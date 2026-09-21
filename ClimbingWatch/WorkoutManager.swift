import Foundation
import HealthKit
import CoreMotion
import Observation
import WatchConnectivity
import WatchKit

/// Watch-side climbing workout: HealthKit session, barometer gain, strain, calories.
@Observable
@MainActor
final class WorkoutManager: NSObject, HKWorkoutSessionDelegate, HKLiveWorkoutBuilderDelegate {
    static let shared = WorkoutManager()

    var isRunning = false
    var isPaused = false
    var startDate: Date?
    var elapsed: TimeInterval = 0
    var verticalGainMeters = 0.0
    var maxAltitude = 0.0
    var verticalSpeedMPerMin = 0.0
    var currentBPM: Int?
    var currentZone: HeartRateZone = .z1
    var activeCalories = 0.0
    var restingCalories = 0.0
    var bodyStressIndex = 0.0
    var cardiovascularStrain = 0.0
    var climbingTime: TimeInterval = 0
    var restingTime: TimeInterval = 0
    var heartRates: [HeartRateSample] = []
    var sessionID = UUID()
    var isStarting = false
    var phase: ClimbPhase = .resting
    var loggedSends: [SessionSend] = []
    var logDiscipline: ClimbDiscipline = .boulder
    var logGrade: String = "V4"
    var gymName: String?
    var gymWalls: [WatchWall] = []
    var walls: [String] = []
    var logWall: String?
    var lastPhoneWall: String?
    var wallPhotos: [String: Data] = [:]
    var logOutcome: ClimbOutcome = .send
    var priorLifetimeGain = 0.0
    var warmupComplete = false
    var restPlan: RestPlan?

    var lifetimeGainMeters: Double {
        LifetimeGainMath.total(persisted: priorLifetimeGain, session: verticalGainMeters)
    }

    var landmarkProgress: LandmarkProgress {
        LandmarkMath.progress(
            gainMeters: lifetimeGainMeters,
            toward: LandmarkMath.sessionTarget(gainMeters: lifetimeGainMeters)
        )
    }

    func cue(at now: Date = Date()) -> WorkoutCue {
        WorkoutCueMath.cue(
            warmupComplete: warmupComplete,
            showWarmedUpUntil: warmupBannerUntil,
            restPlan: restPlan,
            currentBPM: currentBPM,
            now: now
        )
    }

    private let store = HKHealthStore()
    private var workout: HKWorkoutSession?
    private var builder: HKLiveWorkoutBuilder?
    private var altimeter: CMAltimeter?
    private var motion: CMMotionManager?
    private var filter = ElevationFilter()
    private var gainTimeline: [(t: TimeInterval, gain: Double)] = []
    private var zoneSeconds: [HeartRateZone: TimeInterval] = [:]
    private var lastHRAt: Date?
    private var lastTick: Date?
    private var pausedAccumulated: TimeInterval = 0
    private var pauseStartedAt: Date?
    private var tickTask: Task<Void, Never>?
    private var motionMagnitudes: [Double] = []
    private var motionVariance = 0.0
    private var hrvSDNN: Double?
    private var maxHR = StrainMath.defaultMaxHR
    private var weightKg = StrainMath.defaultWeightKg
    private var lastLiveSent: Date?
    private var lastGradeByDiscipline: [ClimbDiscipline: String] = [
        .boulder: "V4",
        .topRope: "5.10a",
        .lead: "5.10a",
    ]
    private var warmupBannerUntil: Date?
    private var didAnnounceWarmup = false
    private var announcedRestID: UUID?
    private var climbingBoutStart: Date?
    private var lastDetectedPhase: ClimbPhase = .resting

    private override init() {
        super.init()
    }

    func startFromButton() {
        guard !isRunning, !isStarting else { return }
        isStarting = true
        Task { await start(skipGuard: true) }
    }

    func start(configuration: HKWorkoutConfiguration = .indoorClimbing, skipGuard: Bool = false) async {
        if !skipGuard {
            guard !isRunning, !isStarting else { return }
            isStarting = true
            isRunning = true
        }
        isPaused = false
        sessionID = UUID()
        let now = Date()
        startDate = now
        lastTick = now
        resetLiveState()
        startTicker()
        broadcastLive()
        WatchCueNotifier.requestAuthorization()
        await authorize()
        if workout != nil {
            await finishWorkout()
        }
        isRunning = true
        loadProfile()
        loadPriorLifetimeGain()
        startAltimeter()
        startMotion()
        do {
            let session = try HKWorkoutSession(healthStore: store, configuration: configuration)
            let live = session.associatedWorkoutBuilder()
            live.dataSource = HKLiveWorkoutDataSource(healthStore: store, workoutConfiguration: configuration)
            session.delegate = self
            live.delegate = self
            workout = session
            builder = live
            session.prepare()
            session.startActivity(with: now)
            try await live.beginCollection(at: now)
        } catch {
            currentBPM = nil
        }
        isStarting = false
        WatchCueNotifier.workoutStarted()
        broadcastLive()
    }

    func pause() {
        guard isRunning, !isPaused else { return }
        isPaused = true
        pauseStartedAt = Date()
        workout?.pause()
        stopSensors()
    }

    func resume() {
        guard isPaused else { return }
        if let pauseStartedAt {
            pausedAccumulated += Date().timeIntervalSince(pauseStartedAt)
        }
        pauseStartedAt = nil
        isPaused = false
        lastTick = Date()
        workout?.resume()
        startAltimeter()
        startMotion()
    }

    func end() async {
        tickTask?.cancel()
        tickTask = nil
        let endDate = Date()
        if isPaused, let pauseStartedAt {
            pausedAccumulated += endDate.timeIntervalSince(pauseStartedAt)
        }
        recompute(now: endDate)
        LifetimeGainStore.addSession(verticalGainMeters)
        priorLifetimeGain = LifetimeGainStore.load()
        let payload = snapshot(endDate: endDate)
        isStarting = false
        lastLiveSent = nil
        send(payload, kind: SummitSync.live)
        await finishWorkout()
        stopSensors()
        isRunning = false
        isPaused = false
        startDate = nil
        send(payload, kind: SummitSync.workoutSummary)
    }

    /// Drop leftover HealthKit / motion if the Start screen is showing.
    func ensureIdle() {
        guard !isRunning, !isStarting else { return }
        tickTask?.cancel()
        tickTask = nil
        stopSensors()
        Task {
            await finishWorkout()
            await WatchWorkoutController.shared.stop()
        }
    }

    func heartRateSamples(from start: TimeInterval, to end: TimeInterval) -> [HeartRateSample] {
        heartRates.filter { $0.timestamp >= start && $0.timestamp <= end }
    }

    func selectLogDiscipline(_ item: ClimbDiscipline) {
        lastGradeByDiscipline[logDiscipline] = logGrade
        logDiscipline = item
        logGrade = lastGradeByDiscipline[item] ?? (item.usesRopeGrades ? "5.10a" : "V4")
    }

    func selectLogGrade(_ grade: String) {
        logGrade = grade
        lastGradeByDiscipline[logDiscipline] = grade
    }

    var currentWallRoutes: [WatchRoutePin] {
        gymWalls.first { $0.name == logWall }?.routes ?? []
    }

    func selectLogWall(_ name: String) {
        logWall = name
    }

    func selectLogOutcome(_ outcome: ClimbOutcome) {
        logOutcome = outcome
    }

    func adoptGym(_ context: WatchGymContext) {
        gymName = context.gymName
        gymWalls = context.walls
        walls = context.wallNames
        logWall = WatchGymContext.pickWall(
            walls: walls,
            phoneCurrent: context.currentWall,
            previousPhoneCurrent: lastPhoneWall,
            watchWall: logWall
        )
        lastPhoneWall = context.currentWall
        wallPhotos = wallPhotos.filter { walls.contains($0.key) }
    }

    func adoptWallPhotos(_ photos: [String: Data]) {
        wallPhotos.merge(photos) { _, new in new }
        wallPhotos = wallPhotos.filter { walls.contains($0.key) }
    }

    func logRoute(_ pin: WatchRoutePin, outcome: ClimbOutcome) {
        logGrade = pin.grade
        logDiscipline = pin.disciplineValue
        logSend(
            grade: pin.grade,
            outcome: outcome,
            discipline: pin.disciplineValue,
            color: pin.color,
            routeLabel: pin.label
        )
    }

    func logSend(
        grade: String,
        outcome: ClimbOutcome,
        discipline: ClimbDiscipline,
        color: String? = nil,
        routeLabel: String? = nil
    ) {
        let send = SessionSend(
            grade: grade,
            outcome: outcome,
            discipline: discipline,
            wall: logWall,
            routeLabel: routeLabel
        )
        loggedSends.insert(send, at: 0)
        if loggedSends.count > 12 {
            loggedSends = Array(loggedSends.prefix(12))
        }
        WKInterfaceDevice.current().play(.success)
        var message: [String: Any] = [
            WatchSync.kind: WatchSync.log,
            WatchSync.grade: grade,
            WatchSync.outcome: outcome.rawValue,
            WatchSync.discipline: discipline.rawValue,
        ]
        if let logWall {
            message[WatchSync.wall] = logWall
        }
        if let color {
            message[WatchSync.color] = color
        }
        if let routeLabel {
            message[WatchSync.routeLabel] = routeLabel
        }
        if let data = try? JSONEncoder().encode(Array(heartRates.suffix(40))) {
            message[WatchSync.heartRates] = data
        }
        beginRest(at: Date())
        if let data = try? JSONEncoder().encode(restPlan) {
            message[WatchSync.rest] = data
        }
        sendWatchMessage(message)
    }

    func skipRest() {
        restPlan = nil
        announcedRestID = nil
        climbingBoutStart = nil
    }

    func beginRest(at date: Date = Date()) {
        let plan = RecoveryMath.plan(
            at: date,
            heartRates: heartRates,
            currentBPM: currentBPM
        )
        restPlan = plan
        announcedRestID = nil
    }

    func snapshot(endDate: Date? = nil, live: Bool = false) -> ClimbSessionPayload {
        ClimbSessionPayload(
            id: sessionID,
            startDate: startDate ?? Date(),
            endDate: endDate,
            totalElevationGain: verticalGainMeters,
            maxAltitude: maxAltitude,
            verticalSpeed: verticalSpeedMPerMin,
            activeCalories: activeCalories,
            restingCalories: restingCalories,
            bodyStressIndex: bodyStressIndex,
            cardiovascularStrain: cardiovascularStrain,
            climbingTime: climbingTime,
            restingTime: restingTime,
            heartRateSeries: live ? Array(heartRates.suffix(90)) : heartRates,
            currentBPM: currentBPM,
            phase: phase,
            elapsed: elapsed,
            isPaused: isPaused
        )
    }

    // MARK: - Sensors

    private func startAltimeter() {
        guard CMAltimeter.isRelativeAltitudeAvailable() else { return }
        let sensor = altimeter ?? CMAltimeter()
        altimeter = sensor
        sensor.startRelativeAltitudeUpdates(to: .main) { [weak self] data, _ in
            guard let self, let data, self.isRunning, !self.isPaused else { return }
            let meters = data.relativeAltitude.doubleValue
            let moving = self.motionVariance >= StrainMath.climbingMotionThreshold
            if self.filter.ingest(meters, countingGain: moving) != nil {
                self.verticalGainMeters = self.filter.gainMeters
                self.maxAltitude = self.filter.maxAltitude
                let t = Date().timeIntervalSince1970
                self.gainTimeline.append((t, self.filter.gainMeters))
                let cutoff = t - 90
                self.gainTimeline.removeAll { $0.t < cutoff }
            } else {
                self.verticalGainMeters = self.filter.gainMeters
            }
        }
    }

    private func startMotion() {
        let sensor = motion ?? CMMotionManager()
        guard sensor.isDeviceMotionAvailable else { return }
        motion = sensor
        sensor.deviceMotionUpdateInterval = 0.2
        sensor.startDeviceMotionUpdates(to: .main) { [weak self] data, _ in
            guard let self, let data, self.isRunning, !self.isPaused else { return }
            let acc = data.userAcceleration
            let mag = sqrt(acc.x * acc.x + acc.y * acc.y + acc.z * acc.z)
            self.motionMagnitudes.append(mag)
            if self.motionMagnitudes.count > 25 {
                self.motionMagnitudes.removeFirst(self.motionMagnitudes.count - 25)
            }
            self.motionVariance = Self.variance(self.motionMagnitudes)
        }
    }

    private func stopSensors() {
        altimeter?.stopRelativeAltitudeUpdates()
        motion?.stopDeviceMotionUpdates()
        altimeter = nil
        motion = nil
    }

    private func startTicker() {
        tickTask?.cancel()
        tickTask = Task { [weak self] in
            while let self, !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                if Task.isCancelled { break }
                await MainActor.run {
                    guard self.isRunning, !self.isPaused else { return }
                    self.recompute(now: Date())
                }
            }
        }
    }

    private func recompute(now: Date) {
        guard let startDate, let lastTick else {
            elapsed = 0
            return
        }
        elapsed = max(0, now.timeIntervalSince(startDate) - pausedAccumulated)
        let dt = now.timeIntervalSince(lastTick)
        self.lastTick = now
        if motionVariance < StrainMath.climbingMotionThreshold {
            verticalSpeedMPerMin = 0
        } else {
            verticalSpeedMPerMin = VerticalSpeed.metersPerMinute(
                samples: gainTimeline,
                now: now.timeIntervalSince1970
            )
        }
        let detected = StrainMath.phase(
            verticalSpeedMPerMin: verticalSpeedMPerMin,
            motionVariance: motionVariance
        )
        phase = detected
        if detected == .climbing {
            climbingTime += dt
            if lastDetectedPhase != .climbing {
                climbingBoutStart = now
                if restPlan != nil { skipRest() }
            }
        } else {
            restingTime += dt
            if lastDetectedPhase == .climbing,
               warmupComplete,
               restPlan == nil,
               let bout = climbingBoutStart,
               now.timeIntervalSince(bout) >= 20 {
                beginRest(at: now)
            }
        }
        lastDetectedPhase = detected
        evaluateCues(now: now)
        if let bpm = currentBPM {
            let zone = HeartRateZone.zone(bpm: bpm, maxHR: maxHR)
            currentZone = zone
            zoneSeconds[zone, default: 0] += dt
        }
        cardiovascularStrain = StrainMath.trimp(zoneSeconds: zoneSeconds)
        bodyStressIndex = StrainMath.bodyStressIndex(
            trimp: cardiovascularStrain,
            elapsed: elapsed,
            motionVariance: motionVariance,
            hrvSDNN: hrvSDNN
        )
        if activeCalories <= 0 {
            activeCalories = StrainMath.calories(met: ClimbPhase.climbing.met, weightKg: weightKg, seconds: climbingTime)
            restingCalories = StrainMath.calories(met: ClimbPhase.resting.met, weightKg: weightKg, seconds: restingTime)
        }
        refreshEnergyFromBuilder()
        broadcastLive()
    }

    private func evaluateCues(now: Date) {
        if !warmupComplete {
            warmupComplete = WarmupMath.isComplete(
                elapsed: elapsed,
                climbingTime: climbingTime,
                gainMeters: verticalGainMeters
            )
        }
        if warmupComplete, !didAnnounceWarmup {
            didAnnounceWarmup = true
            warmupBannerUntil = now.addingTimeInterval(12)
            WatchCueNotifier.warmupComplete()
        }
        if let plan = restPlan {
            let phase = RecoveryMath.phase(plan: plan, now: now, currentBPM: currentBPM)
            if phase.isFinished, announcedRestID != plan.id {
                announcedRestID = plan.id
                WatchCueNotifier.restComplete()
            }
        }
    }

    func adoptLifetimeGain(_ meters: Double) {
        LifetimeGainStore.merge(meters)
        priorLifetimeGain = max(priorLifetimeGain, LifetimeGainStore.load())
    }

    private func loadPriorLifetimeGain() {
        priorLifetimeGain = LifetimeGainStore.load()
    }

    private func refreshEnergyFromBuilder() {
        guard let builder else { return }
        if let type = HKQuantityType.quantityType(forIdentifier: .activeEnergyBurned),
           let stats = builder.statistics(for: type),
           let sum = stats.sumQuantity() {
            activeCalories = sum.doubleValue(for: .kilocalorie())
        }
        if let type = HKQuantityType.quantityType(forIdentifier: .basalEnergyBurned),
           let stats = builder.statistics(for: type),
           let sum = stats.sumQuantity() {
            restingCalories = sum.doubleValue(for: .kilocalorie())
        }
    }

    private func ingestHeartRate(from builder: HKLiveWorkoutBuilder) {
        guard let type = HKQuantityType.quantityType(forIdentifier: .heartRate),
              let stats = builder.statistics(for: type),
              let quantity = stats.mostRecentQuantity() else { return }
        let unit = HKUnit.count().unitDivided(by: .minute())
        let bpm = quantity.doubleValue(for: unit)
        let now = Date()
        currentBPM = Int(bpm.rounded())
        currentZone = HeartRateZone.zone(bpm: currentBPM ?? 0, maxHR: maxHR)
        heartRates.append(HeartRateSample(timestamp: now.timeIntervalSince1970, bpm: bpm))
        lastHRAt = now
        refreshEnergyFromBuilder()
        broadcastLive()
    }

    private func resetLiveState() {
        elapsed = 0
        verticalGainMeters = 0
        maxAltitude = 0
        verticalSpeedMPerMin = 0
        currentBPM = nil
        currentZone = .z1
        activeCalories = 0
        restingCalories = 0
        bodyStressIndex = 0
        cardiovascularStrain = 0
        climbingTime = 0
        restingTime = 0
        heartRates = []
        filter = ElevationFilter()
        gainTimeline = []
        zoneSeconds = [:]
        lastHRAt = nil
        pausedAccumulated = 0
        pauseStartedAt = nil
        motionMagnitudes = []
        motionVariance = 0
        hrvSDNN = nil
        lastLiveSent = nil
        phase = .resting
        loggedSends = []
        warmupComplete = false
        restPlan = nil
        warmupBannerUntil = nil
        didAnnounceWarmup = false
        announcedRestID = nil
        climbingBoutStart = nil
        lastDetectedPhase = .resting
    }

    // MARK: - HealthKit

    private func authorize() async {
        var toShare: Set<HKSampleType> = [HKObjectType.workoutType()]
        var toRead = Set<HKObjectType>()
        let ids: [HKQuantityTypeIdentifier] = [
            .heartRate,
            .heartRateVariabilitySDNN,
            .activeEnergyBurned,
            .basalEnergyBurned,
            .bodyMass,
        ]
        for id in ids {
            if let type = HKObjectType.quantityType(forIdentifier: id) {
                toRead.insert(type)
            }
        }
        if let dob = HKObjectType.characteristicType(forIdentifier: .dateOfBirth) {
            toRead.insert(dob)
        }
        try? await store.requestAuthorization(toShare: toShare, read: toRead)
    }

    private func loadProfile() {
        if let birthday = try? store.dateOfBirthComponents(), let year = birthday.year {
            let age = Calendar.current.component(.year, from: Date()) - year
            maxHR = StrainMath.maxHR(ageYears: age)
        }
        if let type = HKQuantityType.quantityType(forIdentifier: .bodyMass) {
            let query = HKSampleQuery(
                sampleType: type,
                predicate: nil,
                limit: 1,
                sortDescriptors: [NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: false)]
            ) { [weak self] _, samples, _ in
                let kg = (samples?.first as? HKQuantitySample)?
                    .quantity.doubleValue(for: .gramUnit(with: .kilo))
                Task { @MainActor in
                    if let kg { self?.weightKg = kg }
                }
            }
            store.execute(query)
        }
        if let type = HKQuantityType.quantityType(forIdentifier: .heartRateVariabilitySDNN) {
            let query = HKSampleQuery(
                sampleType: type,
                predicate: nil,
                limit: 1,
                sortDescriptors: [NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: false)]
            ) { [weak self] _, samples, _ in
                let ms = (samples?.first as? HKQuantitySample)?
                    .quantity.doubleValue(for: HKUnit.secondUnit(with: .milli))
                Task { @MainActor in
                    self?.hrvSDNN = ms
                }
            }
            store.execute(query)
        }
    }

    private func finishWorkout() async {
        workout?.end()
        try? await builder?.endCollection(at: Date())
        _ = try? await builder?.finishWorkout()
        workout = nil
        builder = nil
    }

    private func broadcastLive() {
        let now = Date()
        if let lastLiveSent, now.timeIntervalSince(lastLiveSent) < 1 { return }
        lastLiveSent = now
        send(snapshot(live: true), kind: SummitSync.live)
    }

    private func send(_ payload: ClimbSessionPayload, kind: String) {
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        guard let data = try? JSONEncoder().encode(payload) else { return }
        let message: [String: Any] = [
            SummitSync.kind: kind,
            SummitSync.payload: data,
        ]
        if kind == SummitSync.live {
            try? session.updateApplicationContext(message)
        }
        guard session.activationState == .activated else { return }
        if session.isReachable {
            session.sendMessage(message, replyHandler: { _ in }, errorHandler: { _ in
                if kind != SummitSync.live {
                    session.transferUserInfo(message)
                }
            })
        } else if kind != SummitSync.live {
            session.transferUserInfo(message)
        }
    }

    private func sendWatchMessage(_ message: [String: Any]) {
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        guard session.activationState == .activated else {
            session.transferUserInfo(message)
            return
        }
        if session.isReachable {
            session.sendMessage(message, replyHandler: { _ in }, errorHandler: { _ in
                session.transferUserInfo(message)
            })
        } else {
            session.transferUserInfo(message)
        }
    }

    private static func variance(_ values: [Double]) -> Double {
        guard values.count > 1 else { return 0 }
        let mean = values.reduce(0, +) / Double(values.count)
        let sum = values.reduce(0) { $0 + ($1 - mean) * ($1 - mean) }
        return sum / Double(values.count)
    }

    // MARK: - HK delegates

    nonisolated func workoutSession(
        _ workoutSession: HKWorkoutSession,
        didChangeTo toState: HKWorkoutSessionState,
        from fromState: HKWorkoutSessionState,
        date: Date
    ) {
        Task { @MainActor in
            if toState == .paused { self.isPaused = true }
            if toState == .running {
                self.isPaused = false
                self.isRunning = true
            }
            // Do not clear `isRunning` on `.ended`. A leftover or failed
            // HealthKit session can emit `.ended` after Start, which used
            // to bounce the UI back to the Start button. `end()` owns stop.
        }
    }

    nonisolated func workoutSession(_ workoutSession: HKWorkoutSession, didFailWithError error: Error) {}

    nonisolated func workoutBuilderDidCollectEvent(_ workoutBuilder: HKLiveWorkoutBuilder) {}

    nonisolated func workoutBuilder(
        _ workoutBuilder: HKLiveWorkoutBuilder,
        didCollectDataOf collectedTypes: Set<HKSampleType>
    ) {
        Task { @MainActor in
            if let heart = HKQuantityType.quantityType(forIdentifier: .heartRate),
               collectedTypes.contains(heart) {
                self.ingestHeartRate(from: workoutBuilder)
            }
            self.refreshEnergyFromBuilder()
        }
    }
}

/// A send logged from the Watch during the current workout.
struct SessionSend: Identifiable, Equatable {
    var id = UUID()
    var grade: String
    var outcome: ClimbOutcome
    var discipline: ClimbDiscipline
    var wall: String?
    var routeLabel: String?
}

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
    var isLocked = false
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

    var landmarkProgress: LandmarkProgress {
        LandmarkMath.progress(
            gainMeters: verticalGainMeters,
            toward: LandmarkMath.sessionTarget(gainMeters: verticalGainMeters)
        )
    }

    private let store = HKHealthStore()
    private var workout: HKWorkoutSession?
    private var builder: HKLiveWorkoutBuilder?
    private let altimeter = CMAltimeter()
    private let motion = CMMotionManager()
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

    private override init() {
        super.init()
    }

    func prepare() {
        Task { await authorize() }
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
        isLocked = false
        sessionID = UUID()
        let now = Date()
        startDate = now
        lastTick = now
        resetLiveState()
        startTicker()
        broadcastLive()
        await authorize()
        if workout != nil {
            await finishWorkout()
        }
        isRunning = true
        loadProfile()
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
        broadcastLive()
    }

    func pause() {
        guard isRunning, !isPaused else { return }
        isPaused = true
        pauseStartedAt = Date()
        workout?.pause()
        altimeter.stopRelativeAltitudeUpdates()
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
    }

    func lock() {
        isLocked = true
        WKExtension.shared().enableWaterLock()
    }

    func end() async {
        tickTask?.cancel()
        tickTask = nil
        let endDate = Date()
        if isPaused, let pauseStartedAt {
            pausedAccumulated += endDate.timeIntervalSince(pauseStartedAt)
        }
        recompute(now: endDate)
        let payload = snapshot(endDate: endDate)
        isStarting = false
        lastLiveSent = nil
        send(payload, kind: SummitSync.live)
        await finishWorkout()
        stopSensors()
        isRunning = false
        isPaused = false
        isLocked = false
        startDate = nil
        send(payload, kind: SummitSync.workoutSummary)
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
        altimeter.startRelativeAltitudeUpdates(to: .main) { [weak self] data, _ in
            guard let self, let data, self.isRunning, !self.isPaused else { return }
            let meters = data.relativeAltitude.doubleValue
            if self.filter.ingest(meters) != nil {
                self.verticalGainMeters = self.filter.gainMeters
                self.maxAltitude = self.filter.maxAltitude
                let t = Date().timeIntervalSince1970
                self.gainTimeline.append((t, self.filter.gainMeters))
                let cutoff = t - 90
                self.gainTimeline.removeAll { $0.t < cutoff }
            }
        }
    }

    private func startMotion() {
        guard motion.isDeviceMotionAvailable else { return }
        motion.deviceMotionUpdateInterval = 0.2
        motion.startDeviceMotionUpdates(to: .main) { [weak self] data, _ in
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
        altimeter.stopRelativeAltitudeUpdates()
        motion.stopDeviceMotionUpdates()
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
        let detected = StrainMath.phase(
            verticalSpeedMPerMin: verticalSpeedMPerMin,
            motionVariance: motionVariance
        )
        phase = detected
        if detected == .climbing {
            climbingTime += dt
        } else {
            restingTime += dt
        }
        verticalSpeedMPerMin = VerticalSpeed.metersPerMinute(
            samples: gainTimeline,
            now: now.timeIntervalSince1970
        )
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

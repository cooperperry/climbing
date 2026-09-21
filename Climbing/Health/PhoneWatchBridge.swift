import Foundation
import HealthKit
import Observation
import SwiftData
import WatchConnectivity

/// Phone-side WatchConnectivity: session logging from the Watch, live BPM,
/// and snapshots so the Watch UI matches iPhone.
@Observable
@MainActor
final class PhoneWatchBridge: NSObject, WCSessionDelegate {
    static let shared = PhoneWatchBridge()

    let health = HealthManager()
    var liveBPM: Int?
    var liveWorkout: ClimbSessionPayload?
    var liveReceivedAt: Date?
    var selectedGrade: String?
    var selectedStyle: ClimbStyle = .crimp
    var restPlan: RestPlan?

    private var context: ModelContext?
    private var lastLiveSave: Date?
    private var session: WCSession? {
        WCSession.isSupported() ? .default : nil
    }

    private override init() {
        super.init()
        session?.delegate = self
        session?.activate()
    }

    func attach(context: ModelContext) {
        self.context = context
        publishSnapshot()
    }

    /// Starts a phone session and the Watch workout. Used by Shortcuts
    /// (Arrive at gym) as well as the in-app Start button path.
    func startClimbingWorkout(gymID: UUID? = nil) {
        if let context {
            if let gymID {
                setCurrentGym(id: gymID, in: context)
            }
            startSession(in: context)
            publishSnapshot()
        }
        send([WatchSync.kind: WatchSync.start])
    }

    func gymEntities(matching ids: [UUID]? = nil) -> [GymEntity] {
        guard let context else { return [] }
        let gyms = (try? context.fetch(
            FetchDescriptor<ClimbGym>(sortBy: [SortDescriptor(\.joinedAt, order: .reverse)])
        )) ?? []
        let selected = ids.map { wanted in gyms.filter { wanted.contains($0.id) } } ?? gyms
        return selected.map { GymEntity(id: $0.id, name: $0.name) }
    }

    private func setCurrentGym(id: UUID, in context: ModelContext) {
        let gyms = (try? context.fetch(FetchDescriptor<ClimbGym>())) ?? []
        guard gyms.contains(where: { $0.id == id }) else { return }
        for gym in gyms {
            gym.isCurrent = gym.id == id
        }
        try? context.save()
    }

    func startWatchSide() {
        send([WatchSync.kind: WatchSync.start])
        Task { await health.startWatchWorkout() }
        publishSnapshot()
    }

    func stopWatchSide() {
        send([WatchSync.kind: WatchSync.stop])
        liveBPM = nil
        liveWorkout = nil
        liveReceivedAt = nil
        restPlan = nil
        publishSnapshot()
    }

    func beginRest(heartRates: [HeartRateSample] = [], currentBPM: Int? = nil, plan: RestPlan? = nil) {
        restPlan = plan ?? RecoveryMath.plan(
            at: .now,
            heartRates: heartRates,
            currentBPM: currentBPM ?? liveBPM
        )
        publishSnapshot()
    }

    func skipRest() {
        restPlan = nil
        send([WatchSync.kind: WatchSync.skipRest])
        publishSnapshot()
    }

    func heartRates(from start: Date, to end: Date) async -> [HeartRateSample] {
        guard let session, session.activationState == .activated, session.isReachable else {
            return []
        }
        return await withCheckedContinuation { continuation in
            session.sendMessage(
                [
                    WatchSync.kind: WatchSync.heartRates,
                    WatchSync.from: start.timeIntervalSince1970,
                    WatchSync.to: end.timeIntervalSince1970,
                ],
                replyHandler: { reply in
                    let samples: [HeartRateSample]
                    if let data = reply[WatchSync.heartRates] as? Data {
                        samples = (try? JSONDecoder().decode([HeartRateSample].self, from: data)) ?? []
                    } else {
                        samples = []
                    }
                    continuation.resume(returning: samples)
                },
                errorHandler: { _ in
                    continuation.resume(returning: [])
                }
            )
        }
    }

    func publishSnapshot() {
        guard let context, let data = try? JSONEncoder().encode(makeSnapshot(in: context)) else { return }
        let gymData = (try? JSONEncoder().encode(gymContext(in: context))) ?? Data()
        let contextMessage: [String: Any] = [
            WatchSync.kind: WatchSync.snapshot,
            WatchSync.payload: data,
            WatchSync.lifetimeGain: lifetimeGain(in: context),
            WatchSync.gym: gymData,
        ]
        try? session?.updateApplicationContext(contextMessage)
        guard session?.isReachable == true else { return }
        var live = contextMessage
        if let photos = try? JSONEncoder().encode(wallPhotos(in: context)) {
            live[WatchSync.wallPhotos] = photos
        }
        session?.sendMessage(
            live,
            replyHandler: { _ in },
            errorHandler: { _ in }
        )
    }

    // MARK: - Incoming Watch commands

    private func handle(_ message: [String: Any], replyHandler: (([String: Any]) -> Void)?) {
        let kind = message[WatchSync.kind] as? String
        if kind == WatchSync.bpm {
            if let value = message[WatchSync.value] as? Int {
                liveBPM = value
            }
            replyHandler?([:])
            return
        }
        if kind == WatchSync.skipRest {
            restPlan = nil
            publishSnapshot()
            replyHandler?([:])
            return
        }
        if kind == SummitSync.live || kind == SummitSync.workoutSummary {
            ingestLiveOrSummary(message, finished: kind == SummitSync.workoutSummary)
            replyHandler?([:])
            return
        }
        guard let context, let kind else {
            replyHandler?([:])
            return
        }
        switch kind {
        case WatchSync.start:
            startSession(in: context)
        case WatchSync.stop:
            endSession(in: context)
        case WatchSync.log:
            log(from: message, in: context)
        case WatchSync.undo:
            undoLast(in: context)
        default:
            break
        }
        publishSnapshot()
        if let data = try? JSONEncoder().encode(makeSnapshot(in: context)) {
            replyHandler?([WatchSync.payload: data])
        } else {
            replyHandler?([:])
        }
    }

    private func ingestLiveOrSummary(_ message: [String: Any], finished: Bool) {
        guard let data = message[SummitSync.payload] as? Data,
              let payload = try? JSONDecoder().decode(ClimbSessionPayload.self, from: data) else { return }
        liveBPM = payload.currentBPM
        if payload.isLive && !finished {
            liveWorkout = payload
            liveReceivedAt = Date()
            upsertSession(payload, throttle: true)
        } else {
            liveWorkout = nil
            liveReceivedAt = nil
            upsertSession(payload, throttle: false)
            publishSnapshot()
        }
    }

    private func upsertSession(_ payload: ClimbSessionPayload, throttle: Bool) {
        guard let context else { return }
        if throttle {
            let now = Date()
            if let lastLiveSave, now.timeIntervalSince(lastLiveSave) < 2 { return }
            lastLiveSave = now
        }
        let existing = (try? context.fetch(FetchDescriptor<ClimbSession>())) ?? []
        if let match = existing.first(where: { $0.id == payload.id }) {
            match.apply(payload)
        } else {
            context.insert(ClimbSession(payload: payload))
        }
        try? context.save()
    }

    private func startSession(in context: ModelContext) {
        seedScaleIfNeeded(in: context)
        if activeSession(in: context) == nil {
            context.insert(ClimbingSession())
            try? context.save()
        }
        Task { await health.startWatchWorkout() }
    }

    private func endSession(in context: ModelContext) {
        guard let session = activeSession(in: context) else { return }
        session.endTime = .now
        try? context.save()
        liveBPM = nil
        restPlan = nil
    }

    private func log(from message: [String: Any], in context: ModelContext) {
        seedScaleIfNeeded(in: context)
        let session: ClimbingSession
        if let existing = activeSession(in: context) {
            session = existing
        } else {
            let created = ClimbingSession()
            context.insert(created)
            session = created
        }
        let discipline = (message[WatchSync.discipline] as? String)
            .flatMap(ClimbDiscipline.init(rawValue:)) ?? .boulder
        let scale = scale(for: discipline, in: context)
        let grade = (message[WatchSync.grade] as? String)
            ?? selectedGrade
            ?? scale?.grades.first
        guard let grade else { return }
        let outcome = ClimbOutcome(rawValue: message[WatchSync.outcome] as? String ?? "") ?? .attempt
        let style = (message[WatchSync.style] as? String).flatMap(ClimbStyle.init(rawValue:))
        if let style { selectedStyle = style }
        selectedGrade = grade
        let previousLogAt = session.logs.map(\.loggedAt).max()
        let gym = currentGym(in: context)
        let wall = (message[WatchSync.wall] as? String)
            .flatMap { name in
                let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
                return trimmed.isEmpty ? nil : trimmed
            }
            ?? gym?.currentWallName
        if let gym, let wall {
            gym.currentWallName = wall
        }
        let colorName = message[WatchSync.color] as? String
        let routeLabel = (message[WatchSync.routeLabel] as? String)
            ?? colorName.flatMap { name in
                HoldColor(rawValue: name).map { "\($0.displayName) \(grade)" }
            }
        let entry = ClimbLog(
            gradeLabel: grade,
            attempts: outcome == .flash ? 1 : (outcome == .send ? 2 : 1),
            outcome: outcome,
            style: style,
            discipline: discipline,
            gym: gym,
            areaName: wall,
            routeLabel: routeLabel,
            session: session,
            gradeScale: scale
        )
        context.insert(entry)
        try? context.save()
        var incomingHR: [HeartRateSample] = []
        if let data = message[WatchSync.heartRates] as? Data {
            incomingHR = (try? JSONDecoder().decode([HeartRateSample].self, from: data)) ?? []
        }
        if let data = message[WatchSync.rest] as? Data,
           let plan = try? JSONDecoder().decode(RestPlan.self, from: data) {
            restPlan = plan
        } else {
            restPlan = RecoveryMath.plan(at: entry.loggedAt, heartRates: incomingHR, currentBPM: liveBPM)
        }
        if outcome.isCompletion {
            Task { await captureEffort(for: entry, in: session, previousLogAt: previousLogAt, watchSamples: incomingHR) }
        }
    }

    private func undoLast(in context: ModelContext) {
        guard let session = activeSession(in: context),
              let last = session.logs.max(by: { $0.loggedAt < $1.loggedAt }) else { return }
        context.delete(last)
        try? context.save()
        restPlan = nil
        send([WatchSync.kind: WatchSync.skipRest])
    }

    private func captureEffort(
        for entry: ClimbLog,
        in session: ClimbingSession,
        previousLogAt: Date?,
        watchSamples: [HeartRateSample]
    ) async {
        let bounds = EffortWindow.bounds(
            loggedAt: entry.loggedAt,
            sessionStart: session.startTime,
            previousLogAt: previousLogAt
        )
        let remote = watchSamples.isEmpty
            ? await heartRates(from: bounds.start, to: bounds.end)
            : watchSamples
        let healthSamples = await health.heartRateTimeline(from: bounds.start, to: bounds.end)
        let merged = remote.isEmpty ? healthSamples : remote
        var trace = EffortMath.trace(heartRates: merged, start: bounds.start, end: bounds.end)
        #if targetEnvironment(simulator)
        if !trace.hasData { trace = .demo }
        #endif
        if trace.hasData {
            entry.effortTrace = trace
            try? context?.save()
            publishSnapshot()
        }
    }

    private func activeSession(in context: ModelContext) -> ClimbingSession? {
        var descriptor = FetchDescriptor<ClimbingSession>(
            predicate: #Predicate { $0.endTime == nil },
            sortBy: [SortDescriptor(\.startTime, order: .reverse)]
        )
        descriptor.fetchLimit = 1
        return try? context.fetch(descriptor).first
    }

    private func defaultScale(in context: ModelContext) -> CustomGradeScale? {
        let scales = (try? context.fetch(FetchDescriptor<CustomGradeScale>(sortBy: [SortDescriptor(\.createdAt)]))) ?? []
        return scales.first { $0.isDefault } ?? scales.first
    }

    private func scale(for discipline: ClimbDiscipline, in context: ModelContext) -> CustomGradeScale? {
        let kind: GradeScaleKind = discipline.usesRopeGrades ? .yds : .boulderVScale
        let scales = (try? context.fetch(FetchDescriptor<CustomGradeScale>())) ?? []
        return scales.first { $0.kind == kind } ?? defaultScale(in: context)
    }

    private func seedScaleIfNeeded(in context: ModelContext) {
        let scales = (try? context.fetch(FetchDescriptor<CustomGradeScale>())) ?? []
        if scales.contains(where: { $0.kind == .boulderVScale }) == false {
            context.insert(CustomGradeScale(template: .standardVScale(), isDefault: true))
        }
        if scales.contains(where: { $0.kind == .yds }) == false {
            context.insert(CustomGradeScale(template: .standardYDS()))
        }
        try? context.save()
    }

    private func currentGym(in context: ModelContext) -> ClimbGym? {
        var descriptor = FetchDescriptor<ClimbGym>(
            predicate: #Predicate { $0.isCurrent == true }
        )
        descriptor.fetchLimit = 1
        return try? context.fetch(descriptor).first
    }

    private func gymContext(in context: ModelContext) -> WatchGymContext {
        guard let gym = currentGym(in: context) else { return .empty }
        let areas = gym.areas.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        let walls = areas.map { area in
            WatchWall(
                name: area.name,
                routes: area.routes
                    .sorted { $0.createdAt < $1.createdAt }
                    .map {
                        WatchRoutePin(
                            id: $0.id.uuidString,
                            grade: $0.grade,
                            color: $0.colorName,
                            x: $0.x,
                            y: $0.y,
                            discipline: $0.disciplineRaw
                        )
                    }
            )
        }
        let current = WatchGymContext.pickWall(
            walls: walls.map(\.name),
            phoneCurrent: gym.currentWallName,
            previousPhoneCurrent: nil,
            watchWall: gym.currentWallName
        )
        return WatchGymContext(gymName: gym.name, walls: walls, currentWall: current)
    }

    private func wallPhotos(in context: ModelContext) -> [String: Data] {
        guard let gym = currentGym(in: context) else { return [:] }
        var photos: [String: Data] = [:]
        for area in gym.areas {
            guard let data = area.photoData, let thumb = WallPhotoSync.thumbnail(data) else { continue }
            photos[area.name] = thumb
        }
        return photos
    }

    private func lifetimeGain(in context: ModelContext) -> Double {
        let workouts = (try? context.fetch(FetchDescriptor<ClimbSession>())) ?? []
        return workouts.filter { $0.endDate != nil }.reduce(0) { $0 + $1.totalElevationGain }
    }

    private func makeSnapshot(in context: ModelContext) -> WatchSnapshot {
        let session = activeSession(in: context)
        let scale = defaultScale(in: context)
        let logs = session?.logs.sorted { $0.loggedAt > $1.loggedAt } ?? []
        let lastCompletion = logs.first { $0.outcome.isCompletion }
        let allLogs = (try? context.fetch(FetchDescriptor<ClimbLog>())) ?? []
        let points = allLogs.reduce(0) { $0 + $1.points }
        let level = ScoreEngine.level(forTotalPoints: points)
        let sends = allLogs.filter { $0.outcome.isCompletion }
        let hardest = sends.max { $0.gradeIndex < $1.gradeIndex }?.gradeLabel
        let insight = StyleWeakSpotMath.insight(
            logs: allLogs.compactMap { log in
                guard let style = log.style else { return nil }
                return StyleLog(style: style, outcome: log.outcome, loggedAt: log.loggedAt)
            },
            now: Date()
        )
        return WatchSnapshot(
            isActive: session != nil,
            startTime: session?.startTime.timeIntervalSince1970,
            grades: scale?.grades ?? GradeScaleTemplate.standardVScale().grades,
            selectedGrade: selectedGrade ?? scale?.grades.first,
            selectedStyle: selectedStyle.rawValue,
            climbs: session?.logs.count ?? 0,
            sends: session?.completionCount ?? 0,
            score: session?.score ?? 0,
            logs: logs.prefix(8).map {
                WatchLogDTO(
                    id: $0.loggedAt.timeIntervalSince1970.description,
                    grade: $0.gradeLabel,
                    outcome: $0.outcome.rawValue,
                    style: $0.style?.rawValue ?? "",
                    loggedAt: $0.loggedAt.timeIntervalSince1970
                )
            },
            lastTrace: lastCompletion?.effortTrace,
            lastTraceTitle: lastCompletion.map { "\($0.gradeLabel) \($0.outcome.displayName)" },
            lifetimeClimbs: allLogs.count,
            lifetimeSends: sends.count,
            lifetimeFlashes: allLogs.filter { $0.outcome == .flash }.count,
            lifetimePoints: points,
            hardestSend: hardest,
            levelNumber: level.number,
            levelTitle: level.title,
            rest: session != nil ? restPlan : nil,
            styleHeadline: insight.headline
        )
    }

    private func send(_ message: [String: Any]) {
        guard let session, session.activationState == .activated else { return }
        if session.isReachable {
            session.sendMessage(message, replyHandler: { _ in }, errorHandler: { _ in
                session.transferUserInfo(message)
            })
        } else {
            session.transferUserInfo(message)
        }
    }

    // MARK: - WCSessionDelegate

    nonisolated func session(
        _ session: WCSession,
        activationDidCompleteWith activationState: WCSessionActivationState,
        error: Error?
    ) {
        Task { @MainActor in self.publishSnapshot() }
    }

    nonisolated func sessionDidBecomeInactive(_ session: WCSession) {}

    nonisolated func sessionDidDeactivate(_ session: WCSession) {
        session.activate()
    }

    nonisolated func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        Task { @MainActor in self.handle(message, replyHandler: nil) }
    }

    nonisolated func session(
        _ session: WCSession,
        didReceiveMessage message: [String: Any],
        replyHandler: @escaping ([String: Any]) -> Void
    ) {
        Task { @MainActor in self.handle(message, replyHandler: replyHandler) }
    }

    nonisolated func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any] = [:]) {
        Task { @MainActor in self.handle(userInfo, replyHandler: nil) }
    }

    nonisolated func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        Task { @MainActor in self.handle(applicationContext, replyHandler: nil) }
    }
}

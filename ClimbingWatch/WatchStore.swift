import Foundation
import Observation
import WatchConnectivity
import WatchKit

/// Watch-side session mirror. Phone owns SwiftData; this keeps the Watch UI live.
@Observable
@MainActor
final class WatchStore: NSObject, WCSessionDelegate {
    static let shared = WatchStore()

    var snapshot = WatchSnapshot.empty
    var selectedGrade: String?
    var toast: String?
    var logPulse = 0
    var restPlan: RestPlan?

    private var skippedRestID: UUID?
    private var lastReadyHaptic: UUID?

    private var session: WCSession? {
        WCSession.isSupported() ? .default : nil
    }

    var liveBPM: Int? { WorkoutManager.shared.currentBPM }

    var grades: [String] {
        let list = snapshot.grades
        return list.isEmpty ? GradeScaleTemplate.standardVScale().grades : list
    }

    private override init() {
        super.init()
        if snapshot.grades.isEmpty {
            selectedGrade = GradeScaleTemplate.standardVScale().grades.first
        }
        session?.delegate = self
        session?.activate()
    }

    func startSession() {
        snapshot.isActive = true
        snapshot.startTime = Date().timeIntervalSince1970
        if snapshot.grades.isEmpty {
            snapshot.grades = GradeScaleTemplate.standardVScale().grades
        }
        selectedGrade = selectedGrade ?? snapshot.selectedGrade ?? snapshot.grades.first
        send([WatchSync.kind: WatchSync.start])
        Task { await WorkoutManager.shared.start() }
    }

    func endSession() {
        send([WatchSync.kind: WatchSync.stop])
        snapshot.isActive = false
        snapshot.startTime = nil
        restPlan = nil
        Task { await WorkoutManager.shared.end() }
    }

    func log(outcome: ClimbOutcome) {
        guard let grade = selectedGrade ?? snapshot.selectedGrade else { return }
        let plan = RecoveryMath.plan(
            at: Date(),
            heartRates: WorkoutManager.shared.heartRates,
            currentBPM: WorkoutManager.shared.currentBPM
        )
        restPlan = plan
        skippedRestID = nil
        var message: [String: Any] = [
            WatchSync.kind: WatchSync.log,
            WatchSync.outcome: outcome.rawValue,
            WatchSync.grade: grade,
        ]
        if let wall = WorkoutManager.shared.logWall {
            message[WatchSync.wall] = wall
        }
        if let data = try? JSONEncoder().encode(Array(WorkoutManager.shared.heartRates.suffix(40))) {
            message[WatchSync.heartRates] = data
        }
        if let data = try? JSONEncoder().encode(plan) {
            message[WatchSync.rest] = data
        }
        if outcome.isCompletion, !WorkoutManager.shared.heartRates.isEmpty {
            snapshot.lastTrace = EffortMath.trace(
                heartRates: Array(WorkoutManager.shared.heartRates.suffix(40)),
                start: Date().addingTimeInterval(-EffortWindow.maximum),
                end: .now
            )
            snapshot.lastTraceTitle = "\(grade) \(outcome.displayName)"
        }
        send(message)
        toast = "\(grade) \(outcome.displayName)"
        logPulse += 1
        WKInterfaceDevice.current().play(.success)
        Task {
            try? await Task.sleep(for: .seconds(1.2))
            if toast == "\(grade) \(outcome.displayName)" { toast = nil }
        }
    }

    func undo() {
        send([WatchSync.kind: WatchSync.undo])
        if !snapshot.logs.isEmpty {
            snapshot.logs.removeFirst()
        }
        skipRest()
    }

    func skipRest(notifyPhone: Bool = true) {
        skippedRestID = restPlan?.id
        restPlan = nil
        if notifyPhone {
            send([WatchSync.kind: WatchSync.skipRest])
        }
    }

    func evaluateRest(now: Date = Date()) {
        guard let plan = restPlan else { return }
        let phase = RecoveryMath.phase(
            plan: plan,
            now: now,
            currentBPM: WorkoutManager.shared.currentBPM ?? liveBPM
        )
        if phase.isFinished, lastReadyHaptic != plan.id {
            lastReadyHaptic = plan.id
            WKInterfaceDevice.current().play(.notification)
        }
    }

    func requestGymMap() {
        send([WatchSync.kind: WatchSync.refresh])
    }

    func broadcastBPM() {
        guard let bpm = WorkoutManager.shared.currentBPM else { return }
        send([WatchSync.kind: WatchSync.bpm, WatchSync.value: bpm])
    }

    private func apply(_ data: Data) {
        guard let snap = try? JSONDecoder().decode(WatchSnapshot.self, from: data) else { return }
        snapshot = snap
        if selectedGrade == nil { selectedGrade = snap.selectedGrade ?? snap.grades.first }
        if !snap.isActive {
            restPlan = nil
        } else if let rest = snap.rest, rest.id != skippedRestID {
            restPlan = rest
        }
    }

    private func ingestLifetimeGain(_ message: [String: Any]) {
        let raw = message[WatchSync.lifetimeGain]
        let gain = (raw as? Double) ?? (raw as? NSNumber)?.doubleValue
        guard let gain else { return }
        WorkoutManager.shared.adoptLifetimeGain(gain)
    }

    private func ingestGym(_ message: [String: Any]) {
        guard let data = message[WatchSync.gym] as? Data,
              let gym = try? JSONDecoder().decode(WatchGymContext.self, from: data) else { return }
        WorkoutManager.shared.adoptGym(gym)
    }

    private func ingestPhoneContext(_ message: [String: Any]) {
        ingestLifetimeGain(message)
        ingestGym(message)
        ingestWallPhotos(message)
    }

    private func ingestWallPhotos(_ message: [String: Any]) {
        let photos: [String: Data]
        if let data = message[WatchSync.wallPhotos] as? Data,
           let decoded = try? JSONDecoder().decode([String: Data].self, from: data) {
            photos = decoded
        } else if let typed = message[WatchSync.wallPhotos] as? [String: Data] {
            photos = typed
        } else if let raw = message[WatchSync.wallPhotos] as? [String: Any] {
            var typed: [String: Data] = [:]
            for (key, value) in raw {
                if let data = value as? Data { typed[key] = data }
            }
            photos = typed
        } else {
            return
        }
        guard photos.isEmpty == false else { return }
        WorkoutManager.shared.adoptWallPhotos(photos)
    }

    private func send(_ message: [String: Any]) {
        guard let session, session.activationState == .activated else { return }
        if session.isReachable {
            session.sendMessage(message, replyHandler: { [weak self] reply in
                Task { @MainActor in
                    if let data = reply[WatchSync.payload] as? Data {
                        self?.apply(data)
                    }
                    self?.ingestPhoneContext(reply)
                }
            }, errorHandler: { _ in
                session.transferUserInfo(message)
            })
        } else {
            session.transferUserInfo(message)
        }
    }

    nonisolated func session(
        _ session: WCSession,
        activationDidCompleteWith activationState: WCSessionActivationState,
        error: Error?
    ) {
        guard activationState == .activated else { return }
        let context = session.receivedApplicationContext
        Task { @MainActor in
            if let data = context[WatchSync.payload] as? Data {
                self.apply(data)
            }
            self.ingestPhoneContext(context)
            self.requestGymMap()
        }
    }

    nonisolated func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        if let data = applicationContext[WatchSync.payload] as? Data {
            Task { @MainActor in self.apply(data) }
        }
        Task { @MainActor in self.ingestPhoneContext(applicationContext) }
    }

    nonisolated func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any] = [:]) {
        Task { @MainActor in self.ingestPhoneContext(userInfo) }
    }

    nonisolated func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        Task { @MainActor in
            if let data = message[WatchSync.payload] as? Data {
                self.apply(data)
            }
            self.ingestPhoneContext(message)
            let kind = message[WatchSync.kind] as? String
            if kind == WatchSync.start {
                await WorkoutManager.shared.start()
            }
            if kind == WatchSync.stop {
                await WorkoutManager.shared.end()
            }
            if kind == WatchSync.skipRest {
                self.skipRest(notifyPhone: false)
            }
        }
    }

    nonisolated func session(
        _ session: WCSession,
        didReceiveMessage message: [String: Any],
        replyHandler: @escaping ([String: Any]) -> Void
    ) {
        let kind = message[WatchSync.kind] as? String
        if kind == WatchSync.start || kind == WatchSync.stop {
            replyHandler([:])
            Task { @MainActor in
                if kind == WatchSync.start {
                    await WorkoutManager.shared.start()
                } else {
                    await WorkoutManager.shared.end()
                }
            }
            return
        }
        let reply: [String: Any] = DispatchQueue.main.sync {
            MainActor.assumeIsolated {
                switch kind {
                case WatchSync.heartRates:
                    let from = message[WatchSync.from] as? TimeInterval ?? 0
                    let to = message[WatchSync.to] as? TimeInterval ?? Date().timeIntervalSince1970
                    let payload = (try? JSONEncoder().encode(
                        WorkoutManager.shared.heartRateSamples(from: from, to: to)
                    )) ?? Data()
                    return [WatchSync.heartRates: payload]
                case WatchSync.skipRest:
                    self.skipRest(notifyPhone: false)
                    return [:]
                default:
                    if let data = message[WatchSync.payload] as? Data {
                        self.apply(data)
                    }
                    self.ingestPhoneContext(message)
                    return [:]
                }
            }
        }
        replyHandler(reply)
    }
}

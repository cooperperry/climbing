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

    var liveBPM: Int? { WatchWorkoutController.shared.currentBPM }

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
        Task { await WatchWorkoutController.shared.start() }
    }

    func endSession() {
        send([WatchSync.kind: WatchSync.stop])
        snapshot.isActive = false
        snapshot.startTime = nil
        restPlan = nil
        Task { await WatchWorkoutController.shared.stop() }
    }

    func log(outcome: ClimbOutcome) {
        guard let grade = selectedGrade ?? snapshot.selectedGrade else { return }
        let plan = RecoveryMath.plan(
            at: Date(),
            heartRates: WatchWorkoutController.shared.recentHeartRates(seconds: RecoveryMath.effortWindow),
            currentBPM: WatchWorkoutController.shared.currentBPM
        )
        restPlan = plan
        skippedRestID = nil
        var message: [String: Any] = [
            WatchSync.kind: WatchSync.log,
            WatchSync.outcome: outcome.rawValue,
            WatchSync.grade: grade,
        ]
        if let data = try? JSONEncoder().encode(WatchWorkoutController.shared.recentHeartRates()) {
            message[WatchSync.heartRates] = data
        }
        if let data = try? JSONEncoder().encode(plan) {
            message[WatchSync.rest] = data
        }
        if outcome.isCompletion, !WatchWorkoutController.shared.recentHeartRates().isEmpty {
            snapshot.lastTrace = EffortMath.trace(
                heartRates: WatchWorkoutController.shared.recentHeartRates(),
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
            currentBPM: WatchWorkoutController.shared.currentBPM ?? liveBPM
        )
        if phase.isFinished, lastReadyHaptic != plan.id {
            lastReadyHaptic = plan.id
            WKInterfaceDevice.current().play(.notification)
        }
    }

    func broadcastBPM() {
        guard let bpm = WatchWorkoutController.shared.currentBPM else { return }
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

    private func send(_ message: [String: Any]) {
        guard let session, session.activationState == .activated else { return }
        if session.isReachable {
            session.sendMessage(message, replyHandler: { [weak self] reply in
                if let data = reply[WatchSync.payload] as? Data {
                    Task { @MainActor in self?.apply(data) }
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
    ) {}

    nonisolated func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        if let data = applicationContext[WatchSync.payload] as? Data {
            Task { @MainActor in self.apply(data) }
        }
        Task { @MainActor in self.ingestLifetimeGain(applicationContext) }
    }

    nonisolated func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        Task { @MainActor in
            if let data = message[WatchSync.payload] as? Data {
                self.apply(data)
            }
            self.ingestLifetimeGain(message)
            let kind = message[WatchSync.kind] as? String
            if kind == WatchSync.start {
                await WatchWorkoutController.shared.start()
            }
            if kind == WatchSync.stop {
                await WatchWorkoutController.shared.stop()
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
        Task { @MainActor in
            switch kind {
            case WatchSync.heartRates:
                let from = message[WatchSync.from] as? TimeInterval ?? 0
                let to = message[WatchSync.to] as? TimeInterval ?? 0
                let payload = (try? JSONEncoder().encode(
                    WatchWorkoutController.shared.heartRates(from: from, to: to)
                )) ?? Data()
                replyHandler([WatchSync.heartRates: payload])
            case WatchSync.start:
                await WatchWorkoutController.shared.start()
                replyHandler([:])
            case WatchSync.stop:
                await WatchWorkoutController.shared.stop()
                replyHandler([:])
            case WatchSync.skipRest:
                self.skipRest(notifyPhone: false)
                replyHandler([:])
            default:
                if let data = message[WatchSync.payload] as? Data {
                    self.apply(data)
                }
                self.ingestLifetimeGain(message)
                replyHandler([:])
            }
        }
    }
}

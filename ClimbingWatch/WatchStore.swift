import Foundation
import Observation
import WatchConnectivity

/// Watch-side session mirror. Phone owns SwiftData; this keeps the Watch UI live.
@Observable
@MainActor
final class WatchStore: NSObject, WCSessionDelegate {
    static let shared = WatchStore()

    var snapshot = WatchSnapshot.empty
    var selectedGrade: String?
    var selectedStyle: ClimbStyle = .crimp

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
        Task { await WatchWorkoutController.shared.stop() }
    }

    func log(outcome: ClimbOutcome) {
        guard let grade = selectedGrade ?? snapshot.selectedGrade else { return }
        var message: [String: Any] = [
            WatchSync.kind: WatchSync.log,
            WatchSync.outcome: outcome.rawValue,
            WatchSync.grade: grade,
            WatchSync.style: selectedStyle.rawValue,
        ]
        if let data = try? JSONEncoder().encode(WatchWorkoutController.shared.recentHeartRates()) {
            message[WatchSync.heartRates] = data
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
    }

    func undo() {
        send([WatchSync.kind: WatchSync.undo])
        if !snapshot.logs.isEmpty {
            snapshot.logs.removeFirst()
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
        if let style = ClimbStyle(rawValue: snap.selectedStyle) { selectedStyle = style }
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
    }

    nonisolated func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        Task { @MainActor in
            if let data = message[WatchSync.payload] as? Data {
                self.apply(data)
            }
            if message[WatchSync.kind] as? String == WatchSync.start {
                await WatchWorkoutController.shared.start()
            }
            if message[WatchSync.kind] as? String == WatchSync.stop {
                await WatchWorkoutController.shared.stop()
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
            default:
                if let data = message[WatchSync.payload] as? Data {
                    self.apply(data)
                }
                replyHandler([:])
            }
        }
    }
}

import Foundation
import WatchConnectivity

/// Asks the paired Watch for wrist-motion frames covering a send/flash window.
/// Returns an empty array when the Watch isn't reachable so HR-only traces
/// still work.
@MainActor
final class WatchMotionClient: NSObject, WCSessionDelegate {
    static let shared = WatchMotionClient()

    private var session: WCSession? {
        WCSession.isSupported() ? .default : nil
    }

    private override init() {
        super.init()
        session?.delegate = self
        session?.activate()
    }

    func startRecording() {
        send(kind: WatchSync.start)
    }

    func stopRecording() {
        send(kind: WatchSync.stop)
    }

    func frames(from start: Date, to end: Date) async -> [MotionFrame] {
        guard let session, session.activationState == .activated, session.isReachable else {
            return []
        }
        return await withCheckedContinuation { continuation in
            session.sendMessage(
                [
                    WatchSync.kind: WatchSync.frames,
                    WatchSync.from: start.timeIntervalSince1970,
                    WatchSync.to: end.timeIntervalSince1970,
                ],
                replyHandler: { reply in
                    let frames: [MotionFrame]
                    if let data = reply[WatchSync.frames] as? Data {
                        frames = (try? JSONDecoder().decode([MotionFrame].self, from: data)) ?? []
                    } else {
                        frames = []
                    }
                    continuation.resume(returning: frames)
                },
                errorHandler: { _ in
                    continuation.resume(returning: [])
                }
            )
        }
    }

    private func send(kind: String) {
        guard let session, session.activationState == .activated, session.isReachable else { return }
        session.sendMessage([WatchSync.kind: kind], replyHandler: { _ in }, errorHandler: { _ in })
    }

    nonisolated func session(
        _ session: WCSession,
        activationDidCompleteWith activationState: WCSessionActivationState,
        error: Error?
    ) {}

    nonisolated func sessionDidBecomeInactive(_ session: WCSession) {}

    nonisolated func sessionDidDeactivate(_ session: WCSession) {
        session.activate()
    }
}

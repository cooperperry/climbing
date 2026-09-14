import CoreMotion
import Foundation
import HealthKit
import WatchConnectivity

/// Records a rolling buffer of wrist motion while a climbing workout is active
/// and answers iPhone requests for the last attempt window.
final class WorkoutMotionManager: NSObject, WCSessionDelegate, HKWorkoutSessionDelegate, HKLiveWorkoutBuilderDelegate {
    static let shared = WorkoutMotionManager()

    private let store = HKHealthStore()
    private let motion = CMMotionManager()
    private let motionQueue: OperationQueue = {
        let queue = OperationQueue()
        queue.name = "ClimbingWatch.motion"
        queue.maxConcurrentOperationCount = 1
        return queue
    }()

    private var workout: HKWorkoutSession?
    private var builder: HKLiveWorkoutBuilder?
    private var buffer: [MotionFrame] = []
    private let lock = NSLock()
    private let keep: TimeInterval = 180

    private override init() {
        super.init()
        if WCSession.isSupported() {
            WCSession.default.delegate = self
            WCSession.default.activate()
        }
    }

    func start(configuration: HKWorkoutConfiguration = .indoorClimbing) async {
        await authorize()
        motion.stopDeviceMotionUpdates()
        await finishWorkout()

        do {
            let session = try HKWorkoutSession(healthStore: store, configuration: configuration)
            let live = session.associatedWorkoutBuilder()
            live.dataSource = HKLiveWorkoutDataSource(healthStore: store, workoutConfiguration: configuration)
            session.delegate = self
            live.delegate = self
            workout = session
            builder = live
            let now = Date()
            session.startActivity(with: now)
            try await live.beginCollection(at: now)
        } catch {
            // Motion still records if the HealthKit session can't start.
        }

        startMotion()
    }

    func stop() async {
        motion.stopDeviceMotionUpdates()
        await finishWorkout()
    }

    func frames(from start: TimeInterval, to end: TimeInterval) -> [MotionFrame] {
        lock.lock()
        defer { lock.unlock() }
        return buffer.filter { $0.timestamp >= start && $0.timestamp <= end }
    }

    private func authorize() async {
        var toShare: Set<HKSampleType> = [HKObjectType.workoutType()]
        var toRead = Set<HKObjectType>()
        if let heart = HKObjectType.quantityType(forIdentifier: .heartRate) {
            toRead.insert(heart)
        }
        try? await store.requestAuthorization(toShare: toShare, read: toRead)
    }

    private func startMotion() {
        guard motion.isDeviceMotionAvailable else { return }
        motion.deviceMotionUpdateInterval = 0.1
        motion.startDeviceMotionUpdates(using: .xArbitraryZVertical, to: motionQueue) { [weak self] data, _ in
            guard let self, let data else { return }
            let acc = data.userAcceleration
            let gravity = data.gravity
            let frame = MotionFrame(
                timestamp: Date().timeIntervalSince1970,
                userX: acc.x, userY: acc.y, userZ: acc.z,
                gravityX: gravity.x, gravityY: gravity.y, gravityZ: gravity.z
            )
            self.append(frame)
        }
    }

    private func append(_ frame: MotionFrame) {
        lock.lock()
        buffer.append(frame)
        let cutoff = frame.timestamp - keep
        buffer.removeAll { $0.timestamp < cutoff }
        lock.unlock()
    }

    private func finishWorkout() async {
        let end = Date()
        workout?.end(end)
        try? await builder?.endCollection(at: end)
        _ = try? await builder?.finishWorkout()
        workout = nil
        builder = nil
    }

    // MARK: - WCSession

    nonisolated func session(
        _ session: WCSession,
        activationDidCompleteWith activationState: WCSessionActivationState,
        error: Error?
    ) {}

    nonisolated func session(
        _ session: WCSession,
        didReceiveMessage message: [String: Any],
        replyHandler: @escaping ([String: Any]) -> Void
    ) {
        let kind = message[WatchSync.kind] as? String
        Task {
            switch kind {
            case WatchSync.start:
                await self.start()
                replyHandler([:])
            case WatchSync.stop:
                await self.stop()
                replyHandler([:])
            case WatchSync.frames:
                let from = message[WatchSync.from] as? TimeInterval ?? 0
                let to = message[WatchSync.to] as? TimeInterval ?? 0
                let payload = (try? JSONEncoder().encode(self.frames(from: from, to: to))) ?? Data()
                replyHandler([WatchSync.frames: payload])
            default:
                replyHandler([:])
            }
        }
    }

    // MARK: - HKWorkoutSession

    nonisolated func workoutSession(
        _ workoutSession: HKWorkoutSession,
        didChangeTo toState: HKWorkoutSessionState,
        from fromState: HKWorkoutSessionState,
        date: Date
    ) {}

    nonisolated func workoutSession(_ workoutSession: HKWorkoutSession, didFailWithError error: Error) {}

    nonisolated func workoutBuilderDidCollectEvent(_ workoutBuilder: HKLiveWorkoutBuilder) {}

    nonisolated func workoutBuilder(
        _ workoutBuilder: HKLiveWorkoutBuilder,
        didCollectDataOf collectedTypes: Set<HKSampleType>
    ) {}
}

extension HKWorkoutConfiguration {
    static var indoorClimbing: HKWorkoutConfiguration {
        let config = HKWorkoutConfiguration()
        config.activityType = .climbing
        config.locationType = .indoor
        return config
    }
}

import Foundation
import HealthKit
import Observation

/// Running climbing workout on Watch: live BPM plus a rolling heart-rate buffer.
@Observable
@MainActor
final class WatchWorkoutController: NSObject, HKWorkoutSessionDelegate, HKLiveWorkoutBuilderDelegate {
    static let shared = WatchWorkoutController()

    var currentBPM: Int?
    private(set) var samples: [HeartRateSample] = []

    private let store = HKHealthStore()
    private var workout: HKWorkoutSession?
    private var builder: HKLiveWorkoutBuilder?
    private let keep: TimeInterval = 180

    private override init() {
        super.init()
    }

    func start(configuration: HKWorkoutConfiguration = .indoorClimbing) async {
        await authorize()
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
            currentBPM = nil
        }
    }

    func stop() async {
        await finishWorkout()
        currentBPM = nil
    }

    func heartRates(from start: TimeInterval, to end: TimeInterval) -> [HeartRateSample] {
        samples.filter { $0.timestamp >= start && $0.timestamp <= end }
    }

    func recentHeartRates(seconds: TimeInterval = EffortWindow.maximum) -> [HeartRateSample] {
        let cutoff = Date().timeIntervalSince1970 - seconds
        return samples.filter { $0.timestamp >= cutoff }
    }

    private func authorize() async {
        let toShare: Set<HKSampleType> = [HKObjectType.workoutType()]
        var toRead = Set<HKObjectType>()
        if let heart = HKObjectType.quantityType(forIdentifier: .heartRate) {
            toRead.insert(heart)
        }
        try? await store.requestAuthorization(toShare: toShare, read: toRead)
    }

    private func finishWorkout() async {
        workout?.end()
        try? await builder?.endCollection(at: Date())
        _ = try? await builder?.finishWorkout()
        workout = nil
        builder = nil
    }

    private func ingestHeartRate(from builder: HKLiveWorkoutBuilder) {
        guard let type = HKQuantityType.quantityType(forIdentifier: .heartRate),
              let stats = builder.statistics(for: type),
              let quantity = stats.mostRecentQuantity() else { return }
        let unit = HKUnit.count().unitDivided(by: .minute())
        let bpm = quantity.doubleValue(for: unit)
        let now = Date().timeIntervalSince1970
        currentBPM = Int(bpm.rounded())
        samples.append(HeartRateSample(timestamp: now, bpm: bpm))
        let cutoff = now - keep
        samples.removeAll { $0.timestamp < cutoff }
    }

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
    ) {
        Task { @MainActor in
            guard let heart = HKQuantityType.quantityType(forIdentifier: .heartRate),
                  collectedTypes.contains(heart) else { return }
            self.ingestHeartRate(from: workoutBuilder)
            WatchStore.shared.broadcastBPM()
        }
    }
}

extension HKWorkoutConfiguration {
    static var indoorClimbing: HKWorkoutConfiguration {
        let config = HKWorkoutConfiguration()
        config.activityType = .climbing
        config.locationType = .indoor
        return config
    }
}

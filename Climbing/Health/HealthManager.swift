import Foundation
import HealthKit
import Observation

/// Reads Apple Watch metrics (active energy + heart rate) from HealthKit for a
/// session window. Pure aggregation/formatting lives in `HealthMath` /
/// `HealthSummary` (Domain) so it can be unit tested; this type only bridges
/// HealthKit into those values.
@Observable
@MainActor
final class HealthManager {
    enum Status: Equatable {
        case unknown
        case unavailable
        case denied
        case authorized
    }

    private let store = HKHealthStore()

    private(set) var status: Status = .unknown
    private(set) var summary: HealthSummary = .empty

    private var readTypes: Set<HKObjectType> {
        var types = Set<HKObjectType>()
        if let energy = HKObjectType.quantityType(forIdentifier: .activeEnergyBurned) {
            types.insert(energy)
        }
        if let heart = HKObjectType.quantityType(forIdentifier: .heartRate) {
            types.insert(heart)
        }
        return types
    }

    /// Prompts for read access to active energy and heart rate.
    func requestAuthorization() async {
        guard HKHealthStore.isHealthDataAvailable() else {
            status = .unavailable
            return
        }
        do {
            try await store.requestAuthorization(toShare: [], read: readTypes)
            status = .authorized
        } catch {
            status = .denied
        }
    }

    /// Refreshes the summary for the given window. Safe to call repeatedly.
    func refresh(from start: Date, to end: Date) async {
        guard HKHealthStore.isHealthDataAvailable(), status == .authorized else { return }
        async let calories = activeEnergy(start: start, end: end)
        async let heartRates = heartRateSamples(start: start, end: end)
        let burned = await calories
        let samples = await heartRates
        summary = HealthMath.summary(
            activeCalories: burned,
            heartRates: samples.map(\.bpm)
        )
    }

    /// Timestamped heart-rate samples for overlaying a send trace.
    func heartRateTimeline(from start: Date, to end: Date) async -> [HeartRateSample] {
        await heartRateSamples(start: start, end: end)
    }

    /// Launches the Watch app into a climbing workout so it can record wrist
    /// motion. No-ops when a Watch isn't paired or the companion isn't installed.
    func startWatchWorkout() async {
        guard HKHealthStore.isHealthDataAvailable() else { return }
        let config = HKWorkoutConfiguration()
        config.activityType = .climbing
        config.locationType = .indoor
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            store.startWatchApp(with: config) { _, _ in
                continuation.resume()
            }
        }
    }

    private func activeEnergy(start: Date, end: Date) async -> Double {
        guard let type = HKQuantityType.quantityType(forIdentifier: .activeEnergyBurned) else {
            return 0
        }
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end)
        return await withCheckedContinuation { continuation in
            let query = HKStatisticsQuery(
                quantityType: type,
                quantitySamplePredicate: predicate,
                options: .cumulativeSum
            ) { _, statistics, _ in
                let kcal = statistics?.sumQuantity()?.doubleValue(for: .kilocalorie()) ?? 0
                continuation.resume(returning: kcal)
            }
            store.execute(query)
        }
    }

    private func heartRateSamples(start: Date, end: Date) async -> [HeartRateSample] {
        guard let type = HKQuantityType.quantityType(forIdentifier: .heartRate) else {
            return []
        }
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end)
        let unit = HKUnit.count().unitDivided(by: .minute())
        return await withCheckedContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: type,
                predicate: predicate,
                limit: HKObjectQueryNoLimit,
                sortDescriptors: [NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)]
            ) { _, samples, _ in
                let values = (samples as? [HKQuantitySample])?.map {
                    HeartRateSample(
                        timestamp: $0.startDate.timeIntervalSince1970,
                        bpm: $0.quantity.doubleValue(for: unit)
                    )
                } ?? []
                continuation.resume(returning: values)
            }
            store.execute(query)
        }
    }
}

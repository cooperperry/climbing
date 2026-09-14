import Foundation

/// A snapshot of Apple Health metrics for a session window (sourced from Apple
/// Watch via HealthKit). Foundation-only so the aggregation and formatting are
/// unit-testable without HealthKit.
public struct HealthSummary: Equatable, Sendable {
    /// Active energy burned, in kilocalories.
    public var activeCalories: Double
    /// Average heart rate over the window, in beats per minute.
    public var averageHeartRate: Int?
    /// Peak heart rate over the window, in beats per minute.
    public var maxHeartRate: Int?

    public init(
        activeCalories: Double = 0,
        averageHeartRate: Int? = nil,
        maxHeartRate: Int? = nil
    ) {
        self.activeCalories = activeCalories
        self.averageHeartRate = averageHeartRate
        self.maxHeartRate = maxHeartRate
    }

    public static let empty = HealthSummary()

    /// Whether there is anything worth showing.
    public var hasData: Bool {
        activeCalories > 0 || averageHeartRate != nil
    }

    /// Whole-number calories for display.
    public var caloriesText: String {
        "\(Int(activeCalories.rounded()))"
    }
}

/// Pure helpers for turning raw HealthKit sample values into a `HealthSummary`.
public enum HealthMath {
    /// Rounded average of heart-rate samples (bpm), or nil when there are none.
    public static func averageBPM(_ samples: [Double]) -> Int? {
        guard !samples.isEmpty else { return nil }
        return Int((samples.reduce(0, +) / Double(samples.count)).rounded())
    }

    /// Rounded peak of heart-rate samples (bpm), or nil when there are none.
    public static func maxBPM(_ samples: [Double]) -> Int? {
        guard let peak = samples.max() else { return nil }
        return Int(peak.rounded())
    }

    /// Builds a summary from a calorie total and raw heart-rate samples.
    public static func summary(activeCalories: Double, heartRates: [Double]) -> HealthSummary {
        HealthSummary(
            activeCalories: max(0, activeCalories),
            averageHeartRate: averageBPM(heartRates),
            maxHeartRate: maxBPM(heartRates)
        )
    }
}

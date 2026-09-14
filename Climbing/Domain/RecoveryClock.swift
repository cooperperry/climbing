import Foundation

/// A rest interval after a logged go. `duration` is the timeout; heart rate at
/// or below `targetBPM` can end rest early once a short floor has elapsed.
public struct RestPlan: Equatable, Sendable, Codable, Identifiable {
    public var id: UUID
    public var startedAt: TimeInterval
    public var duration: TimeInterval
    public var peakBPM: Int?
    public var targetBPM: Int?

    public init(
        id: UUID = UUID(),
        startedAt: TimeInterval,
        duration: TimeInterval,
        peakBPM: Int? = nil,
        targetBPM: Int? = nil
    ) {
        self.id = id
        self.startedAt = startedAt
        self.duration = duration
        self.peakBPM = peakBPM
        self.targetBPM = targetBPM
    }

    public var startDate: Date { Date(timeIntervalSince1970: startedAt) }
}

/// What the rest clock should show right now.
public enum RestPhase: Equatable, Sendable {
    /// Still recovering; `remaining` is seconds left on the timeout.
    case resting(remaining: TimeInterval)
    /// Heart rate dropped to the target before the timeout.
    case recovered
    /// Timeout elapsed (HR may still be elevated).
    case ready

    public var isFinished: Bool {
        switch self {
        case .resting: return false
        case .recovered, .ready: return true
        }
    }
}

/// Pure rest-timer rules. Gym rest scales with how high HR went on the go,
/// then ends early when BPM falls back toward recovered.
public enum RecoveryMath {
    /// Used when there is no heart-rate reading for the go.
    public static let fallbackDuration: TimeInterval = 150
    public static let minimumDuration: TimeInterval = 60
    public static let maximumDuration: TimeInterval = 240
    /// Ignore a noisy HR dip in the first seconds off the wall.
    public static let minElapsedBeforeHRReady: TimeInterval = 25
    /// Recovered ≈ 78% of the go's peak BPM.
    public static let recoveryFraction = 0.78
    /// Look this far back for peak HR on the attempt.
    public static let effortWindow: TimeInterval = 45

    /// Build a rest plan from samples around `date` (typically the log time).
    public static func plan(
        at date: Date,
        heartRates: [HeartRateSample],
        currentBPM: Int? = nil
    ) -> RestPlan {
        let peak = peakBPM(heartRates: heartRates, around: date) ?? currentBPM
        return RestPlan(
            startedAt: date.timeIntervalSince1970,
            duration: duration(peakBPM: peak),
            peakBPM: peak,
            targetBPM: peak.map(targetBPM)
        )
    }

    /// Highest BPM in `[date - window, date + 2s]`.
    public static func peakBPM(
        heartRates: [HeartRateSample],
        around date: Date,
        window: TimeInterval = effortWindow
    ) -> Int? {
        let end = date.timeIntervalSince1970 + 2
        let start = date.timeIntervalSince1970 - window
        let inWindow = heartRates.filter { $0.timestamp >= start && $0.timestamp <= end }
        guard let maxBPM = inWindow.map(\.bpm).max() else { return nil }
        return Int(maxBPM.rounded())
    }

    public static func targetBPM(peak: Int) -> Int {
        max(90, Int((Double(peak) * recoveryFraction).rounded()))
    }

    /// Linear map: ~100 bpm → 90s rest, ~180 bpm → 210s, clamped.
    public static func duration(peakBPM: Int?) -> TimeInterval {
        guard let peak = peakBPM else { return fallbackDuration }
        let t = Double(peak - 100) / 80.0
        let seconds = 90 + t * 120
        return min(maximumDuration, max(minimumDuration, seconds))
    }

    public static func remaining(plan: RestPlan, now: Date) -> TimeInterval {
        max(0, plan.duration - now.timeIntervalSince(plan.startDate))
    }

    public static func phase(plan: RestPlan, now: Date, currentBPM: Int?) -> RestPhase {
        let elapsed = now.timeIntervalSince(plan.startDate)
        if elapsed >= plan.duration {
            return .ready
        }
        if elapsed >= minElapsedBeforeHRReady,
           let bpm = currentBPM,
           let target = plan.targetBPM,
           bpm <= target {
            return .recovered
        }
        return .resting(remaining: remaining(plan: plan, now: now))
    }
}

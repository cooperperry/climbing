import Foundation

/// Pure time helpers for session timing and display.
///
/// Kept free of SwiftUI/UIKit so the active-session timer math can be unit
/// tested deterministically by passing explicit dates rather than reading the
/// wall clock.
public enum SessionClock {
    /// Non-negative elapsed seconds between two dates.
    ///
    /// Clamped at zero so clock skew or an `endTime` slightly before `start`
    /// never yields a negative duration.
    public static func elapsed(from start: Date, to end: Date) -> TimeInterval {
        max(0, end.timeIntervalSince(start))
    }

    /// Formats a duration as `H:MM:SS`, collapsing to `M:SS` when under an hour.
    public static func format(_ interval: TimeInterval) -> String {
        let total = Int(max(0, interval).rounded(.down))
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let seconds = total % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        }
        return String(format: "%d:%02d", minutes, seconds)
    }
}

import Foundation

/// On-wrist cues during a workout: warmup, then rest between goes.
public enum WorkoutCue: Equatable, Sendable {
    case none
    case warmingUp
    case warmedUp
    case resting(remaining: TimeInterval)
    case readyToSend

    public var title: String {
        switch self {
        case .none: return ""
        case .warmingUp: return "Warming up"
        case .warmedUp: return "Warmed up — go climb"
        case .resting(let remaining): return "Rest \(SessionClock.format(remaining))"
        case .readyToSend: return "Ready — go send"
        }
    }

    public var isActionable: Bool {
        switch self {
        case .resting, .readyToSend: return true
        default: return false
        }
    }
}

/// A proper gym warmup is easy movement over several minutes, not one hard go.
public enum WarmupMath {
    public static let minimumElapsed: TimeInterval = 8 * 60
    public static let minimumClimbing: TimeInterval = 3 * 60
    /// Roughly two indoor boulder problems.
    public static let minimumGainMeters: Double = 8

    public static func isComplete(
        elapsed: TimeInterval,
        climbingTime: TimeInterval,
        gainMeters: Double
    ) -> Bool {
        guard elapsed >= minimumElapsed else { return false }
        return climbingTime >= minimumClimbing || gainMeters >= minimumGainMeters
    }
}

public enum WorkoutCueMath {
    /// Rest and “go send” beat warmup copy; a finished rest stays until the next go.
    public static func cue(
        warmupComplete: Bool,
        showWarmedUpUntil: Date?,
        restPlan: RestPlan?,
        currentBPM: Int?,
        now: Date
    ) -> WorkoutCue {
        if let plan = restPlan {
            switch RecoveryMath.phase(plan: plan, now: now, currentBPM: currentBPM) {
            case .resting(let remaining):
                return .resting(remaining: remaining)
            case .recovered, .ready:
                return .readyToSend
            }
        }
        if !warmupComplete { return .warmingUp }
        if let until = showWarmedUpUntil, now < until { return .warmedUp }
        return .none
    }
}

public enum LifetimeGainMath {
    public static func total(persisted: Double, session: Double) -> Double {
        max(0, persisted) + max(0, session)
    }
}

import Foundation

/// The result of a logged attempt on a climb.
///
/// This type intentionally depends only on `Foundation` so the domain logic can
/// be unit tested on any platform (including Linux CI), independent of SwiftUI
/// or SwiftData.
public enum ClimbOutcome: String, CaseIterable, Codable, Identifiable, Sendable {
    /// Completed on the first try with no prior beta.
    case flash
    /// Completed after one or more attempts.
    case send
    /// Actively working the climb; not yet completed.
    case project
    /// A single go that did not complete the climb.
    case attempt

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .flash: return "Flash"
        case .send: return "Send"
        case .project: return "Project"
        case .attempt: return "Attempt"
        }
    }

    /// SF Symbol name used by the quick-tap logging buttons.
    public var symbolName: String {
        switch self {
        case .flash: return "bolt.fill"
        case .send: return "checkmark.circle.fill"
        case .project: return "hammer.fill"
        case .attempt: return "arrow.uturn.up"
        }
    }

    /// Whether this outcome represents topping out the climb.
    public var isCompletion: Bool {
        switch self {
        case .flash, .send: return true
        case .project, .attempt: return false
        }
    }

    /// Sort priority used in summaries; lower is a stronger result.
    public var rank: Int {
        switch self {
        case .flash: return 0
        case .send: return 1
        case .project: return 2
        case .attempt: return 3
        }
    }

    /// A plain-language definition, surfaced in the in-app info sheet and tooltips
    /// so users never have to guess what a term means.
    public var explanation: String {
        switch self {
        case .flash: return "Topped the climb on your very first try."
        case .send: return "Topped the climb after two or more tries."
        case .project: return "A climb you're still working — tries logged, not sent yet."
        case .attempt: return "A try that didn't top out."
        }
    }

    /// Derives the outcome for a successful top-out from the number of tries:
    /// a first-go top is a flash, anything more is a send. This lets the UI offer
    /// a single "Send" action instead of making the climber choose flash vs send.
    public static func topOut(attempts: Int) -> ClimbOutcome {
        attempts <= 1 ? .flash : .send
    }
}

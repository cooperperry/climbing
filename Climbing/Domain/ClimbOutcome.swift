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
}

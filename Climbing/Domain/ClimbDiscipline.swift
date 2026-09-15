import Foundation

/// How the climb was done. Independent of grade so a V4 boulder and a 5.10
/// top-rope don't get mixed together.
public enum ClimbDiscipline: String, CaseIterable, Codable, Identifiable, Sendable {
    case boulder
    case topRope
    case lead

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .boulder: return "Bouldering"
        case .topRope: return "Top rope"
        case .lead: return "Lead"
        }
    }

    public var symbolName: String {
        switch self {
        case .boulder: return "circle.grid.3x3.fill"
        case .topRope: return "arrow.up.to.line"
        case .lead: return "figure.climbing"
        }
    }

    /// Rope climbs use YDS; boulders use V-scale.
    public var usesRopeGrades: Bool {
        self != .boulder
    }
}

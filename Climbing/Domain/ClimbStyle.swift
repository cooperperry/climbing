import Foundation

/// The movement / hold character of a climb — how it *felt*, independent of the
/// wall angle (see `ClimbAngle`). Tracking this over time surfaces strengths and
/// weaknesses (e.g. a low send-rate on slopers).
///
/// Foundation-only so it is shared by SwiftData models, SwiftUI views, and
/// platform-independent unit tests.
public enum ClimbStyle: String, CaseIterable, Codable, Identifiable, Sendable {
    case crimp
    case sloper
    case pinch
    case pocket
    case compression
    case dyno
    case mantle
    case technical
    case powerful

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .crimp: return "Crimpy"
        case .sloper: return "Slopey"
        case .pinch: return "Pinchy"
        case .pocket: return "Pockets"
        case .compression: return "Compression"
        case .dyno: return "Dyno"
        case .mantle: return "Mantle"
        case .technical: return "Technical"
        case .powerful: return "Powerful"
        }
    }

    /// SF Symbol name used by the quick-tap style chips.
    public var symbolName: String {
        switch self {
        case .crimp: return "hand.point.up.left.fill"
        case .sloper: return "circle.fill"
        case .pinch: return "hand.pinch.fill"
        case .pocket: return "circle.dashed"
        case .compression: return "arrow.left.and.right.circle.fill"
        case .dyno: return "figure.jumprope"
        case .mantle: return "hand.raised.fill"
        case .technical: return "gearshape.fill"
        case .powerful: return "bolt.fill"
        }
    }

    /// A curated subset surfaced as quick-tap chips during a session.
    public static let quickTap: [ClimbStyle] = [
        .crimp, .sloper, .pinch, .pocket, .compression, .dyno, .mantle, .powerful,
    ]
}

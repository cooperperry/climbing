import Foundation

/// The dominant hold or movement style of a climb.
///
/// Foundation-only so it can be shared by SwiftData models, SwiftUI views, and
/// platform-independent unit tests.
public enum ClimbStyle: String, CaseIterable, Codable, Identifiable, Sendable {
    case crimp
    case sloper
    case pinch
    case jug
    case pocket
    case slab
    case vertical
    case overhang
    case roof
    case dyno
    case mantle

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .crimp: return "Crimp"
        case .sloper: return "Sloper"
        case .pinch: return "Pinch"
        case .jug: return "Jug"
        case .pocket: return "Pocket"
        case .slab: return "Slab"
        case .vertical: return "Vertical"
        case .overhang: return "Overhang"
        case .roof: return "Roof"
        case .dyno: return "Dyno"
        case .mantle: return "Mantle"
        }
    }

    /// SF Symbol name used by the quick-tap style chips.
    public var symbolName: String {
        switch self {
        case .crimp: return "hand.point.up.left.fill"
        case .sloper: return "circle.fill"
        case .pinch: return "hand.pinch.fill"
        case .jug: return "hand.raised.fill"
        case .pocket: return "circle.dashed"
        case .slab: return "triangle"
        case .vertical: return "rectangle.portrait"
        case .overhang: return "triangle.fill"
        case .roof: return "rectangle.fill"
        case .dyno: return "figure.jumprope"
        case .mantle: return "hand.raised.app.fill"
        }
    }

    /// A curated subset surfaced as quick-tap chips during a session.
    public static let quickTap: [ClimbStyle] = [
        .crimp, .sloper, .pinch, .jug, .pocket, .slab, .overhang, .dyno,
    ]
}

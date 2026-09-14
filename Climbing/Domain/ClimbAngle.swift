import Foundation

/// The wall angle / terrain of a climb. Distinct from movement `ClimbStyle`:
/// angle describes the wall, style describes the holds and moves.
public enum ClimbAngle: String, CaseIterable, Codable, Identifiable, Sendable {
    case slab
    case vertical
    case overhang
    case roof

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .slab: return "Slab"
        case .vertical: return "Vertical"
        case .overhang: return "Overhang"
        case .roof: return "Roof"
        }
    }

    /// SF Symbol name used by the angle chips.
    public var symbolName: String {
        switch self {
        case .slab: return "triangle"
        case .vertical: return "rectangle.portrait"
        case .overhang: return "triangle.righthalf.filled"
        case .roof: return "rectangle.fill"
        }
    }
}

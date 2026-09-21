import Foundation

/// Hold tape / plastic color on a gym map pin. RGB lives here so Watch and
/// iPhone can render the same chips without importing SwiftUI into Domain.
public enum HoldColor: String, CaseIterable, Codable, Sendable, Identifiable {
    case red
    case orange
    case yellow
    case green
    case blue
    case purple
    case pink
    case black
    case white

    public var id: String { rawValue }

    public var displayName: String {
        rawValue.capitalized
    }

    public var red: Double { rgb.0 }
    public var green: Double { rgb.1 }
    public var blue: Double { rgb.2 }

    public var prefersDarkLabel: Bool {
        self == .yellow || self == .white || self == .orange
    }

    private var rgb: (Double, Double, Double) {
        switch self {
        case .red: return (0.86, 0.18, 0.16)
        case .orange: return (0.96, 0.52, 0.08)
        case .yellow: return (0.97, 0.84, 0.16)
        case .green: return (0.22, 0.72, 0.29)
        case .blue: return (0.18, 0.45, 0.90)
        case .purple: return (0.55, 0.27, 0.87)
        case .pink: return (0.92, 0.32, 0.62)
        case .black: return (0.12, 0.12, 0.12)
        case .white: return (0.94, 0.94, 0.94)
        }
    }
}

import Foundation

/// One labeled spot on a gym floor plan, in 0...1 coordinates so pins stay
/// put if the photo is a different size later.
public struct GymMapPin: Equatable, Sendable, Identifiable {
    public var id: String
    public var name: String
    public var x: Double
    public var y: Double

    public init(id: String = UUID().uuidString, name: String, x: Double, y: Double) {
        self.id = id
        self.name = name
        let clamped = GymJoinMath.clampPin(x: x, y: y)
        self.x = clamped.x
        self.y = clamped.y
    }
}

public enum GymJoinMath {
    public static func normalizedName(_ name: String) -> String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let collapsed = trimmed.replacingOccurrences(
            of: "\\s+",
            with: " ",
            options: .regularExpression
        )
        return collapsed.lowercased()
    }

    public static func namesMatch(_ a: String, _ b: String) -> Bool {
        let left = normalizedName(a)
        let right = normalizedName(b)
        guard left.isEmpty == false, right.isEmpty == false else { return false }
        return left == right
    }

    /// Six-character code a climber can type to find a gym already on this phone.
    public static func joinCode(from uuid: UUID = UUID()) -> String {
        let hex = uuid.uuidString.replacingOccurrences(of: "-", with: "")
        return String(hex.prefix(6)).uppercased()
    }

    public static func codesMatch(_ a: String, _ b: String) -> Bool {
        let left = a.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        let right = b.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard left.count == 6, right.count == 6 else { return false }
        return left == right
    }

    public static func clampPin(x: Double, y: Double) -> (x: Double, y: Double) {
        (min(1, max(0, x)), min(1, max(0, y)))
    }

    public static func isUsableName(_ name: String) -> Bool {
        normalizedName(name).count >= 2
    }
}

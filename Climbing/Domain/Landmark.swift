import Foundation

/// Real-world heights used as lifetime (and session) climbing goals.
///
/// Heights are stored in meters; feet are derived with the international foot
/// (0.3048 m) so Empire State is exactly 1,250 ft.
public struct Landmark: Equatable, Sendable, Identifiable, Codable {
    public var name: String
    public var heightMeters: Double

    public init(name: String, heightMeters: Double) {
        self.name = name
        self.heightMeters = heightMeters
    }

    public var id: String { name }

    public var heightFeet: Double { heightMeters / 0.3048 }

    public static let empireState = Landmark(name: "Empire State Building", heightMeters: 381)
    public static let elCapitan = Landmark(name: "El Capitan", heightMeters: 914.4)
    public static let halfDome = Landmark(name: "Half Dome", heightMeters: 1_463.04)
    public static let everest = Landmark(name: "Mount Everest", heightMeters: 29_031 * 0.3048)

    public static let all: [Landmark] = [
        .empireState, .elCapitan, .halfDome, .everest,
    ]

    /// 0...1 of this landmark's height, clamped.
    public func percentComplete(gainMeters: Double) -> Double {
        guard heightMeters > 0 else { return 0 }
        return min(1, max(0, gainMeters / heightMeters))
    }

    /// Lifetime multipliers, e.g. 3.2× El Capitan.
    public func completions(gainMeters: Double) -> Double {
        guard heightMeters > 0 else { return 0 }
        return max(0, gainMeters / heightMeters)
    }

    public func remainingMeters(gainMeters: Double) -> Double {
        max(0, heightMeters - max(0, gainMeters))
    }
}

/// Progress toward a landmark, including leftover after full completions.
public struct LandmarkProgress: Equatable, Sendable {
    public var landmark: Landmark
    /// Full + fractional completions of this landmark.
    public var completions: Double
    /// 0...1 through the *current* lap of this landmark.
    public var lapPercent: Double
    public var remainingMeters: Double

    public init(landmark: Landmark, completions: Double, lapPercent: Double, remainingMeters: Double) {
        self.landmark = landmark
        self.completions = completions
        self.lapPercent = lapPercent
        self.remainingMeters = remainingMeters
    }
}

public enum LandmarkMath {
    /// Smallest landmark not yet fully climbed for this lifetime total; Everest once past Half Dome.
    public static func sessionTarget(gainMeters: Double) -> Landmark {
        Landmark.all.first { gainMeters < $0.heightMeters } ?? .everest
    }

    public static func progress(gainMeters: Double, toward landmark: Landmark) -> LandmarkProgress {
        let completions = landmark.completions(gainMeters: gainMeters)
        let remainder = gainMeters.truncatingRemainder(dividingBy: landmark.heightMeters)
        let lap = landmark.heightMeters == 0 ? 0 : remainder / landmark.heightMeters
        // Exact multiples sit at 100% of a finished lap.
        let lapPercent = gainMeters > 0 && remainder == 0 ? 1 : lap
        let remaining = remainder == 0 && gainMeters > 0 ? 0 : landmark.heightMeters - remainder
        return LandmarkProgress(
            landmark: landmark,
            completions: completions,
            lapPercent: min(1, max(0, lapPercent)),
            remainingMeters: max(0, remaining)
        )
    }
}

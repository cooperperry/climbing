import Foundation

/// A climber level derived from lifetime points, in the vein of an athletic
/// progression tier (Beginner → Pro).
public struct ClimberLevel: Equatable, Sendable {
    /// 1-based level number.
    public let number: Int
    public let title: String
    /// Lifetime points at which this level begins.
    public let minPoints: Int
    /// Lifetime points needed to reach the next level, or `nil` at the top tier.
    public let nextLevelPoints: Int?

    public init(number: Int, title: String, minPoints: Int, nextLevelPoints: Int?) {
        self.number = number
        self.title = title
        self.minPoints = minPoints
        self.nextLevelPoints = nextLevelPoints
    }

    public var isMaxLevel: Bool { nextLevelPoints == nil }
}

/// Pure scoring rules for climbs, sessions, and lifetime progression.
///
/// Foundation-only and deterministic so it is fully unit tested independent of
/// SwiftData/SwiftUI. Points reward difficulty and quality of ascent; attempt
/// counts are intentionally *not* scored so grinding failed goes can't inflate a
/// score.
public enum ScoreEngine {
    /// Points contributed by each step up the grade scale.
    public static let pointsPerGradeStep = 10

    /// Difficulty points for a grade at a zero-based scale index (harder is more).
    public static func difficultyPoints(gradeIndex: Int) -> Int {
        (max(0, gradeIndex) + 1) * pointsPerGradeStep
    }

    /// Quality-of-ascent multiplier. Flashing beats sending; working a project or
    /// a lone attempt earns partial effort credit.
    public static func multiplier(for outcome: ClimbOutcome) -> Double {
        switch outcome {
        case .flash: return 1.5
        case .send: return 1.0
        case .project: return 0.3
        case .attempt: return 0.1
        }
    }

    /// Points earned for a single logged climb.
    public static func points(gradeIndex: Int, outcome: ClimbOutcome) -> Int {
        let base = Double(difficultyPoints(gradeIndex: gradeIndex))
        return Int((base * multiplier(for: outcome)).rounded())
    }

    /// Total points for a session given its per-climb point values.
    public static func sessionScore(_ perClimbPoints: [Int]) -> Int {
        perClimbPoints.reduce(0, +)
    }

    /// Progression tiers keyed by the lifetime points needed to enter each.
    static let tiers: [(minPoints: Int, title: String)] = [
        (0, "Beginner"),
        (250, "Novice"),
        (750, "Intermediate"),
        (1_500, "Advanced"),
        (3_000, "Expert"),
        (6_000, "Elite"),
        (12_000, "Pro"),
    ]

    /// The climber level for a given lifetime point total.
    public static func level(forTotalPoints total: Int) -> ClimberLevel {
        let points = max(0, total)
        var currentIndex = 0
        for (index, tier) in tiers.enumerated() where points >= tier.minPoints {
            currentIndex = index
        }
        let tier = tiers[currentIndex]
        let next = currentIndex + 1 < tiers.count ? tiers[currentIndex + 1].minPoints : nil
        return ClimberLevel(
            number: currentIndex + 1,
            title: tier.title,
            minPoints: tier.minPoints,
            nextLevelPoints: next
        )
    }

    /// Fraction (0...1) of the way from the current level to the next.
    /// Returns 1.0 at the max tier.
    public static func progressToNextLevel(forTotalPoints total: Int) -> Double {
        let level = level(forTotalPoints: total)
        guard let next = level.nextLevelPoints else { return 1.0 }
        let span = Double(next - level.minPoints)
        guard span > 0 else { return 1.0 }
        let into = Double(max(0, total) - level.minPoints)
        return min(1.0, max(0.0, into / span))
    }

    /// Points remaining until the next level, or 0 at the max tier.
    public static func pointsToNextLevel(forTotalPoints total: Int) -> Int {
        let level = level(forTotalPoints: total)
        guard let next = level.nextLevelPoints else { return 0 }
        return max(0, next - max(0, total))
    }
}

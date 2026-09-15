import Foundation

/// Five-zone heart-rate model, as fractions of max HR.
public enum HeartRateZone: Int, CaseIterable, Sendable, Codable {
    case z1 = 1
    case z2 = 2
    case z3 = 3
    case z4 = 4
    case z5 = 5

    /// Inclusive lower bound, exclusive upper bound except z5 which is 1.0.
    public var maxHRFraction: ClosedRange<Double> {
        switch self {
        case .z1: return 0.50 ... 0.60
        case .z2: return 0.60 ... 0.70
        case .z3: return 0.70 ... 0.80
        case .z4: return 0.80 ... 0.90
        case .z5: return 0.90 ... 1.20
        }
    }

    public var displayName: String { "Z\(rawValue)" }

    public static func zone(bpm: Int, maxHR: Int) -> HeartRateZone {
        guard maxHR > 0 else { return .z1 }
        let fraction = Double(bpm) / Double(maxHR)
        if fraction < 0.60 { return .z1 }
        if fraction < 0.70 { return .z2 }
        if fraction < 0.80 { return .z3 }
        if fraction < 0.90 { return .z4 }
        return .z5
    }
}

/// Climbing vs rest, used for MET-based calorie estimates and time split.
public enum ClimbPhase: String, Equatable, Sendable, Codable {
    case climbing
    case resting

    public var displayName: String {
        switch self {
        case .climbing: return "Climb"
        case .resting: return "Rest"
        }
    }

    /// Compendium MET: climbing ~8–11, belay/rest ~2–3.
    public var met: Double {
        switch self {
        case .climbing: return 9.5
        case .resting: return 2.5
        }
    }
}

public enum StrainMath {
    public static let defaultMaxHR = 190
    public static let defaultWeightKg = 75.0
    /// m/min — above this (or high motion) counts as climbing.
    public static let climbingSpeedThreshold = 1.5
    public static let climbingMotionThreshold = 0.08

    public static func phase(verticalSpeedMPerMin: Double, motionVariance: Double) -> ClimbPhase {
        if verticalSpeedMPerMin >= climbingSpeedThreshold || motionVariance >= climbingMotionThreshold {
            return .climbing
        }
        return .resting
    }

    /// Edwards TRIMP: minutes in zone × zone number, summed.
    public static func trimp(zoneSeconds: [HeartRateZone: TimeInterval]) -> Double {
        zoneSeconds.reduce(0) { sum, pair in
            sum + (max(0, pair.value) / 60) * Double(pair.key.rawValue)
        }
    }

    /// 0...10 body-stress index from TRIMP rate, motion variance, and optional HRV SDNN (ms).
    public static func bodyStressIndex(
        trimp: Double,
        elapsed: TimeInterval,
        motionVariance: Double,
        hrvSDNN: Double?
    ) -> Double {
        let minutes = max(elapsed / 60, 1.0 / 60)
        let intensity = min(10, (trimp / minutes) * 2)
        let motion = min(10, max(0, (motionVariance - 0.02) / 0.15 * 10))
        let hrv: Double
        if let sdnn = hrvSDNN {
            hrv = min(10, max(0, (40 - sdnn) / 4))
        } else {
            hrv = intensity
        }
        return clamp((intensity * 0.55) + (motion * 0.25) + (hrv * 0.20), 0, 10)
    }

    /// kcal ≈ MET × kg × hours.
    public static func calories(met: Double, weightKg: Double, seconds: TimeInterval) -> Double {
        max(0, met * max(0, weightKg) * (max(0, seconds) / 3_600))
    }

    public static func maxHR(ageYears: Int?) -> Int {
        guard let age = ageYears, age > 0, age < 100 else { return defaultMaxHR }
        return max(120, 220 - age)
    }

    public static func clamp(_ value: Double, _ lo: Double, _ hi: Double) -> Double {
        min(hi, max(lo, value))
    }
}

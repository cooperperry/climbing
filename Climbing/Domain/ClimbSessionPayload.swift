import Foundation

/// Watch → phone payload for a finished SummitPulse session. Foundation-only
/// so both targets encode the same contract.
public struct ClimbSessionPayload: Equatable, Sendable, Codable {
    public var id: UUID
    public var startDate: Date
    public var endDate: Date?
    public var totalElevationGain: Double
    public var maxAltitude: Double
    public var verticalSpeed: Double
    public var activeCalories: Double
    public var restingCalories: Double
    public var bodyStressIndex: Double
    public var cardiovascularStrain: Double
    public var climbingTime: TimeInterval
    public var restingTime: TimeInterval
    public var heartRateSeries: [HeartRateSample]

    public init(
        id: UUID = UUID(),
        startDate: Date,
        endDate: Date? = nil,
        totalElevationGain: Double = 0,
        maxAltitude: Double = 0,
        verticalSpeed: Double = 0,
        activeCalories: Double = 0,
        restingCalories: Double = 0,
        bodyStressIndex: Double = 0,
        cardiovascularStrain: Double = 0,
        climbingTime: TimeInterval = 0,
        restingTime: TimeInterval = 0,
        heartRateSeries: [HeartRateSample] = []
    ) {
        self.id = id
        self.startDate = startDate
        self.endDate = endDate
        self.totalElevationGain = totalElevationGain
        self.maxAltitude = maxAltitude
        self.verticalSpeed = verticalSpeed
        self.activeCalories = activeCalories
        self.restingCalories = restingCalories
        self.bodyStressIndex = bodyStressIndex
        self.cardiovascularStrain = cardiovascularStrain
        self.climbingTime = climbingTime
        self.restingTime = restingTime
        self.heartRateSeries = heartRateSeries
    }

    public var climbRestRatio: Double {
        let rest = max(restingTime, 1)
        return climbingTime / rest
    }

    public var sessionTitle: String {
        let hour = Calendar.current.component(.hour, from: startDate)
        let timeOfDay: String
        switch hour {
        case 5..<12: timeOfDay = "Morning"
        case 12..<17: timeOfDay = "Afternoon"
        case 17..<21: timeOfDay = "Evening"
        default: timeOfDay = "Night"
        }
        let target = LandmarkMath.sessionTarget(gainMeters: totalElevationGain)
        return "\(timeOfDay) Session — \(target.name) Progress"
    }
}

public enum SummitSync {
    public static let kind = "kind"
    public static let workoutSummary = "workoutSummary"
    public static let payload = "payload"
    public static let live = "live"
}

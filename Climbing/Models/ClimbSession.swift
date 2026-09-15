import Foundation
import SwiftData

/// One SummitPulse workout: elevation, calories, strain, and the HR series.
@Model
final class ClimbSession {
    var id: UUID
    var startDate: Date
    var endDate: Date?
    /// Cumulative filtered ascent, meters.
    var totalElevationGain: Double
    var maxAltitude: Double
    /// Rolling vertical speed at end of session, meters / minute.
    var verticalSpeed: Double
    var activeCalories: Double
    var restingCalories: Double
    /// 0...10
    var bodyStressIndex: Double
    /// Edwards TRIMP
    var cardiovascularStrain: Double
    var climbingTime: TimeInterval
    var restingTime: TimeInterval
    var heartRateSeriesData: Data?

    init(
        id: UUID = UUID(),
        startDate: Date = .now,
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

    var isActive: Bool { endDate == nil }

    var heartRateSeries: [HeartRateSample] {
        get {
            guard let heartRateSeriesData else { return [] }
            return (try? JSONDecoder().decode([HeartRateSample].self, from: heartRateSeriesData)) ?? []
        }
        set {
            heartRateSeriesData = try? JSONEncoder().encode(newValue)
        }
    }

    var payload: ClimbSessionPayload {
        ClimbSessionPayload(
            id: id,
            startDate: startDate,
            endDate: endDate,
            totalElevationGain: totalElevationGain,
            maxAltitude: maxAltitude,
            verticalSpeed: verticalSpeed,
            activeCalories: activeCalories,
            restingCalories: restingCalories,
            bodyStressIndex: bodyStressIndex,
            cardiovascularStrain: cardiovascularStrain,
            climbingTime: climbingTime,
            restingTime: restingTime,
            heartRateSeries: heartRateSeries
        )
    }

    convenience init(payload: ClimbSessionPayload) {
        self.init(
            id: payload.id,
            startDate: payload.startDate,
            endDate: payload.endDate,
            totalElevationGain: payload.totalElevationGain,
            maxAltitude: payload.maxAltitude,
            verticalSpeed: payload.verticalSpeed,
            activeCalories: payload.activeCalories,
            restingCalories: payload.restingCalories,
            bodyStressIndex: payload.bodyStressIndex,
            cardiovascularStrain: payload.cardiovascularStrain,
            climbingTime: payload.climbingTime,
            restingTime: payload.restingTime,
            heartRateSeries: payload.heartRateSeries
        )
    }
}

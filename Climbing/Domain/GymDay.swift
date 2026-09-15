import Foundation

/// One logged go, stripped to values Domain can group without SwiftData.
public struct DayClimb: Equatable, Sendable, Identifiable {
    public var loggedAt: Date
    public var gradeLabel: String
    public var outcome: ClimbOutcome
    public var discipline: ClimbDiscipline

    public init(
        loggedAt: Date,
        gradeLabel: String,
        outcome: ClimbOutcome,
        discipline: ClimbDiscipline
    ) {
        self.loggedAt = loggedAt
        self.gradeLabel = gradeLabel
        self.outcome = outcome
        self.discipline = discipline
    }

    public var id: String {
        "\(loggedAt.timeIntervalSince1970)-\(gradeLabel)-\(discipline.rawValue)-\(outcome.rawValue)"
    }

    public var isTop: Bool { outcome.isCompletion }
}

/// Watch (or phone Health) metrics for a workout, keyed by when it started.
public struct DayHealth: Equatable, Sendable {
    public var startDate: Date
    public var calories: Double
    public var gainMeters: Double
    public var peakBPM: Int?
    public var averageBPM: Int?
    public var bodyStress: Double
    public var duration: TimeInterval
    public var heartRates: [HeartRateSample]

    public init(
        startDate: Date,
        calories: Double = 0,
        gainMeters: Double = 0,
        peakBPM: Int? = nil,
        averageBPM: Int? = nil,
        bodyStress: Double = 0,
        duration: TimeInterval = 0,
        heartRates: [HeartRateSample] = []
    ) {
        self.startDate = startDate
        self.calories = calories
        self.gainMeters = gainMeters
        self.peakBPM = peakBPM
        self.averageBPM = averageBPM
        self.bodyStress = bodyStress
        self.duration = duration
        self.heartRates = heartRates
    }

    /// Combine two Watch workouts that happened on the same calendar day.
    public static func merged(_ items: [DayHealth]) -> DayHealth? {
        guard let first = items.first else { return nil }
        guard items.count > 1 else { return first }
        let rates = items.flatMap(\.heartRates)
        let avg: Int?
        if rates.isEmpty {
            avg = items.compactMap(\.averageBPM).nilIfEmpty.map { values in
                Int((Double(values.reduce(0, +)) / Double(values.count)).rounded())
            }
        } else {
            avg = Int((rates.map(\.bpm).reduce(0, +) / Double(rates.count)).rounded())
        }
        return DayHealth(
            startDate: items.map(\.startDate).min() ?? first.startDate,
            calories: items.reduce(0) { $0 + $1.calories },
            gainMeters: items.reduce(0) { $0 + $1.gainMeters },
            peakBPM: items.compactMap(\.peakBPM).max(),
            averageBPM: avg,
            bodyStress: items.map(\.bodyStress).max() ?? 0,
            duration: items.reduce(0) { $0 + $1.duration },
            heartRates: Array(rates.suffix(90))
        )
    }
}

/// One gym day: the routes you logged, plus Watch health if you wore it.
public struct GymDay: Equatable, Sendable, Identifiable {
    public var dayStart: Date
    public var climbs: [DayClimb]
    public var health: DayHealth?

    public init(dayStart: Date, climbs: [DayClimb] = [], health: DayHealth? = nil) {
        self.dayStart = dayStart
        self.climbs = climbs.sorted { $0.loggedAt > $1.loggedAt }
        self.health = health
    }

    public var id: Date { dayStart }

    public var tops: [DayClimb] { climbs.filter(\.isTop) }

    public func tops(in discipline: ClimbDiscipline) -> [DayClimb] {
        tops.filter { $0.discipline == discipline }
    }
}

public enum GymDayMath {
    public static func startOfDay(_ date: Date, calendar: Calendar = .current) -> Date {
        calendar.startOfDay(for: date)
    }

    /// Newest day first. A day appears if it has at least one climb or one workout.
    public static func group(
        climbs: [DayClimb],
        workouts: [DayHealth],
        calendar: Calendar = .current
    ) -> [GymDay] {
        var climbsByDay: [Date: [DayClimb]] = [:]
        for climb in climbs {
            climbsByDay[startOfDay(climb.loggedAt, calendar: calendar), default: []].append(climb)
        }
        var workoutsByDay: [Date: [DayHealth]] = [:]
        for workout in workouts {
            workoutsByDay[startOfDay(workout.startDate, calendar: calendar), default: []].append(workout)
        }
        let days = Set(climbsByDay.keys).union(workoutsByDay.keys)
        return days
            .sorted(by: >)
            .map { day in
                GymDay(
                    dayStart: day,
                    climbs: climbsByDay[day] ?? [],
                    health: DayHealth.merged(workoutsByDay[day] ?? [])
                )
            }
    }
}

private extension Array {
    var nilIfEmpty: Self? { isEmpty ? nil : self }
}

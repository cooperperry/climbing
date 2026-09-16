import Foundation

/// One logged go, stripped to values Domain can group without SwiftData.
public struct SessionClimb: Equatable, Sendable, Identifiable {
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

/// Health metrics for one Watch workout, start to end.
public struct SessionHealth: Equatable, Sendable, Identifiable {
    public var id: String
    public var startDate: Date
    public var endDate: Date?
    public var calories: Double
    public var gainMeters: Double
    public var peakBPM: Int?
    public var averageBPM: Int?
    public var bodyStress: Double
    public var duration: TimeInterval
    public var heartRates: [HeartRateSample]

    public init(
        id: String,
        startDate: Date,
        endDate: Date? = nil,
        calories: Double = 0,
        gainMeters: Double = 0,
        peakBPM: Int? = nil,
        averageBPM: Int? = nil,
        bodyStress: Double = 0,
        duration: TimeInterval = 0,
        heartRates: [HeartRateSample] = []
    ) {
        self.id = id
        self.startDate = startDate
        self.endDate = endDate
        self.calories = calories
        self.gainMeters = gainMeters
        self.peakBPM = peakBPM
        self.averageBPM = averageBPM
        self.bodyStress = bodyStress
        self.duration = duration > 0
            ? duration
            : SessionClock.elapsed(from: startDate, to: endDate ?? startDate)
        self.heartRates = heartRates
    }

    public func contains(_ date: Date) -> Bool {
        guard date >= startDate else { return false }
        if let endDate { return date <= endDate }
        return true
    }
}

/// One workout (or phone-only block) with the climbs logged during it.
public struct SessionSummary: Equatable, Sendable, Identifiable {
    public var id: String
    public var startDate: Date
    public var endDate: Date?
    public var duration: TimeInterval
    public var climbs: [SessionClimb]
    public var health: SessionHealth?

    public init(
        id: String,
        startDate: Date,
        endDate: Date? = nil,
        duration: TimeInterval = 0,
        climbs: [SessionClimb] = [],
        health: SessionHealth? = nil
    ) {
        self.id = id
        self.startDate = startDate
        self.endDate = endDate
        self.duration = duration > 0
            ? duration
            : SessionClock.elapsed(from: startDate, to: endDate ?? startDate)
        self.climbs = climbs.sorted { $0.loggedAt > $1.loggedAt }
        self.health = health
    }

    public var tops: [SessionClimb] { climbs.filter(\.isTop) }

    public func climbs(in discipline: ClimbDiscipline) -> [SessionClimb] {
        climbs.filter { $0.discipline == discipline }
    }
}

public enum SessionSummaryMath {
    /// Phone-only climbs farther apart than this become separate sessions.
    public static let phoneSessionGap: TimeInterval = 2 * 60 * 60

    /// Newest session first. Each Watch workout is its own row; leftover climbs
    /// cluster into phone-only sessions instead of merging by calendar day.
    public static func assemble(
        workouts: [SessionHealth],
        climbs: [SessionClimb]
    ) -> [SessionSummary] {
        var leftover = climbs
        var sessions: [SessionSummary] = []
        for workout in workouts.sorted(by: { $0.startDate > $1.startDate }) {
            let matched = leftover.filter { workout.contains($0.loggedAt) }
            leftover.removeAll { climb in matched.contains { $0.id == climb.id } }
            sessions.append(
                SessionSummary(
                    id: workout.id,
                    startDate: workout.startDate,
                    endDate: workout.endDate,
                    duration: workout.duration,
                    climbs: matched,
                    health: workout
                )
            )
        }
        sessions.append(contentsOf: clusterPhoneSessions(leftover.sorted { $0.loggedAt < $1.loggedAt }))
        return sessions.sorted { $0.startDate > $1.startDate }
    }

    private static func clusterPhoneSessions(_ climbs: [SessionClimb]) -> [SessionSummary] {
        guard climbs.isEmpty == false else { return [] }
        var clusters: [[SessionClimb]] = []
        var current: [SessionClimb] = []
        for climb in climbs {
            if let last = current.last,
               climb.loggedAt.timeIntervalSince(last.loggedAt) > phoneSessionGap {
                clusters.append(current)
                current = [climb]
            } else {
                current.append(climb)
            }
        }
        if current.isEmpty == false {
            clusters.append(current)
        }
        return clusters.map { group in
            let start = group.first!.loggedAt
            let end = group.last!.loggedAt
            return SessionSummary(
                id: "phone-\(start.timeIntervalSince1970)",
                startDate: start,
                endDate: end,
                duration: SessionClock.elapsed(from: start, to: end),
                climbs: group
            )
        }
    }
}

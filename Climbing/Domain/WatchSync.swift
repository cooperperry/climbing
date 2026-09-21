import Foundation

/// Keys and payloads for WatchConnectivity. Foundation-only so iPhone and Watch
/// compile the same contract without importing WatchConnectivity.
public enum WatchSync {
    public static let kind = "kind"
    public static let start = "start"
    public static let stop = "stop"
    public static let log = "log"
    public static let undo = "undo"
    public static let snapshot = "snapshot"
    public static let heartRates = "heartRates"
    public static let bpm = "bpm"
    public static let outcome = "outcome"
    public static let grade = "grade"
    public static let style = "style"
    public static let discipline = "discipline"
    public static let from = "from"
    public static let to = "to"
    public static let payload = "payload"
    public static let value = "value"
    public static let rest = "rest"
    public static let skipRest = "skipRest"
    public static let lifetimeGain = "lifetimeGain"
}

/// One climb row mirrored onto the Watch.
public struct WatchLogDTO: Equatable, Sendable, Codable, Identifiable {
    public var id: String
    public var grade: String
    public var outcome: String
    public var style: String
    public var loggedAt: TimeInterval

    public init(
        id: String,
        grade: String,
        outcome: String,
        style: String,
        loggedAt: TimeInterval
    ) {
        self.id = id
        self.grade = grade
        self.outcome = outcome
        self.style = style
        self.loggedAt = loggedAt
    }

    public var outcomeValue: ClimbOutcome {
        ClimbOutcome(rawValue: outcome) ?? .attempt
    }

    public var styleValue: ClimbStyle {
        ClimbStyle(rawValue: style) ?? .crimp
    }
}

/// Phone → Watch snapshot of the active session, grades, recap, and lifetime stats.
public struct WatchSnapshot: Equatable, Sendable, Codable {
    public var isActive: Bool
    public var startTime: TimeInterval?
    public var grades: [String]
    public var selectedGrade: String?
    public var selectedStyle: String
    public var climbs: Int
    public var sends: Int
    public var score: Int
    public var logs: [WatchLogDTO]
    public var lastTrace: EffortTrace?
    public var lastTraceTitle: String?
    public var lifetimeClimbs: Int
    public var lifetimeSends: Int
    public var lifetimeFlashes: Int
    public var lifetimePoints: Int
    public var hardestSend: String?
    public var levelNumber: Int
    public var levelTitle: String
    public var rest: RestPlan?
    public var styleHeadline: String?

    public init(
        isActive: Bool = false,
        startTime: TimeInterval? = nil,
        grades: [String] = [],
        selectedGrade: String? = nil,
        selectedStyle: String = ClimbStyle.crimp.rawValue,
        climbs: Int = 0,
        sends: Int = 0,
        score: Int = 0,
        logs: [WatchLogDTO] = [],
        lastTrace: EffortTrace? = nil,
        lastTraceTitle: String? = nil,
        lifetimeClimbs: Int = 0,
        lifetimeSends: Int = 0,
        lifetimeFlashes: Int = 0,
        lifetimePoints: Int = 0,
        hardestSend: String? = nil,
        levelNumber: Int = 1,
        levelTitle: String = "Beginner",
        rest: RestPlan? = nil,
        styleHeadline: String? = nil
    ) {
        self.isActive = isActive
        self.startTime = startTime
        self.grades = grades
        self.selectedGrade = selectedGrade
        self.selectedStyle = selectedStyle
        self.climbs = climbs
        self.sends = sends
        self.score = score
        self.logs = logs
        self.lastTrace = lastTrace
        self.lastTraceTitle = lastTraceTitle
        self.lifetimeClimbs = lifetimeClimbs
        self.lifetimeSends = lifetimeSends
        self.lifetimeFlashes = lifetimeFlashes
        self.lifetimePoints = lifetimePoints
        self.hardestSend = hardestSend
        self.levelNumber = levelNumber
        self.levelTitle = levelTitle
        self.rest = rest
        self.styleHeadline = styleHeadline
    }

    public static let empty = WatchSnapshot()

    public var selectedStyleValue: ClimbStyle {
        ClimbStyle(rawValue: selectedStyle) ?? .crimp
    }

    public var sessionStart: Date? {
        startTime.map { Date(timeIntervalSince1970: $0) }
    }
}

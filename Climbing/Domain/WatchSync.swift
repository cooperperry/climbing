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
    public static let gym = "gym"
    public static let wall = "wall"
    public static let wallPhotos = "wallPhotos"
    public static let color = "color"
    public static let routeLabel = "routeLabel"
    public static let refresh = "refresh"
}

/// One problem on the current set. Pins die when the wall is reset; send
/// history keeps wall + grade + date.
public struct WatchRoutePin: Equatable, Sendable, Codable, Identifiable {
    public var id: String
    public var grade: String
    public var color: String
    public var x: Double
    public var y: Double
    public var discipline: String

    public init(
        id: String = UUID().uuidString,
        grade: String,
        color: String,
        x: Double,
        y: Double,
        discipline: String = ClimbDiscipline.boulder.rawValue
    ) {
        self.id = id
        self.grade = grade
        self.color = color
        let clamped = GymJoinMath.clampPin(x: x, y: y)
        self.x = clamped.x
        self.y = clamped.y
        self.discipline = discipline
    }

    public var holdColor: HoldColor {
        HoldColor(rawValue: color) ?? .blue
    }

    public var disciplineValue: ClimbDiscipline {
        ClimbDiscipline(rawValue: discipline) ?? .boulder
    }

    public var label: String {
        "\(holdColor.displayName) \(grade)"
    }
}

/// A wall on the Watch map: durable name plus today's pins.
public struct WatchWall: Equatable, Sendable, Codable, Identifiable {
    public var name: String
    public var routes: [WatchRoutePin]

    public var id: String { name }

    public init(name: String, routes: [WatchRoutePin] = []) {
        self.name = name
        self.routes = routes
    }
}

/// Phone → Watch: the gym you're at, its walls, and the current set's pins.
/// Walls persist across route resets; pins do not.
public struct WatchGymContext: Equatable, Sendable, Codable {
    public var gymName: String?
    public var walls: [WatchWall]
    public var currentWall: String?

    public init(gymName: String? = nil, walls: [WatchWall] = [], currentWall: String? = nil) {
        self.gymName = gymName
        self.walls = walls
        self.currentWall = currentWall
    }

    public static let empty = WatchGymContext()

    public var wallNames: [String] { walls.map(\.name) }

    public func wall(named name: String?) -> WatchWall? {
        guard let name else { return nil }
        return walls.first { $0.name == name }
    }

    enum CodingKeys: String, CodingKey {
        case gymName, walls, currentWall
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        gymName = try container.decodeIfPresent(String.self, forKey: .gymName)
        currentWall = try container.decodeIfPresent(String.self, forKey: .currentWall)
        if let rich = try? container.decode([WatchWall].self, forKey: .walls) {
            walls = rich
        } else if let names = try? container.decode([String].self, forKey: .walls) {
            walls = names.map { WatchWall(name: $0) }
        } else {
            walls = []
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(gymName, forKey: .gymName)
        try container.encode(walls, forKey: .walls)
        try container.encodeIfPresent(currentWall, forKey: .currentWall)
    }

    /// Use a new phone-map selection when it changes. Otherwise keep the Watch
    /// pick if that wall still exists after a set reset.
    public static func pickWall(
        walls: [String],
        phoneCurrent: String?,
        previousPhoneCurrent: String?,
        watchWall: String?
    ) -> String? {
        if let phoneCurrent, walls.contains(phoneCurrent), phoneCurrent != previousPhoneCurrent {
            return phoneCurrent
        }
        if let watchWall, walls.contains(watchWall) {
            return watchWall
        }
        if let phoneCurrent, walls.contains(phoneCurrent) {
            return phoneCurrent
        }
        return walls.first
    }
}

/// Who last set a route, and when, for the gym floor plan.
public enum RouteCredit {
    public static func line(name: String?, at date: Date?, now: Date = Date()) -> String {
        let trimmed = name?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let who = trimmed.isEmpty ? "Someone" : trimmed
        guard let date else { return who }
        return "\(who) · \(relative(from: date, to: now))"
    }

    static func relative(from date: Date, to now: Date) -> String {
        let seconds = now.timeIntervalSince(date)
        if seconds < 60 { return "just now" }
        if seconds < 3_600 { return "\(Int(seconds / 60))m ago" }
        if seconds < 86_400 { return "\(Int(seconds / 3_600))h ago" }
        return "\(max(1, Int(seconds / 86_400)))d ago"
    }
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

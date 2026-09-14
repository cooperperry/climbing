import Foundation

/// Headline totals for a single session, used to build the end-of-session recap
/// and to detect personal records. Foundation-only and unit-testable.
public struct SessionTotals: Equatable, Sendable {
    public var climbs: Int
    public var sends: Int
    public var flashes: Int
    public var points: Int
    /// Difficulty index of the hardest send this session, or nil if none.
    public var hardestSendGradeIndex: Int?
    public var durationSeconds: TimeInterval

    public init(
        climbs: Int = 0,
        sends: Int = 0,
        flashes: Int = 0,
        points: Int = 0,
        hardestSendGradeIndex: Int? = nil,
        durationSeconds: TimeInterval = 0
    ) {
        self.climbs = climbs
        self.sends = sends
        self.flashes = flashes
        self.points = points
        self.hardestSendGradeIndex = hardestSendGradeIndex
        self.durationSeconds = durationSeconds
    }
}

/// The best marks across all prior sessions, used as the bar a new session must
/// clear to set a record.
public struct PreviousBests: Equatable, Sendable {
    public var hardestSendGradeIndex: Int?
    public var mostSendsInSession: Int
    public var mostPointsInSession: Int
    public var longestSessionSeconds: TimeInterval

    public init(
        hardestSendGradeIndex: Int? = nil,
        mostSendsInSession: Int = 0,
        mostPointsInSession: Int = 0,
        longestSessionSeconds: TimeInterval = 0
    ) {
        self.hardestSendGradeIndex = hardestSendGradeIndex
        self.mostSendsInSession = mostSendsInSession
        self.mostPointsInSession = mostPointsInSession
        self.longestSessionSeconds = longestSessionSeconds
    }
}

/// A personal record broken during a session.
public enum PersonalRecord: Equatable, Sendable, Identifiable {
    case hardestSend(grade: String)
    case mostSends(Int)
    case mostPoints(Int)
    case longestSession(TimeInterval)

    public var id: String {
        switch self {
        case .hardestSend: return "hardestSend"
        case .mostSends: return "mostSends"
        case .mostPoints: return "mostPoints"
        case .longestSession: return "longestSession"
        }
    }

    public var title: String {
        switch self {
        case .hardestSend: return "Hardest send"
        case .mostSends: return "Most sends in a session"
        case .mostPoints: return "Most points in a session"
        case .longestSession: return "Longest session"
        }
    }

    public var detail: String {
        switch self {
        case .hardestSend(let grade): return grade
        case .mostSends(let count): return "\(count)"
        case .mostPoints(let points): return "\(points) pts"
        case .longestSession(let seconds): return SessionClock.format(seconds)
        }
    }

    public var symbolName: String {
        switch self {
        case .hardestSend: return "trophy.fill"
        case .mostSends: return "checkmark.seal.fill"
        case .mostPoints: return "star.fill"
        case .longestSession: return "clock.badge.checkmark.fill"
        }
    }
}

/// Detects which personal records a just-finished session set.
public enum RecordsEngine {
    /// Records broken by `current`, given the bests from all *prior* sessions and
    /// the label of this session's hardest send (for display). A record requires
    /// strictly beating the previous best, and send/point/duration records only
    /// count when there is something to show (non-zero).
    public static func newRecords(
        current: SessionTotals,
        hardestSendGradeLabel: String?,
        previous: PreviousBests
    ) -> [PersonalRecord] {
        var records: [PersonalRecord] = []

        if let index = current.hardestSendGradeIndex, let label = hardestSendGradeLabel {
            let beatsPrevious = previous.hardestSendGradeIndex.map { index > $0 } ?? true
            if beatsPrevious {
                records.append(.hardestSend(grade: label))
            }
        }

        if current.sends > 0 && current.sends > previous.mostSendsInSession {
            records.append(.mostSends(current.sends))
        }

        if current.points > 0 && current.points > previous.mostPointsInSession {
            records.append(.mostPoints(current.points))
        }

        if current.durationSeconds > 0 && current.durationSeconds > previous.longestSessionSeconds {
            records.append(.longestSession(current.durationSeconds))
        }

        return records
    }
}

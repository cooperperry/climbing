import Foundation
import SwiftData

/// A single climbing session: when it started, when it ended, and the climbs
/// logged during it.
@Model
final class ClimbingSession {
    var startTime: Date

    /// `nil` while the session is in progress.
    var endTime: Date?

    var notes: String

    /// Climbs logged in this session. Deleting the session deletes its logs.
    @Relationship(deleteRule: .cascade, inverse: \ClimbLog.session)
    var logs: [ClimbLog] = []

    init(startTime: Date = .now, endTime: Date? = nil, notes: String = "") {
        self.startTime = startTime
        self.endTime = endTime
        self.notes = notes
    }

    /// A session is active until it is explicitly ended.
    var isActive: Bool { endTime == nil }

    /// Duration through `endTime`, or through `referenceDate` while still active.
    ///
    /// Pass the current date from a `TimelineView` to drive a live timer.
    func duration(asOf referenceDate: Date = .now) -> TimeInterval {
        SessionClock.elapsed(from: startTime, to: endTime ?? referenceDate)
    }

    /// Count of climbs topped out (send or flash) in this session.
    var completionCount: Int {
        logs.filter { $0.outcome.isCompletion }.count
    }
}

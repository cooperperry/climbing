import Foundation
import SwiftData

/// A single logged climb: grade, attempts, outcome, and optional hold/wall tags.
@Model
final class ClimbLog {
    /// The session this climb belongs to.
    var session: ClimbingSession?

    /// The scale the grade was read from. Optional so a log survives deletion of
    /// its scale.
    var gradeScale: CustomGradeScale?

    /// The grade label exactly as recorded, e.g. "V4" or "Blue".
    var gradeLabel: String

    /// Number of attempts. Floored at 1 by the initializer; set through the app,
    /// which never records a value below 1.
    var attempts: Int

    var outcome: ClimbOutcome

    /// Hold / movement character. Optional — most goes are logged as grade +
    /// outcome only; tag later if you care. Optional also migrates legacy rows.
    var style: ClimbStyle?

    /// The wall angle of the climb.
    ///
    /// Stored as optional so it migrates cleanly onto rows saved before `angle`
    /// existed: SwiftData can't backfill a default for a custom enum during
    /// lightweight migration, so a non-optional attribute reads `nil` on legacy
    /// rows and crashes on the cast. Optional avoids that; use `wallAngle` for a
    /// non-optional value that treats legacy `nil` as `.vertical`.
    var angle: ClimbAngle?

    /// Wall angle when tagged; untagged / legacy `nil` is not assumed to be vertical
    /// in the UI. This fallback is only for call sites that still need a value.
    var wallAngle: ClimbAngle { angle ?? .vertical }

    var loggedAt: Date

    /// Encoded `EffortTrace` for a send/flash (Watch motion + HR overlay).
    /// Optional so logs saved before send traces existed migrate as `nil`.
    var effortTraceData: Data?

    /// Decoded send trace, or `nil` when none was captured.
    var effortTrace: EffortTrace? {
        get {
            guard let effortTraceData else { return nil }
            return try? JSONDecoder().decode(EffortTrace.self, from: effortTraceData)
        }
        set {
            if let newValue {
                effortTraceData = try? JSONEncoder().encode(newValue)
            } else {
                effortTraceData = nil
            }
        }
    }

    init(
        gradeLabel: String,
        attempts: Int = 1,
        outcome: ClimbOutcome,
        style: ClimbStyle? = nil,
        angle: ClimbAngle? = nil,
        session: ClimbingSession? = nil,
        gradeScale: CustomGradeScale? = nil,
        loggedAt: Date = .now
    ) {
        self.gradeLabel = gradeLabel
        self.attempts = max(1, attempts)
        self.outcome = outcome
        self.style = style
        self.angle = angle
        self.session = session
        self.gradeScale = gradeScale
        self.loggedAt = loggedAt
    }
}

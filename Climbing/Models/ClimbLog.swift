import Foundation
import SwiftData

/// A single logged climb within a session: its grade, how many attempts it
/// took, the outcome, and the movement style.
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

    /// The movement/hold character of the climb.
    var style: ClimbStyle

    /// The wall angle of the climb.
    var angle: ClimbAngle

    var loggedAt: Date

    init(
        gradeLabel: String,
        attempts: Int = 1,
        outcome: ClimbOutcome,
        style: ClimbStyle,
        angle: ClimbAngle = .vertical,
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

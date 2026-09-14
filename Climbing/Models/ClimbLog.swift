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

    /// Number of attempts, always at least 1.
    private(set) var attempts: Int

    var outcome: ClimbOutcome

    var style: ClimbStyle

    var loggedAt: Date

    init(
        gradeLabel: String,
        attempts: Int = 1,
        outcome: ClimbOutcome,
        style: ClimbStyle,
        session: ClimbingSession? = nil,
        gradeScale: CustomGradeScale? = nil,
        loggedAt: Date = .now
    ) {
        self.gradeLabel = gradeLabel
        self.attempts = max(1, attempts)
        self.outcome = outcome
        self.style = style
        self.session = session
        self.gradeScale = gradeScale
        self.loggedAt = loggedAt
    }

    /// Updates the attempt count, enforcing a floor of 1.
    func setAttempts(_ value: Int) {
        attempts = max(1, value)
    }
}

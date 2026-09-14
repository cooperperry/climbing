import Foundation

extension ClimbLog {
    /// Zero-based difficulty index of this climb within its grade scale.
    /// Falls back to the easiest step when the scale or label is unknown.
    var gradeIndex: Int {
        gradeScale?.index(of: gradeLabel) ?? 0
    }

    /// Points earned for this climb, per `ScoreEngine`.
    var points: Int {
        ScoreEngine.points(gradeIndex: gradeIndex, outcome: outcome)
    }
}

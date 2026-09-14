import Foundation

extension ClimbingSession {
    /// Total points earned across all climbs logged this session.
    var score: Int {
        ScoreEngine.sessionScore(logs.map(\.points))
    }

    /// Number of climbs flashed (first-try sends) this session.
    var flashCount: Int {
        logs.filter { $0.outcome == .flash }.count
    }

    /// The hardest topped-out climb this session, if any.
    var hardestSend: ClimbLog? {
        logs.filter { $0.outcome.isCompletion }.max { $0.gradeIndex < $1.gradeIndex }
    }
}

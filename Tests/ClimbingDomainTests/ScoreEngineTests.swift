import XCTest
@testable import ClimbingDomain

final class ScoreEngineTests: XCTestCase {
    func testDifficultyScalesWithGradeIndex() {
        XCTAssertEqual(ScoreEngine.difficultyPoints(gradeIndex: 0), 10)  // VB
        XCTAssertEqual(ScoreEngine.difficultyPoints(gradeIndex: 1), 20)  // V0
        XCTAssertEqual(ScoreEngine.difficultyPoints(gradeIndex: 6), 70)  // V5
        // Negative indices are clamped to the easiest step.
        XCTAssertEqual(ScoreEngine.difficultyPoints(gradeIndex: -3), 10)
    }

    func testMultiplierOrdering() {
        XCTAssertGreaterThan(
            ScoreEngine.multiplier(for: .flash), ScoreEngine.multiplier(for: .send)
        )
        XCTAssertGreaterThan(
            ScoreEngine.multiplier(for: .send), ScoreEngine.multiplier(for: .project)
        )
        XCTAssertGreaterThan(
            ScoreEngine.multiplier(for: .project), ScoreEngine.multiplier(for: .attempt)
        )
    }

    func testPointsForV5() {
        // V5 -> gradeIndex 6 -> difficulty 70.
        XCTAssertEqual(ScoreEngine.points(gradeIndex: 6, outcome: .flash), 105)
        XCTAssertEqual(ScoreEngine.points(gradeIndex: 6, outcome: .send), 70)
        XCTAssertEqual(ScoreEngine.points(gradeIndex: 6, outcome: .project), 21)
        XCTAssertEqual(ScoreEngine.points(gradeIndex: 6, outcome: .attempt), 7)
    }

    func testHarderGradeAlwaysScoresMoreForSameOutcome() {
        for outcome in [ClimbOutcome.flash, .send, .project] {
            let easier = ScoreEngine.points(gradeIndex: 2, outcome: outcome)
            let harder = ScoreEngine.points(gradeIndex: 8, outcome: outcome)
            XCTAssertGreaterThan(harder, easier, "outcome \(outcome)")
        }
    }

    func testFlashBeatsSendAtSameGrade() {
        XCTAssertGreaterThan(
            ScoreEngine.points(gradeIndex: 4, outcome: .flash),
            ScoreEngine.points(gradeIndex: 4, outcome: .send)
        )
    }

    func testSessionScoreSumsPoints() {
        XCTAssertEqual(ScoreEngine.sessionScore([70, 105, 21]), 196)
        XCTAssertEqual(ScoreEngine.sessionScore([]), 0)
    }

    func testLevelBoundaries() {
        XCTAssertEqual(ScoreEngine.level(forTotalPoints: 0).title, "Beginner")
        XCTAssertEqual(ScoreEngine.level(forTotalPoints: 0).number, 1)
        XCTAssertEqual(ScoreEngine.level(forTotalPoints: 249).title, "Beginner")
        XCTAssertEqual(ScoreEngine.level(forTotalPoints: 250).title, "Novice")
        XCTAssertEqual(ScoreEngine.level(forTotalPoints: 250).number, 2)
        XCTAssertEqual(ScoreEngine.level(forTotalPoints: 11_999).title, "Elite")
        XCTAssertEqual(ScoreEngine.level(forTotalPoints: 12_000).title, "Pro")
    }

    func testMaxLevelHasNoNext() {
        let pro = ScoreEngine.level(forTotalPoints: 50_000)
        XCTAssertEqual(pro.title, "Pro")
        XCTAssertTrue(pro.isMaxLevel)
        XCTAssertNil(pro.nextLevelPoints)
    }

    func testNegativeTotalsClampToFirstLevel() {
        let level = ScoreEngine.level(forTotalPoints: -100)
        XCTAssertEqual(level.number, 1)
        XCTAssertEqual(level.title, "Beginner")
    }

    func testProgressToNextLevel() {
        // Novice spans 250...750 (span 500). 500 is halfway.
        XCTAssertEqual(ScoreEngine.progressToNextLevel(forTotalPoints: 250), 0.0, accuracy: 0.0001)
        XCTAssertEqual(ScoreEngine.progressToNextLevel(forTotalPoints: 500), 0.5, accuracy: 0.0001)
        XCTAssertEqual(ScoreEngine.progressToNextLevel(forTotalPoints: 749), 0.998, accuracy: 0.001)
        // Max tier is always full.
        XCTAssertEqual(ScoreEngine.progressToNextLevel(forTotalPoints: 20_000), 1.0, accuracy: 0.0001)
    }

    func testPointsToNextLevel() {
        XCTAssertEqual(ScoreEngine.pointsToNextLevel(forTotalPoints: 0), 250)
        XCTAssertEqual(ScoreEngine.pointsToNextLevel(forTotalPoints: 200), 50)
        XCTAssertEqual(ScoreEngine.pointsToNextLevel(forTotalPoints: 250), 500)
        XCTAssertEqual(ScoreEngine.pointsToNextLevel(forTotalPoints: 30_000), 0)
    }
}

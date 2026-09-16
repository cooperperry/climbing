import XCTest
@testable import ClimbingDomain

final class ClimbOutcomeStyleTests: XCTestCase {
    func testCompletionSemantics() {
        XCTAssertTrue(ClimbOutcome.flash.isCompletion)
        XCTAssertTrue(ClimbOutcome.send.isCompletion)
        XCTAssertFalse(ClimbOutcome.project.isCompletion)
        XCTAssertFalse(ClimbOutcome.attempt.isCompletion)
    }

    func testRankOrdersBestFirst() {
        let sorted = ClimbOutcome.allCases.sorted { $0.rank < $1.rank }
        XCTAssertEqual(sorted, [.flash, .send, .project, .attempt])
    }

    func testEveryOutcomeHasDisplayNameAndSymbol() {
        for outcome in ClimbOutcome.allCases {
            XCTAssertFalse(outcome.displayName.isEmpty)
            XCTAssertFalse(outcome.symbolName.isEmpty)
        }
    }

    func testOutcomeRoundTripsThroughRawValue() {
        for outcome in ClimbOutcome.allCases {
            XCTAssertEqual(ClimbOutcome(rawValue: outcome.rawValue), outcome)
        }
    }

    func testQuickTapStylesAreUniqueAndValid() {
        let quick = ClimbStyle.quickTap
        XCTAssertEqual(Set(quick).count, quick.count, "quick-tap styles must be unique")
        XCTAssertTrue(quick.allSatisfy { ClimbStyle.allCases.contains($0) })
    }

    func testEveryStyleHasDisplayNameAndSymbol() {
        for style in ClimbStyle.allCases {
            XCTAssertFalse(style.displayName.isEmpty)
            XCTAssertFalse(style.symbolName.isEmpty)
        }
    }

    func testStylesNoLongerIncludeHoldOnlyOrAngleTerms() {
        // Jug is a hold, not a style; slab/overhang/etc. are angles, not styles.
        let raw = Set(ClimbStyle.allCases.map(\.rawValue))
        for absent in ["jug", "slab", "vertical", "overhang", "roof"] {
            XCTAssertFalse(raw.contains(absent), "\(absent) should not be a ClimbStyle")
        }
    }

    func testEveryOutcomeHasAnExplanation() {
        for outcome in ClimbOutcome.allCases {
            XCTAssertFalse(outcome.explanation.isEmpty)
        }
    }

    func testTopOutDerivesFlashOnFirstGoOtherwiseSend() {
        XCTAssertEqual(ClimbOutcome.topOut(attempts: 1), .flash)
        XCTAssertEqual(ClimbOutcome.topOut(attempts: 0), .flash)
        XCTAssertEqual(ClimbOutcome.topOut(attempts: 2), .send)
        XCTAssertEqual(ClimbOutcome.topOut(attempts: 9), .send)
    }

    func testLogCopyIsPlainLanguage() {
        XCTAssertEqual(ClimbOutcome.flash.logSubtitle, "First try")
        XCTAssertEqual(ClimbOutcome.send.logSubtitle, "Topped it")
        XCTAssertEqual(ClimbOutcome.attempt.displayName, "Didn't send")
        XCTAssertEqual(ClimbOutcome.attempt.logSubtitle, "Fell / no top")
    }
}

final class ClimbDisciplineTests: XCTestCase {
    func testDisplayNamesArePlainLanguage() {
        XCTAssertEqual(ClimbDiscipline.boulder.displayName, "Bouldering")
        XCTAssertEqual(ClimbDiscipline.topRope.displayName, "Top rope")
        XCTAssertEqual(ClimbDiscipline.lead.displayName, "Lead")
    }

    func testShortNamesAreFullWords() {
        XCTAssertEqual(ClimbDiscipline.boulder.shortName, "Boulder")
        XCTAssertEqual(ClimbDiscipline.topRope.shortName, "Top rope")
        XCTAssertEqual(ClimbDiscipline.lead.shortName, "Lead")
    }

    func testOnlyBoulderUsesVScale() {
        XCTAssertFalse(ClimbDiscipline.boulder.usesRopeGrades)
        XCTAssertTrue(ClimbDiscipline.topRope.usesRopeGrades)
        XCTAssertTrue(ClimbDiscipline.lead.usesRopeGrades)
    }

    func testRoundTripsThroughRawValue() {
        for discipline in ClimbDiscipline.allCases {
            XCTAssertEqual(ClimbDiscipline(rawValue: discipline.rawValue), discipline)
        }
    }
}

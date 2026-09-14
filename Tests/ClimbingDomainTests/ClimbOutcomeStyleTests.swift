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
}

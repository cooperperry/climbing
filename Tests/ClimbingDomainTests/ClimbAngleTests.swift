import XCTest
@testable import ClimbingDomain

final class ClimbAngleTests: XCTestCase {
    func testAllAnglesPresentInDifficultyOrder() {
        XCTAssertEqual(
            ClimbAngle.allCases, [.slab, .vertical, .overhang, .roof]
        )
    }

    func testEveryAngleHasDisplayNameAndSymbol() {
        for angle in ClimbAngle.allCases {
            XCTAssertFalse(angle.displayName.isEmpty)
            XCTAssertFalse(angle.symbolName.isEmpty)
        }
    }

    func testAngleRoundTripsThroughRawValue() {
        for angle in ClimbAngle.allCases {
            XCTAssertEqual(ClimbAngle(rawValue: angle.rawValue), angle)
        }
    }
}

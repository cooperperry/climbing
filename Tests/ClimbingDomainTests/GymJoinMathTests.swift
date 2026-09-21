import XCTest
@testable import ClimbingDomain

final class GymJoinMathTests: XCTestCase {
    func testNormalizedNamesMatchDespiteSpacingAndCase() {
        XCTAssertTrue(GymJoinMath.namesMatch("Movement  RiNo", "movement rino"))
        XCTAssertFalse(GymJoinMath.namesMatch("Movement RiNo", "Movement Baker"))
        XCTAssertFalse(GymJoinMath.namesMatch("  ", "Movement"))
    }

    func testJoinCodeIsSixCharacters() {
        let code = GymJoinMath.joinCode(from: UUID(uuidString: "AABBCCDD-EEFF-0011-2233-445566778899")!)
        XCTAssertEqual(code, "AABBCC")
        XCTAssertTrue(GymJoinMath.codesMatch("aabbcc", "AABBCC"))
        XCTAssertFalse(GymJoinMath.codesMatch("AABBCC", "AABBCD"))
    }

    func testPinCoordinatesClampToTheMap() {
        let pin = GymMapPin(name: "Cave", x: 1.4, y: -0.2)
        XCTAssertEqual(pin.x, 1)
        XCTAssertEqual(pin.y, 0)
    }

    func testNameNeedsTwoCharacters() {
        XCTAssertFalse(GymJoinMath.isUsableName("A"))
        XCTAssertTrue(GymJoinMath.isUsableName("AB"))
    }
}

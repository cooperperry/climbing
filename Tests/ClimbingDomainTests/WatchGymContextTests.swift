import XCTest
@testable import ClimbingDomain

final class WatchGymContextTests: XCTestCase {
    func testRoundTripKeepsPins() throws {
        let original = WatchGymContext(
            gymName: "Movement RiNo",
            walls: [
                WatchWall(
                    name: "Cave",
                    routes: [
                        WatchRoutePin(grade: "V4", color: HoldColor.blue.rawValue, x: 0.2, y: 0.4)
                    ]
                ),
                WatchWall(name: "Comp"),
            ],
            currentWall: "Cave"
        )
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(WatchGymContext.self, from: data)
        XCTAssertEqual(decoded.gymName, "Movement RiNo")
        XCTAssertEqual(decoded.wallNames, ["Cave", "Comp"])
        XCTAssertEqual(decoded.wall(named: "Cave")?.routes.first?.grade, "V4")
        XCTAssertEqual(decoded.wall(named: "Cave")?.routes.first?.holdColor, .blue)
        XCTAssertTrue(decoded.wall(named: "Cave")?.outline.isEmpty ?? false)
    }

    func testWallOutlineRoundTripsAndLegacyOmitsIt() throws {
        let original = WatchWall(
            name: "Cave",
            routes: [],
            outline: [WatchOutlinePoint(x: 0.2, y: 0.2), WatchOutlinePoint(x: 0.8, y: 0.8)],
            closed: true
        )
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(WatchWall.self, from: data)
        XCTAssertEqual(decoded.outline.count, 2)
        XCTAssertTrue(decoded.closed)

        let legacy = """
        {"name":"Cave","routes":[]}
        """.data(using: .utf8)!
        let old = try JSONDecoder().decode(WatchWall.self, from: legacy)
        XCTAssertTrue(old.outline.isEmpty)
        XCTAssertFalse(old.closed)
    }

    func testLegacyWallNameArrayStillDecodes() throws {
        let json = """
        {"gymName":"Movement RiNo","walls":["Cave","Comp"],"currentWall":"Cave"}
        """.data(using: .utf8)!
        let decoded = try JSONDecoder().decode(WatchGymContext.self, from: json)
        XCTAssertEqual(decoded.wallNames, ["Cave", "Comp"])
        XCTAssertTrue(decoded.wall(named: "Cave")?.routes.isEmpty ?? false)
    }

    func testPinCoordinatesClampToThePhoto() {
        let pin = WatchRoutePin(grade: "V2", color: HoldColor.red.rawValue, x: 1.4, y: -0.2)
        XCTAssertEqual(pin.x, 1)
        XCTAssertEqual(pin.y, 0)
    }

    func testPhoneMapTapReplacesWatchPick() {
        XCTAssertEqual(
            WatchGymContext.pickWall(
                walls: ["Cave", "Comp"],
                phoneCurrent: "Comp",
                previousPhoneCurrent: "Cave",
                watchWall: "Cave"
            ),
            "Comp"
        )
    }

    func testWatchPickSurvivesUnchangedPhoneSnapshot() {
        XCTAssertEqual(
            WatchGymContext.pickWall(
                walls: ["Cave", "Comp"],
                phoneCurrent: "Cave",
                previousPhoneCurrent: "Cave",
                watchWall: "Comp"
            ),
            "Comp"
        )
    }

    func testDroppedWallFallsBackAfterSetReset() {
        XCTAssertEqual(
            WatchGymContext.pickWall(
                walls: ["Moonboard"],
                phoneCurrent: "Cave",
                previousPhoneCurrent: "Cave",
                watchWall: "Cave"
            ),
            "Moonboard"
        )
    }

    func testEmptyWallsMeansNoCurrentWall() {
        XCTAssertNil(
            WatchGymContext.pickWall(
                walls: [],
                phoneCurrent: "Cave",
                previousPhoneCurrent: nil,
                watchWall: "Cave"
            )
        )
    }

    func testCreditUsesTheClimberName() {
        XCTAssertEqual(RouteCredit.line(name: "Jack", at: nil), "Jack")
        XCTAssertEqual(RouteCredit.line(name: "  ", at: nil), "Someone")
    }
}

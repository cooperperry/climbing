import XCTest
@testable import ClimbingDomain

final class FloorPlanShapeTests: XCTestCase {
    func testDefaultSegmentIsCenteredOnAnchor() {
        let anchor = PlanPoint(x: 0.4, y: 0.6)
        let seg = FloorPlanMath.defaultSegment(anchor: anchor, halfWidth: 0.1)
        XCTAssertEqual(seg.count, 2)
        let mid = FloorPlanMath.centroid(of: seg)
        XCTAssertEqual(mid.x, anchor.x, accuracy: 1e-9)
        XCTAssertEqual(mid.y, anchor.y, accuracy: 1e-9)
    }

    func testRoundTripEncode() {
        let points = [
            PlanPoint(x: 0.1, y: 0.2),
            PlanPoint(x: 0.9, y: 0.8),
        ]
        let data = FloorPlanMath.encode(points)
        XCTAssertNotNil(data)
        XCTAssertEqual(FloorPlanMath.decode(data), points)
    }

    func testTranslateClampsToBoard() {
        let points = [PlanPoint(x: 0.95, y: 0.5)]
        let moved = FloorPlanMath.translate(points: points, dx: 0.2, dy: 0)
        XCTAssertEqual(moved[0].x, 1.0, accuracy: 1e-9)
    }
}

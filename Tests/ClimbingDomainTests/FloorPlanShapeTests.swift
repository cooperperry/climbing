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

    func testSquareHasFourCorners() {
        let sq = FloorPlanMath.square(center: PlanPoint(x: 0.5, y: 0.5), size: 0.2)
        XCTAssertEqual(sq.count, 4)
        XCTAssertEqual(FloorPlanMath.centroid(of: sq).x, 0.5, accuracy: 1e-9)
    }

    func testInsertVertexOnEdge() {
        let line = [
            PlanPoint(x: 0.2, y: 0.5),
            PlanPoint(x: 0.8, y: 0.5),
        ]
        let next = FloorPlanMath.insertingVertex(in: line, at: PlanPoint(x: 0.5, y: 0.51))
        XCTAssertEqual(next?.count, 3)
        XCTAssertEqual(next?[1].x, 0.5, accuracy: 1e-6)
    }

    func testSplitLineInTwo() {
        let line = [
            PlanPoint(x: 0.1, y: 0.5),
            PlanPoint(x: 0.9, y: 0.5),
        ]
        let parts = FloorPlanMath.split(points: line, at: PlanPoint(x: 0.5, y: 0.5))
        XCTAssertEqual(parts?.left.count, 2)
        XCTAssertEqual(parts?.right.count, 2)
        XCTAssertEqual(parts?.left.last?.x, 0.5, accuracy: 1e-6)
        XCTAssertEqual(parts?.right.first?.x, 0.5, accuracy: 1e-6)
    }
}

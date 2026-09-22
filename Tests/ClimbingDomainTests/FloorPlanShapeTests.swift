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
        XCTAssertEqual(FloorPlanMath.decode(nil), [])
        XCTAssertEqual(FloorPlanMath.decode(Data()), [])
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

    func testInsertVertexOnEdge() throws {
        let line = [
            PlanPoint(x: 0.2, y: 0.5),
            PlanPoint(x: 0.8, y: 0.5),
        ]
        let next = try XCTUnwrap(FloorPlanMath.insertingVertex(in: line, at: PlanPoint(x: 0.5, y: 0.51)))
        XCTAssertEqual(next.count, 3)
        XCTAssertEqual(next[1].x, 0.5, accuracy: 1e-6)
    }

    func testInsertVertexRejectedWhenFarFromEdge() {
        let line = [
            PlanPoint(x: 0.2, y: 0.5),
            PlanPoint(x: 0.8, y: 0.5),
        ]
        XCTAssertNil(FloorPlanMath.insertingVertex(in: line, at: PlanPoint(x: 0.5, y: 0.3)))
    }

    func testSplitLineInTwo() throws {
        let line = [
            PlanPoint(x: 0.1, y: 0.5),
            PlanPoint(x: 0.9, y: 0.5),
        ]
        let parts = try XCTUnwrap(FloorPlanMath.split(points: line, at: PlanPoint(x: 0.5, y: 0.5)))
        XCTAssertEqual(parts.left.count, 2)
        XCTAssertEqual(parts.right.count, 2)
        XCTAssertEqual(parts.left.last!.x, 0.5, accuracy: 1e-6)
        XCTAssertEqual(parts.right.first!.x, 0.5, accuracy: 1e-6)
    }

    func testRectangleFromDragCorners() {
        let rect = FloorPlanMath.rectangle(
            from: PlanPoint(x: 0.2, y: 0.3),
            to: PlanPoint(x: 0.6, y: 0.7)
        )
        XCTAssertEqual(rect.count, 4)
        XCTAssertEqual(rect[0].x, 0.2, accuracy: 1e-9)
        XCTAssertEqual(rect[2].x, 0.6, accuracy: 1e-9)
        XCTAssertEqual(rect[2].y, 0.7, accuracy: 1e-9)
        XCTAssertTrue(FloorPlanMath.isUsableRectangle(rect))
    }

    func testTinyRectangleRejected() {
        let rect = FloorPlanMath.rectangle(
            from: PlanPoint(x: 0.5, y: 0.5),
            to: PlanPoint(x: 0.51, y: 0.51)
        )
        XCTAssertFalse(FloorPlanMath.isUsableRectangle(rect))
    }

    func testStrokeLengthGate() {
        XCTAssertFalse(FloorPlanMath.isUsableStroke(
            from: PlanPoint(x: 0.5, y: 0.5),
            to: PlanPoint(x: 0.51, y: 0.5)
        ))
        XCTAssertTrue(FloorPlanMath.isUsableStroke(
            from: PlanPoint(x: 0.2, y: 0.5),
            to: PlanPoint(x: 0.8, y: 0.5)
        ))
    }

    func testOptionalWallNameAllowsBlank() {
        XCTAssertEqual(FloorPlanMath.optionalWallName("  "), "")
        XCTAssertEqual(FloorPlanMath.optionalWallName(" Cave "), "Cave")
        XCTAssertEqual(FloorPlanMath.displayWallName(""), "Untitled")
        XCTAssertEqual(FloorPlanMath.displayWallName("360 A"), "360 A")
    }

    func testPolygonClosesNearStart() {
        let draft = [
            PlanPoint(x: 0.2, y: 0.2),
            PlanPoint(x: 0.8, y: 0.2),
            PlanPoint(x: 0.8, y: 0.8),
        ]
        XCTAssertTrue(FloorPlanMath.shouldClosePolygon(draft: draft, to: PlanPoint(x: 0.21, y: 0.22)))
        XCTAssertFalse(FloorPlanMath.shouldClosePolygon(draft: draft, to: PlanPoint(x: 0.5, y: 0.5)))
        XCTAssertFalse(FloorPlanMath.shouldClosePolygon(draft: [PlanPoint(x: 0.2, y: 0.2)], to: PlanPoint(x: 0.2, y: 0.2)))
    }

    func testExtendedPointContinuesDirection() {
        let points = [
            PlanPoint(x: 0.2, y: 0.5),
            PlanPoint(x: 0.4, y: 0.5),
        ]
        let tip = FloorPlanMath.extendedPoint(after: points, step: 0.1)
        XCTAssertEqual(tip.x, 0.5, accuracy: 1e-6)
        XCTAssertEqual(tip.y, 0.5, accuracy: 1e-6)
    }

    func testAddSegmentHandlePastEnd() {
        let points = [
            PlanPoint(x: 0.3, y: 0.3),
            PlanPoint(x: 0.3, y: 0.5),
        ]
        let handle = FloorPlanMath.addSegmentHandle(after: points, step: 0.1)
        XCTAssertEqual(handle.x, 0.3, accuracy: 1e-6)
        XCTAssertEqual(handle.y, 0.6, accuracy: 1e-6)
    }
}

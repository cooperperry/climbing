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
        let handle = FloorPlanMath.addSegmentHandle(after: points)
        // Last segment length is 0.2, so + sits another 0.2 beyond the end.
        XCTAssertEqual(handle.x, 0.3, accuracy: 1e-6)
        XCTAssertEqual(handle.y, 0.7, accuracy: 1e-6)
    }

    func testAddSegmentHandleBeforeStart() {
        let points = [
            PlanPoint(x: 0.3, y: 0.3),
            PlanPoint(x: 0.3, y: 0.5),
        ]
        let handle = FloorPlanMath.addSegmentHandle(before: points)
        XCTAssertEqual(handle.x, 0.3, accuracy: 1e-6)
        XCTAssertEqual(handle.y, 0.1, accuracy: 1e-6)
    }

    func testAddSegmentHandlePastBoardEdgeStaysOffCanvas() {
        let points = [
            PlanPoint(x: 0.7, y: 0.5),
            PlanPoint(x: 0.95, y: 0.5),
        ]
        let handle = FloorPlanMath.addSegmentHandle(after: points)
        // Segment length 0.25 → tip at 0.95 + 0.25 = 1.2 (must not clamp to 1.0).
        XCTAssertEqual(handle.x, 1.2, accuracy: 1e-6)
        XCTAssertEqual(handle.y, 0.5, accuracy: 1e-6)
    }

    func testPointAlongOpenLine() {
        let line = [
            PlanPoint(x: 0.0, y: 0.5),
            PlanPoint(x: 1.0, y: 0.5),
        ]
        let mid = FloorPlanMath.pointAlong(points: line, closed: false, t: 0.5)
        XCTAssertEqual(mid.x, 0.5, accuracy: 1e-6)
        XCTAssertEqual(mid.y, 0.5, accuracy: 1e-6)
    }

    func testRouteSlotsSpreadAlongWall() {
        let line = [
            PlanPoint(x: 0.0, y: 0.5),
            PlanPoint(x: 1.0, y: 0.5),
        ]
        let slots = FloorPlanMath.routeSlots(count: 3, on: line, closed: false)
        XCTAssertEqual(slots.count, 3)
        XCTAssertEqual(slots[0].x, 0.0, accuracy: 1e-6)
        XCTAssertEqual(slots[1].x, 0.5, accuracy: 1e-6)
        XCTAssertEqual(slots[2].x, 1.0, accuracy: 1e-6)
    }

    func testRouteSlotsOnClosedWallRingAroundLoop() {
        let square = FloorPlanMath.square(center: PlanPoint(x: 0.5, y: 0.5), size: 0.2)
        let slots = FloorPlanMath.routeSlots(count: 4, on: square, closed: true)
        XCTAssertEqual(slots.count, 4)
        // Four evenly spaced points on the perimeter — not stacked at corners only.
        let xs = Set(slots.map { round($0.x * 1000) / 1000 })
        XCTAssertGreaterThan(xs.count, 1)
    }

    func testLayoutRoutesClosedUsesRingOutsideWall() {
        let square = FloorPlanMath.square(center: PlanPoint(x: 0.5, y: 0.5), size: 0.2)
        let slots = FloorPlanMath.layoutRoutes(count: 6, on: square, closed: true)
        XCTAssertEqual(slots.count, 6)
        let center = FloorPlanMath.centroid(of: square)
        let wallRadius = square.map { FloorPlanMath.distance($0, center) }.max() ?? 0
        for slot in slots {
            XCTAssertGreaterThan(FloorPlanMath.distance(slot, center), wallRadius)
        }
    }

    func testMergeRouteLayoutCombinesOutlinesIntoOneRing() {
        let a = FloorPlanMath.square(center: PlanPoint(x: 0.35, y: 0.5), size: 0.12)
        let b = FloorPlanMath.square(center: PlanPoint(x: 0.65, y: 0.5), size: 0.12)
        let slots = FloorPlanMath.mergeRouteLayout(routeCounts: 8, wallOutlines: [a, b])
        XCTAssertEqual(slots.count, 8)
        let center = FloorPlanMath.centroid(of: a + b)
        let distances = slots.map { FloorPlanMath.distance($0, center) }
        let first = distances[0]
        for d in distances {
            XCTAssertEqual(d, first, accuracy: 1e-6)
        }
    }

    func testCircleSlotsFillRing() {
        let center = PlanPoint(x: 0.5, y: 0.5)
        let slots = FloorPlanMath.circleSlots(count: 4, center: center, radius: 0.1)
        XCTAssertEqual(slots.count, 4)
        for slot in slots {
            XCTAssertEqual(FloorPlanMath.distance(slot, center), 0.1, accuracy: 1e-6)
        }
        // Even spacing: opposite points are diameter apart.
        XCTAssertEqual(FloorPlanMath.distance(slots[0], slots[2]), 0.2, accuracy: 1e-6)
    }

    func testJoinOpenPolylinesAtTouchingEnds() throws {
        let a = [
            PlanPoint(x: 0.1, y: 0.5),
            PlanPoint(x: 0.4, y: 0.5),
        ]
        let b = [
            PlanPoint(x: 0.41, y: 0.5),
            PlanPoint(x: 0.8, y: 0.5),
        ]
        let joined = try XCTUnwrap(FloorPlanMath.joinOpenPolylines(a, b, threshold: 0.05))
        XCTAssertEqual(joined.count, 3)
        XCTAssertEqual(joined[0].x, 0.1, accuracy: 1e-6)
        XCTAssertEqual(joined[joined.count - 1].x, 0.8, accuracy: 1e-6)
    }

    func testShouldCloseOpenShapeWhenEndsMeet() {
        let almost = [
            PlanPoint(x: 0.3, y: 0.3),
            PlanPoint(x: 0.7, y: 0.3),
            PlanPoint(x: 0.7, y: 0.7),
            PlanPoint(x: 0.31, y: 0.31),
        ]
        XCTAssertTrue(FloorPlanMath.shouldCloseOpenShape(points: almost))
        XCTAssertFalse(FloorPlanMath.shouldCloseOpenShape(points: [
            PlanPoint(x: 0.2, y: 0.2),
            PlanPoint(x: 0.8, y: 0.2),
            PlanPoint(x: 0.8, y: 0.8),
        ]))
    }

    func testChromeAnchorSitsAboveCentroid() {
        let points = [
            PlanPoint(x: 0.4, y: 0.5),
            PlanPoint(x: 0.6, y: 0.5),
        ]
        let chrome = FloorPlanMath.chromeAnchor(for: points)
        XCTAssertEqual(chrome.x, 0.5, accuracy: 1e-6)
        XCTAssertLessThan(chrome.y, 0.5)
    }

    func testRemoveOnlySegmentDeletesLine() {
        let line = [
            PlanPoint(x: 0.2, y: 0.5),
            PlanPoint(x: 0.8, y: 0.5),
        ]
        XCTAssertEqual(
            FloorPlanMath.removingSegment(at: 0, from: line, closed: false),
            .empty
        )
    }

    func testRemoveEndSegmentShortensLine() {
        let line = [
            PlanPoint(x: 0.1, y: 0.5),
            PlanPoint(x: 0.5, y: 0.5),
            PlanPoint(x: 0.9, y: 0.5),
        ]
        let result = FloorPlanMath.removingSegment(at: 1, from: line, closed: false)
        guard case .single(let points, let closed) = result else {
            return XCTFail("expected shortened line")
        }
        XCTAssertFalse(closed)
        XCTAssertEqual(points.count, 2)
        XCTAssertEqual(points[0].x, 0.1, accuracy: 1e-9)
        XCTAssertEqual(points[1].x, 0.5, accuracy: 1e-9)
    }

    func testRemoveMiddleSegmentSplitsLine() {
        let line = [
            PlanPoint(x: 0.1, y: 0.5),
            PlanPoint(x: 0.3, y: 0.5),
            PlanPoint(x: 0.7, y: 0.5),
            PlanPoint(x: 0.9, y: 0.5),
        ]
        let result = FloorPlanMath.removingSegment(at: 1, from: line, closed: false)
        guard case .split(let left, let right) = result else {
            return XCTFail("expected split")
        }
        XCTAssertEqual(left.count, 2)
        XCTAssertEqual(right.count, 2)
    }

    func testRemovePolygonEdgeOpensShape() {
        let square = FloorPlanMath.square(center: PlanPoint(x: 0.5, y: 0.5), size: 0.2)
        let result = FloorPlanMath.removingSegment(at: 0, from: square, closed: true)
        guard case .single(let points, let closed) = result else {
            return XCTFail("expected opened polygon")
        }
        XCTAssertFalse(closed)
        XCTAssertEqual(points.count, 4)
        XCTAssertEqual(FloorPlanMath.segmentCount(points: points, closed: false), 3)
    }

    func testSnapToGridRoundsToStep() {
        let raw = PlanPoint(x: 0.127, y: 0.373)
        let snapped = FloorPlanMath.snapToGrid(raw)
        XCTAssertEqual(snapped.x, 0.15, accuracy: 1e-9)
        XCTAssertEqual(snapped.y, 0.35, accuracy: 1e-9)
    }

    func testSnapAngleLocksToHorizontal() {
        let origin = PlanPoint(x: 0.3, y: 0.4)
        let free = PlanPoint(x: 0.55, y: 0.43)
        let snapped = FloorPlanMath.snapAngle(from: origin, to: free)
        XCTAssertEqual(snapped.y, origin.y, accuracy: 1e-6)
        XCTAssertGreaterThan(snapped.x, origin.x)
    }

    func testRing360TemplateHasSixWalls() {
        let ring = FloorPlanTemplates.ring360()
        XCTAssertEqual(ring.count, 6)
        XCTAssertTrue(ring.allSatisfy { $0.zone == "360" })
        XCTAssertEqual(ring.map(\.name), ["360 A", "360 B", "360 C", "360 D", "360 E", "360 F"])
        XCTAssertTrue(ring.allSatisfy { $0.points.count == 3 && $0.closed == false })
    }
}

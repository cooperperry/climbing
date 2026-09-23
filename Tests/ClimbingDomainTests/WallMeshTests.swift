import XCTest
@testable import ClimbingDomain

final class WallMeshTests: XCTestCase {
    func testFloorAloneIsNotAWall() {
        let floor = WallMesh(
            positions: [
                MeshPoint(x: 0, y: 0, z: 0),
                MeshPoint(x: 2, y: 0, z: 0),
                MeshPoint(x: 0, y: 0, z: 2),
            ],
            indices: [0, 1, 2]
        )
        XCTAssertTrue(WallMeshMath.climbingWall(from: floor).isEmpty)
    }

    func testFlatRampIsDropped() {
        let degrees = 15.0 * Double.pi / 180
        let rise = sin(degrees)
        let run = cos(degrees)
        let ramp = quad([
            MeshPoint(x: 0, y: 0, z: 0),
            MeshPoint(x: 1, y: 0, z: 0),
            MeshPoint(x: 1, y: rise, z: run),
            MeshPoint(x: 0, y: rise, z: run),
        ])
        XCTAssertTrue(WallMeshMath.climbingWall(from: ramp).isEmpty)
    }

    func testSlabIsKept() {
        let slab = quad([
            MeshPoint(x: 0, y: 0, z: 0),
            MeshPoint(x: 1, y: 0, z: 0),
            MeshPoint(x: 1, y: 1, z: -1),
            MeshPoint(x: 0, y: 1, z: -1),
        ])
        let cleaned = WallMeshMath.climbingWall(from: slab)
        XCTAssertFalse(cleaned.isEmpty)
        let zs = cleaned.positions.map(\.z)
        XCTAssertGreaterThan((zs.max() ?? 0) - (zs.min() ?? 0), 0.45)
    }

    func testWallFacesTheCameraAndSitsOnTheGround() {
        let wall = quad([
            MeshPoint(x: 0, y: 5, z: 0),
            MeshPoint(x: 0, y: 7, z: 0),
            MeshPoint(x: 0, y: 7, z: 2),
            MeshPoint(x: 0, y: 5, z: 2),
        ])
        let cleaned = WallMeshMath.climbingWall(from: wall)
        XCTAssertFalse(cleaned.isEmpty)
        XCTAssertEqual(cleaned.positions.map(\.y).min() ?? -1, 0, accuracy: 0.02)
        XCTAssertEqual(cleaned.positions.map(\.y).max() ?? -1, 2, accuracy: 0.2)
        let xs = cleaned.positions.map(\.x)
        XCTAssertEqual((xs.max() ?? 0) - (xs.min() ?? 0), 2, accuracy: 0.25)
        for point in cleaned.positions {
            XCTAssertEqual(point.z, 0, accuracy: 0.05)
        }
        let normal = faceNormal(cleaned)
        XCTAssertGreaterThan(normal.z, 0.9)
    }

    func testBoxDropsFloorAndCeiling() {
        let box = unitBox()
        let cleaned = WallMeshMath.climbingWall(from: box)
        let ys = cleaned.positions.map(\.y)
        let xs = cleaned.positions.map(\.x)
        let zs = cleaned.positions.map(\.z)
        let ySpan = (ys.max() ?? 0) - (ys.min() ?? 0)
        let xSpan = (xs.max() ?? 0) - (xs.min() ?? 0)
        let zSpan = (zs.max() ?? 0) - (zs.min() ?? 0)
        XCTAssertFalse(cleaned.isEmpty)
        XCTAssertGreaterThan(ySpan, 0.6)
        XCTAssertLessThan(max(xSpan, ySpan), 1.35)
        XCTAssertLessThan(zSpan, 0.25)
    }

    func testSmallScrapIsDropped() {
        let mesh = WallMesh(
            positions: [
                MeshPoint(x: 0, y: 0, z: 0),
                MeshPoint(x: 0, y: 2, z: 0),
                MeshPoint(x: 0, y: 2, z: 2),
                MeshPoint(x: 0, y: 0, z: 2),
                MeshPoint(x: 5, y: 0, z: 5),
                MeshPoint(x: 5, y: 0.1, z: 5),
                MeshPoint(x: 5, y: 0.1, z: 5.1),
                MeshPoint(x: 5, y: 0, z: 5.1),
            ],
            indices: [0, 1, 2, 0, 2, 3, 4, 5, 6, 4, 6, 7]
        )
        let cleaned = WallMeshMath.climbingWall(from: mesh)
        let ys = cleaned.positions.map(\.y)
        let xs = cleaned.positions.map(\.x)
        let zs = cleaned.positions.map(\.z)
        XCTAssertGreaterThan((ys.max() ?? 0) - (ys.min() ?? 0), 1.5)
        XCTAssertLessThan((xs.max() ?? 0) - (xs.min() ?? 0), 2.6)
        XCTAssertLessThan((zs.max() ?? 0) - (zs.min() ?? 0), 0.4)
    }

    func testNearbyNoiseWeldsIntoOneFace() {
        let mesh = WallMesh(
            positions: [
                MeshPoint(x: 0, y: 0, z: 0),
                MeshPoint(x: 0, y: 1, z: 0),
                MeshPoint(x: 1, y: 1, z: 0),
                MeshPoint(x: 0.01, y: 0.01, z: 0),
                MeshPoint(x: 0.01, y: 1.01, z: 0),
                MeshPoint(x: 1.01, y: 1.01, z: 0),
            ],
            indices: [0, 1, 2, 3, 4, 5]
        )
        let cleaned = WallMeshMath.climbingWall(from: mesh, voxelSize: 0.04)
        let zs = cleaned.positions.map(\.z)
        XCTAssertFalse(cleaned.isEmpty)
        XCTAssertLessThan((zs.max() ?? 1) - (zs.min() ?? 0), 0.1)
    }

    func testFarPanelAndSideWallAreLeftOut() {
        let mesh = WallMesh(
            positions: [
                MeshPoint(x: 0, y: 0, z: 0),
                MeshPoint(x: 0, y: 2, z: 0),
                MeshPoint(x: 0, y: 2, z: 2),
                MeshPoint(x: 0, y: 0, z: 2),
                MeshPoint(x: 3, y: 0, z: 0),
                MeshPoint(x: 3, y: 0.5, z: 0),
                MeshPoint(x: 3, y: 0.5, z: 0.5),
                MeshPoint(x: 3, y: 0, z: 0.5),
                MeshPoint(x: 0, y: 0, z: 0),
                MeshPoint(x: 1, y: 0, z: 0),
                MeshPoint(x: 1, y: 1, z: 0),
                MeshPoint(x: 0, y: 1, z: 0),
            ],
            indices: [
                0, 1, 2, 0, 2, 3,
                4, 5, 6, 4, 6, 7,
                8, 9, 10, 8, 10, 11,
            ]
        )
        let cleaned = WallMeshMath.climbingWall(from: mesh)
        let ys = cleaned.positions.map(\.y)
        let zs = cleaned.positions.map(\.z)
        XCTAssertGreaterThan((ys.max() ?? 0) - (ys.min() ?? 0), 1.5)
        XCTAssertLessThan((zs.max() ?? 1) - (zs.min() ?? 0), 0.8)
    }

    private func quad(_ points: [MeshPoint]) -> WallMesh {
        WallMesh(positions: points, indices: [0, 1, 2, 0, 2, 3])
    }

    private func unitBox() -> WallMesh {
        let positions = [
            MeshPoint(x: 0, y: 0, z: 0),
            MeshPoint(x: 1, y: 0, z: 0),
            MeshPoint(x: 1, y: 0, z: 1),
            MeshPoint(x: 0, y: 0, z: 1),
            MeshPoint(x: 0, y: 1, z: 0),
            MeshPoint(x: 1, y: 1, z: 0),
            MeshPoint(x: 1, y: 1, z: 1),
            MeshPoint(x: 0, y: 1, z: 1),
        ]
        let indices = [
            0, 2, 1, 0, 3, 2,
            4, 5, 6, 4, 6, 7,
            0, 1, 5, 0, 5, 4,
            1, 2, 6, 1, 6, 5,
            2, 3, 7, 2, 7, 6,
            3, 0, 4, 3, 4, 7,
        ]
        return WallMesh(positions: positions, indices: indices)
    }

    private func faceNormal(_ mesh: WallMesh) -> MeshPoint {
        unitNormal(
            mesh.positions[mesh.indices[0]],
            mesh.positions[mesh.indices[1]],
            mesh.positions[mesh.indices[2]]
        )
    }

    private func unitNormal(_ a: MeshPoint, _ b: MeshPoint, _ c: MeshPoint) -> MeshPoint {
        let ux = b.x - a.x, uy = b.y - a.y, uz = b.z - a.z
        let vx = c.x - a.x, vy = c.y - a.y, vz = c.z - a.z
        let normal = MeshPoint(
            x: uy * vz - uz * vy,
            y: uz * vx - ux * vz,
            z: ux * vy - uy * vx
        )
        let length = hypot(normal.x, hypot(normal.y, normal.z))
        return MeshPoint(x: normal.x / length, y: normal.y / length, z: normal.z / length)
    }
}

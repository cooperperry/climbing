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
        XCTAssertFalse(WallMeshMath.climbingWall(from: slab).isEmpty)
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
        XCTAssertEqual(cleaned.positions.map(\.y).min() ?? -1, 0, accuracy: 1e-6)
        XCTAssertEqual(cleaned.positions.map(\.y).max() ?? -1, 2, accuracy: 1e-6)
        XCTAssertEqual(cleaned.positions.map(\.x).min() ?? 0, -1, accuracy: 1e-6)
        XCTAssertEqual(cleaned.positions.map(\.x).max() ?? 0, 1, accuracy: 1e-6)
        for point in cleaned.positions {
            XCTAssertEqual(point.z, 0, accuracy: 1e-6)
        }
        let normal = faceNormal(cleaned)
        XCTAssertGreaterThan(normal.z, 0.9)
    }

    func testBoxDropsFloorAndCeiling() {
        let box = unitBox()
        let cleaned = WallMeshMath.climbingWall(from: box)
        XCTAssertEqual(cleaned.indices.count, 24)
        var index = 0
        while index + 2 < cleaned.indices.count {
            let normal = unitNormal(
                cleaned.positions[cleaned.indices[index]],
                cleaned.positions[cleaned.indices[index + 1]],
                cleaned.positions[cleaned.indices[index + 2]]
            )
            XCTAssertLessThanOrEqual(abs(normal.y), 0.2)
            index += 3
        }
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
        XCTAssertEqual(cleaned.positions.count, 4)
        XCTAssertEqual(cleaned.positions.map(\.y).max() ?? 0, 2, accuracy: 1e-6)
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
        XCTAssertEqual(cleaned.indices.count, 3)
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

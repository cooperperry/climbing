import Foundation

/// A point in meters. Y is up.
public struct MeshPoint: Equatable, Sendable, Codable {
    public var x: Double
    public var y: Double
    public var z: Double

    public init(x: Double, y: Double, z: Double) {
        self.x = x
        self.y = y
        self.z = z
    }
}

/// Triangle mesh. Indices are three corners per face.
public struct WallMesh: Equatable, Sendable {
    public var positions: [MeshPoint]
    public var indices: [Int]

    public init(positions: [MeshPoint], indices: [Int]) {
        self.positions = positions
        self.indices = indices
    }

    public var isEmpty: Bool { positions.count < 3 || indices.count < 3 }
}

/// A route stuck on the cleaned climbing wall, in the wall's own meters.
public struct WallRoutePin: Equatable, Sendable, Codable, Identifiable {
    public var id: UUID
    public var grade: String
    public var colorName: String
    public var x: Double
    public var y: Double
    public var z: Double
    public var nx: Double
    public var ny: Double
    public var nz: Double

    public init(
        id: UUID = UUID(),
        grade: String,
        colorName: String,
        x: Double,
        y: Double,
        z: Double,
        nx: Double,
        ny: Double,
        nz: Double
    ) {
        self.id = id
        self.grade = grade
        self.colorName = colorName
        self.x = x
        self.y = y
        self.z = z
        self.nx = nx
        self.ny = ny
        self.nz = nz
    }
}

/// Turns a noisy room scan into one climbable surface facing the camera.
public enum WallMeshMath {
    /// Faces flatter than this (normal's up-component) are floor or ceiling, not wall.
    static let horizontalCutoff = 0.88
    /// Scraps smaller than this fraction of the main surface are dropped.
    static let minimumComponentFraction = 0.15

    public static func climbingWall(from mesh: WallMesh, voxelSize: Double = 0.04) -> WallMesh {
        let faces = climbableFaces(in: mesh)
        guard faces.isEmpty == false else { return WallMesh(positions: [], indices: []) }
        let kept = largestSurface(faces, vertexCount: mesh.positions.count)
        guard kept.isEmpty == false else { return WallMesh(positions: [], indices: []) }
        let welded = weld(kept, positions: mesh.positions, voxelSize: max(voxelSize, 0.005))
        guard welded.isEmpty == false else { return WallMesh(positions: [], indices: []) }
        return orient(welded)
    }

    private struct Face {
        var corners: (Int, Int, Int)
        var area: Double
        var normal: MeshPoint
    }

    private static func climbableFaces(in mesh: WallMesh) -> [Face] {
        var faces: [Face] = []
        var index = 0
        while index + 2 < mesh.indices.count {
            let a = mesh.indices[index]
            let b = mesh.indices[index + 1]
            let c = mesh.indices[index + 2]
            index += 3
            guard mesh.positions.indices.contains(a),
                  mesh.positions.indices.contains(b),
                  mesh.positions.indices.contains(c) else { continue }
            let (normal, length) = cross(mesh.positions[a], mesh.positions[b], mesh.positions[c])
            guard length > 1e-8 else { continue }
            let unitY = abs(normal.y / length)
            guard unitY <= horizontalCutoff else { continue }
            let scale = 1 / length
            faces.append(Face(
                corners: (a, b, c),
                area: length * 0.5,
                normal: MeshPoint(x: normal.x * scale, y: normal.y * scale, z: normal.z * scale)
            ))
        }
        return faces
    }

    /// Keep the main wall and anything still attached to it. Drop floating scraps.
    private static func largestSurface(_ faces: [Face], vertexCount: Int) -> [Face] {
        var parent = Array(0 ..< vertexCount)
        func find(_ start: Int) -> Int {
            var index = start
            while parent[index] != index {
                parent[index] = parent[parent[index]]
                index = parent[index]
            }
            return index
        }
        func unite(_ a: Int, _ b: Int) {
            let left = find(a)
            let right = find(b)
            if left != right { parent[right] = left }
        }
        for face in faces {
            unite(face.corners.0, face.corners.1)
            unite(face.corners.1, face.corners.2)
        }
        var areaByRoot: [Int: Double] = [:]
        for face in faces {
            let root = find(face.corners.0)
            areaByRoot[root, default: 0] += face.area
        }
        let largest = areaByRoot.values.max() ?? 0
        guard largest > 0 else { return [] }
        let minimum = largest * minimumComponentFraction
        return faces.filter { face in
            (areaByRoot[find(face.corners.0)] ?? 0) >= minimum
        }
    }

    private static func weld(_ faces: [Face], positions: [MeshPoint], voxelSize: Double) -> WallMesh {
        struct Key: Hashable {
            var x: Int
            var y: Int
            var z: Int
        }
        var originalSlot: [Int: Int] = [:]
        var keys: [Key: Int] = [:]
        var sums: [MeshPoint] = []
        var counts: [Int] = []
        func slot(_ original: Int) -> Int {
            if let existing = originalSlot[original] { return existing }
            let point = positions[original]
            let key = Key(
                x: Int(floor(point.x / voxelSize)),
                y: Int(floor(point.y / voxelSize)),
                z: Int(floor(point.z / voxelSize))
            )
            let index: Int
            if let existing = keys[key] {
                index = existing
            } else {
                index = sums.count
                keys[key] = index
                sums.append(.init(x: 0, y: 0, z: 0))
                counts.append(0)
            }
            originalSlot[original] = index
            sums[index].x += point.x
            sums[index].y += point.y
            sums[index].z += point.z
            counts[index] += 1
            return index
        }
        struct TriKey: Hashable {
            var a: Int
            var b: Int
            var c: Int
        }
        var seen: Set<TriKey> = []
        var indices: [Int] = []
        for face in faces {
            let mapped = [slot(face.corners.0), slot(face.corners.1), slot(face.corners.2)]
            guard Set(mapped).count == 3 else { continue }
            let ordered = mapped.sorted()
            let key = TriKey(a: ordered[0], b: ordered[1], c: ordered[2])
            guard seen.insert(key).inserted else { continue }
            indices.append(contentsOf: mapped)
        }
        let welded = zip(sums, counts).map { sum, count -> MeshPoint in
            let n = Double(max(count, 1))
            return MeshPoint(x: sum.x / n, y: sum.y / n, z: sum.z / n)
        }
        return WallMesh(positions: welded, indices: indices)
    }

    /// Stand the wall on y = 0 and turn its face toward +Z.
    private static func orient(_ mesh: WallMesh) -> WallMesh {
        var facingX = 0.0
        var facingZ = 0.0
        var index = 0
        while index + 2 < mesh.indices.count {
            let a = mesh.indices[index]
            let b = mesh.indices[index + 1]
            let c = mesh.indices[index + 2]
            index += 3
            guard mesh.positions.indices.contains(a),
                  mesh.positions.indices.contains(b),
                  mesh.positions.indices.contains(c) else { continue }
            let (normal, length) = cross(mesh.positions[a], mesh.positions[b], mesh.positions[c])
            guard length > 1e-8 else { continue }
            facingX += normal.x
            facingZ += normal.z
        }
        let facingLength = hypot(facingX, facingZ)
        let cosAngle = facingLength > 1e-8 ? facingZ / facingLength : 1
        let sinAngle = facingLength > 1e-8 ? facingX / facingLength : 0
        var rotated: [MeshPoint] = mesh.positions.map { point in
            MeshPoint(
                x: point.x * cosAngle - point.z * sinAngle,
                y: point.y,
                z: point.x * sinAngle + point.z * cosAngle
            )
        }
        guard let minY = rotated.map(\.y).min(),
              let minX = rotated.map(\.x).min(),
              let maxX = rotated.map(\.x).max(),
              let minZ = rotated.map(\.z).min(),
              let maxZ = rotated.map(\.z).max() else {
            return mesh
        }
        let midX = (minX + maxX) * 0.5
        let midZ = (minZ + maxZ) * 0.5
        for index in rotated.indices {
            rotated[index].x -= midX
            rotated[index].y -= minY
            rotated[index].z -= midZ
        }
        return WallMesh(positions: rotated, indices: mesh.indices)
    }

    private static func cross(_ a: MeshPoint, _ b: MeshPoint, _ c: MeshPoint) -> (MeshPoint, Double) {
        let ux = b.x - a.x
        let uy = b.y - a.y
        let uz = b.z - a.z
        let vx = c.x - a.x
        let vy = c.y - a.y
        let vz = c.z - a.z
        let normal = MeshPoint(
            x: uy * vz - uz * vy,
            y: uz * vx - ux * vz,
            z: ux * vy - uy * vx
        )
        return (normal, hypot(normal.x, hypot(normal.y, normal.z)))
    }
}

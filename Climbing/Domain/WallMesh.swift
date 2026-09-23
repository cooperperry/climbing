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

/// A route drawn on the cleaned climbing wall, in the wall's own meters.
/// `path` is the finger stroke. Older pins only have a single point.
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
    public var path: [MeshPoint]

    public init(
        id: UUID = UUID(),
        grade: String,
        colorName: String,
        x: Double,
        y: Double,
        z: Double,
        nx: Double,
        ny: Double,
        nz: Double,
        path: [MeshPoint] = []
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
        self.path = path
    }

    public var stroke: [MeshPoint] {
        if path.count >= 2 { return path }
        return [MeshPoint(x: x, y: y, z: z)]
    }

    private enum CodingKeys: String, CodingKey {
        case id, grade, colorName, x, y, z, nx, ny, nz, path
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        grade = try container.decode(String.self, forKey: .grade)
        colorName = try container.decode(String.self, forKey: .colorName)
        x = try container.decode(Double.self, forKey: .x)
        y = try container.decode(Double.self, forKey: .y)
        z = try container.decode(Double.self, forKey: .z)
        nx = try container.decode(Double.self, forKey: .nx)
        ny = try container.decode(Double.self, forKey: .ny)
        nz = try container.decode(Double.self, forKey: .nz)
        path = try container.decodeIfPresent([MeshPoint].self, forKey: .path) ?? []
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(grade, forKey: .grade)
        try container.encode(colorName, forKey: .colorName)
        try container.encode(x, forKey: .x)
        try container.encode(y, forKey: .y)
        try container.encode(z, forKey: .z)
        try container.encode(nx, forKey: .nx)
        try container.encode(ny, forKey: .ny)
        try container.encode(nz, forKey: .nz)
        try container.encode(path, forKey: .path)
    }
}

/// Turns a noisy room scan into one climbable surface facing the camera.
public enum WallMeshMath {
    /// Faces flatter than this (normal's up-component) are floor or ceiling, not wall.
    static let horizontalCutoff = 0.88

    /// One solid climbing surface: the wall the phone was facing, with small holes closed.
    public static func climbingWall(from mesh: WallMesh, voxelSize: Double = 0.05) -> WallMesh {
        let faces = climbableFaces(in: mesh)
        let front = frontFaces(faces, positions: mesh.positions)
        guard front.isEmpty == false else { return WallMesh(positions: [], indices: []) }
        let compact = meshFrom(faces: front, positions: mesh.positions)
        guard compact.isEmpty == false else { return WallMesh(positions: [], indices: []) }
        return solidWall(from: orient(compact), cell: max(voxelSize, 0.02))
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

    /// The surface facing the phone, not the rest of the room or a cabinet in front of it.
    private static func frontFaces(_ faces: [Face], positions: [MeshPoint]) -> [Face] {
        guard faces.isEmpty == false else { return [] }
        let bucketCount = 16
        var areaByBucket = Array(repeating: 0.0, count: bucketCount)
        var angles: [Double] = []
        angles.reserveCapacity(faces.count)
        for face in faces {
            let angle = atan2(face.normal.x, face.normal.z)
            angles.append(angle)
            areaByBucket[bucket(for: angle, count: bucketCount)] += face.area
        }
        guard let winner = areaByBucket.enumerated().max(by: { $0.element < $1.element })?.offset,
              areaByBucket[winner] > 0 else { return [] }
        let center = (Double(winner) + 0.5) / Double(bucketCount) * (2 * Double.pi) - Double.pi
        let dirX = sin(center)
        let dirZ = cos(center)
        let limit = 55.0 * Double.pi / 180
        var aligned: [(Face, Double)] = []
        for (face, angle) in zip(faces, angles) where angleDelta(angle, center) <= limit {
            let depth = centroid(of: face, positions: positions, dirX: dirX, dirZ: dirZ)
            aligned.append((face, depth))
        }
        guard aligned.isEmpty == false else { return [] }
        let slice = 0.5
        var areaBySlice: [Int: Double] = [:]
        for item in aligned {
            let index = Int(floor(item.1 / slice))
            areaBySlice[index, default: 0] += item.0.area
        }
        guard let bestSlice = areaBySlice.max(by: { $0.value < $1.value })?.key else { return [] }
        let plane = (Double(bestSlice) + 0.5) * slice
        return aligned.compactMap { face, depth in
            abs(depth - plane) <= 0.9 ? face : nil
        }
    }

    private static func bucket(for angle: Double, count: Int) -> Int {
        let turns = (angle + Double.pi) / (2 * Double.pi)
        var index = Int(floor(turns * Double(count)))
        if index < 0 { index = 0 }
        if index >= count { index = count - 1 }
        return index
    }

    private static func angleDelta(_ a: Double, _ b: Double) -> Double {
        var delta = abs(a - b)
        if delta > Double.pi { delta = 2 * Double.pi - delta }
        return delta
    }

    private static func centroid(of face: Face, positions: [MeshPoint], dirX: Double, dirZ: Double) -> Double {
        let a = positions[face.corners.0]
        let b = positions[face.corners.1]
        let c = positions[face.corners.2]
        let x = (a.x + b.x + c.x) / 3
        let z = (a.z + b.z + c.z) / 3
        return x * dirX + z * dirZ
    }

    private static func meshFrom(faces: [Face], positions: [MeshPoint]) -> WallMesh {
        var map: [Int: Int] = [:]
        var compact: [MeshPoint] = []
        var indices: [Int] = []
        func slot(_ original: Int) -> Int {
            if let existing = map[original] { return existing }
            let created = compact.count
            map[original] = created
            compact.append(positions[original])
            return created
        }
        for face in faces {
            indices.append(slot(face.corners.0))
            indices.append(slot(face.corners.1))
            indices.append(slot(face.corners.2))
        }
        return WallMesh(positions: compact, indices: indices)
    }

    /// Rasterize the facing surface into a continuous panel and close small gaps.
    private static func solidWall(from mesh: WallMesh, cell: Double) -> WallMesh {
        guard let minX = mesh.positions.map(\.x).min(),
              let minY = mesh.positions.map(\.y).min() else { return mesh }
        var grid: [CellKey: Double] = [:]
        var index = 0
        while index + 2 < mesh.indices.count {
            let ia = mesh.indices[index]
            let ib = mesh.indices[index + 1]
            let ic = mesh.indices[index + 2]
            index += 3
            guard mesh.positions.indices.contains(ia),
                  mesh.positions.indices.contains(ib),
                  mesh.positions.indices.contains(ic) else { continue }
            let a = mesh.positions[ia]
            let b = mesh.positions[ib]
            let c = mesh.positions[ic]
            let minPX = min(a.x, b.x, c.x)
            let maxPX = max(a.x, b.x, c.x)
            let minPY = min(a.y, b.y, c.y)
            let maxPY = max(a.y, b.y, c.y)
            let ix0 = Int(floor((minPX - minX) / cell))
            let ix1 = Int(floor((maxPX - minX) / cell))
            let iy0 = Int(floor((minPY - minY) / cell))
            let iy1 = Int(floor((maxPY - minY) / cell))
            guard ix1 - ix0 <= 200, iy1 - iy0 <= 200 else { continue }
            for ix in ix0 ... ix1 {
                for iy in iy0 ... iy1 {
                    let px = minX + (Double(ix) + 0.5) * cell
                    let py = minY + (Double(iy) + 0.5) * cell
                    guard let z = barycentricZ(px, py, a, b, c) else { continue }
                    let key = CellKey(x: ix, y: iy)
                    grid[key] = max(grid[key] ?? -1e9, z)
                }
            }
        }
        guard grid.isEmpty == false else { return mesh }
        var filled = grid
        for _ in 0 ..< 3 {
            filled = closeGaps(filled)
        }
        filled = smooth(filled)
        return ground(panel(from: filled, originX: minX, originY: minY, cell: cell))
    }

    private static func barycentricZ(_ px: Double, _ py: Double, _ a: MeshPoint, _ b: MeshPoint, _ c: MeshPoint) -> Double? {
        let denominator = (b.y - c.y) * (a.x - c.x) + (c.x - b.x) * (a.y - c.y)
        guard abs(denominator) > 1e-12 else { return nil }
        let w0 = ((b.y - c.y) * (px - c.x) + (c.x - b.x) * (py - c.y)) / denominator
        let w1 = ((c.y - a.y) * (px - c.x) + (a.x - c.x) * (py - c.y)) / denominator
        let w2 = 1 - w0 - w1
        guard w0 >= -0.02, w1 >= -0.02, w2 >= -0.02 else { return nil }
        return w0 * a.z + w1 * b.z + w2 * c.z
    }

    private static func closeGaps(_ grid: [CellKey: Double]) -> [CellKey: Double] {
        var next = grid
        var candidates: Set<CellKey> = []
        for cell in grid.keys {
            for step in neighborSteps where grid[CellKey(x: cell.x + step.0, y: cell.y + step.1)] == nil {
                candidates.insert(CellKey(x: cell.x + step.0, y: cell.y + step.1))
            }
        }
        for cell in candidates {
            var sum = 0.0
            var count = 0
            var left = false
            var right = false
            var below = false
            var above = false
            for step in neighborSteps {
                guard let z = grid[CellKey(x: cell.x + step.0, y: cell.y + step.1)] else { continue }
                sum += z
                count += 1
                if step.0 < 0, step.1 == 0 { left = true }
                if step.0 > 0, step.1 == 0 { right = true }
                if step.1 < 0, step.0 == 0 { below = true }
                if step.1 > 0, step.0 == 0 { above = true }
            }
            let bridged = (left && right) || (below && above)
            if bridged, count >= 3 {
                next[cell] = sum / Double(count)
            }
        }
        return next
    }

    private static func smooth(_ grid: [CellKey: Double]) -> [CellKey: Double] {
        var next = grid
        for (cell, z) in grid {
            var sum = z
            var count = 1.0
            for step in neighborSteps {
                guard let other = grid[CellKey(x: cell.x + step.0, y: cell.y + step.1)] else { continue }
                sum += other
                count += 1
            }
            next[cell] = sum / count
        }
        return next
    }

    private static let neighborSteps: [(Int, Int)] = [
        (-1, -1), (0, -1), (1, -1),
        (-1, 0), (1, 0),
        (-1, 1), (0, 1), (1, 1)
    ]

    private struct CellKey: Hashable {
        var x: Int
        var y: Int
    }

    private static func panel(from grid: [CellKey: Double], originX: Double, originY: Double, cell: Double) -> WallMesh {
        var indexOf: [CellKey: Int] = [:]
        var positions: [MeshPoint] = []
        for (key, z) in grid {
            indexOf[key] = positions.count
            positions.append(MeshPoint(
                x: originX + (Double(key.x) + 0.5) * cell,
                y: originY + (Double(key.y) + 0.5) * cell,
                z: z
            ))
        }
        var indices: [Int] = []
        for key in grid.keys {
            let right = CellKey(x: key.x + 1, y: key.y)
            let above = CellKey(x: key.x, y: key.y + 1)
            let aboveRight = CellKey(x: key.x + 1, y: key.y + 1)
            guard let i00 = indexOf[key],
                  let i10 = indexOf[right],
                  let i01 = indexOf[above],
                  let i11 = indexOf[aboveRight] else { continue }
            indices.append(contentsOf: [i00, i10, i11, i00, i11, i01])
        }
        return WallMesh(positions: positions, indices: indices)
    }

    private static func ground(_ mesh: WallMesh) -> WallMesh {
        guard mesh.isEmpty == false,
              let minY = mesh.positions.map(\.y).min(),
              let minX = mesh.positions.map(\.x).min(),
              let maxX = mesh.positions.map(\.x).max(),
              let minZ = mesh.positions.map(\.z).min(),
              let maxZ = mesh.positions.map(\.z).max() else { return mesh }
        let midX = (minX + maxX) * 0.5
        let midZ = (minZ + maxZ) * 0.5
        let positions = mesh.positions.map { point in
            MeshPoint(x: point.x - midX, y: point.y - minY, z: point.z - midZ)
        }
        return WallMesh(positions: positions, indices: mesh.indices)
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

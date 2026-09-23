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
        var filled = largestPatch(grid)
        for _ in 0 ..< 2 {
            filled = fillEnclosed(filled, reach: 10)
        }
        for _ in 0 ..< 4 {
            filled = closeGaps(filled)
        }
        for _ in 0 ..< 3 {
            filled = trimSpurs(filled)
        }
        filled = smooth(filled)
        filled = constructPanels(filled)
        let shell = ground(panel(from: filled, originX: minX, originY: minY, cell: cell))
        return thicken(shell, depth: 0.1)
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

    /// Drop floating scraps so a gap fill cannot bridge over to furniture.
    private static func largestPatch(_ grid: [CellKey: Double]) -> [CellKey: Double] {
        let keys = Array(grid.keys)
        guard keys.isEmpty == false else { return grid }
        var indexOf: [CellKey: Int] = [:]
        for (index, key) in keys.enumerated() { indexOf[key] = index }
        var parent = Array(0 ..< keys.count)
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
        let orthogonal = [(1, 0), (-1, 0), (0, 1), (0, -1)]
        for (index, key) in keys.enumerated() {
            for step in orthogonal {
                if let other = indexOf[CellKey(x: key.x + step.0, y: key.y + step.1)] {
                    unite(index, other)
                }
            }
        }
        var counts: [Int: Int] = [:]
        for index in keys.indices {
            counts[find(index), default: 0] += 1
        }
        let largest = counts.values.max() ?? 0
        let minimum = max(4, Int(Double(largest) * 0.15))
        var kept: [CellKey: Double] = [:]
        for (index, key) in keys.enumerated() where (counts[find(index)] ?? 0) >= minimum {
            if let z = grid[key] { kept[key] = z }
        }
        return kept.isEmpty ? grid : kept
    }

    /// Fill a missing patch when the wall continues on both sides, up to about half a meter.
    private static func fillEnclosed(_ grid: [CellKey: Double], reach: Int) -> [CellKey: Double] {
        guard let minX = grid.keys.map(\.x).min(),
              let maxX = grid.keys.map(\.x).max(),
              let minY = grid.keys.map(\.y).min(),
              let maxY = grid.keys.map(\.y).max() else { return grid }
        var next = grid
        for x in minX ... maxX {
            for y in minY ... maxY {
                let key = CellKey(x: x, y: y)
                if grid[key] != nil { continue }
                if let horizontal = bridge(grid, x: x, y: y, stepX: 1, stepY: 0, reach: reach),
                   abs(horizontal.0 - horizontal.1) < 0.55 {
                    next[key] = (horizontal.0 + horizontal.1) / 2
                } else if let vertical = bridge(grid, x: x, y: y, stepX: 0, stepY: 1, reach: reach),
                          abs(vertical.0 - vertical.1) < 0.55 {
                    next[key] = (vertical.0 + vertical.1) / 2
                }
            }
        }
        return next
    }

    /// Z on both sides of an empty cell, when each side is within `reach`.
    private static func bridge(
        _ grid: [CellKey: Double],
        x: Int,
        y: Int,
        stepX: Int,
        stepY: Int,
        reach: Int
    ) -> (Double, Double)? {
        var negative: Double?
        var positive: Double?
        for step in 1 ... reach {
            if negative == nil, let z = grid[CellKey(x: x - stepX * step, y: y - stepY * step)] {
                negative = z
            }
            if positive == nil, let z = grid[CellKey(x: x + stepX * step, y: y + stepY * step)] {
                positive = z
            }
        }
        guard let negative, let positive else { return nil }
        return (negative, positive)
    }

    /// Turn scan ripple into a few flat sheets, and a real bulge into a flat volume.
    private static func constructPanels(_ grid: [CellKey: Double]) -> [CellKey: Double] {
        var remaining = grid
        var planes: [(a: Double, b: Double, c: Double)] = []
        var assigned: [CellKey: Double] = [:]
        while remaining.count >= 12 {
            let samples = remaining.map { (Double($0.key.x), Double($0.key.y), $0.value) }
            guard let plane = fitPlane(samples) else { break }
            var inliers: [CellKey: Double] = [:]
            for (cell, z) in remaining {
                let predicted = plane.a * Double(cell.x) + plane.b * Double(cell.y) + plane.c
                if abs(predicted - z) <= 0.05 {
                    inliers[cell] = predicted
                }
            }
            if inliers.count < 12 { break }
            planes.append((plane.a, plane.b, plane.c))
            for (cell, z) in inliers {
                assigned[cell] = z
                remaining.removeValue(forKey: cell)
            }
        }
        guard planes.isEmpty == false else { return grid }

        var caps: [CellKey: Double] = [:]
        for (cell, z) in remaining {
            var nearest = planes[0]
            var error = Double.greatestFiniteMagnitude
            for plane in planes {
                let predicted = plane.a * Double(cell.x) + plane.b * Double(cell.y) + plane.c
                let delta = abs(predicted - z)
                if delta < error {
                    error = delta
                    nearest = plane
                }
            }
            if error <= 0.08 {
                assigned[cell] = nearest.a * Double(cell.x) + nearest.b * Double(cell.y) + nearest.c
            } else {
                caps[cell] = z
            }
        }

        var seen: Set<CellKey> = []
        let orthogonal = [(1, 0), (-1, 0), (0, 1), (0, -1)]
        for start in caps.keys where seen.contains(start) == false {
            var cluster: [CellKey] = []
            var queue = [start]
            seen.insert(start)
            while let cell = queue.popLast() {
                cluster.append(cell)
                for step in orthogonal {
                    let next = CellKey(x: cell.x + step.0, y: cell.y + step.1)
                    if caps[next] != nil, seen.insert(next).inserted {
                        queue.append(next)
                    }
                }
            }
            if cluster.count >= 8 {
                let heights = cluster.compactMap { caps[$0] }.sorted()
                let cap = heights[heights.count / 2]
                for cell in cluster { assigned[cell] = cap }
            } else {
                for cell in cluster {
                    let z = caps[cell] ?? 0
                    var best = planes[0]
                    var error = Double.greatestFiniteMagnitude
                    for plane in planes {
                        let predicted = plane.a * Double(cell.x) + plane.b * Double(cell.y) + plane.c
                        let delta = abs(predicted - z)
                        if delta < error {
                            error = delta
                            best = plane
                        }
                    }
                    assigned[cell] = best.a * Double(cell.x) + best.b * Double(cell.y) + best.c
                }
            }
        }
        return assigned
    }

    /// Remove one-cell whiskers left by the scanner.
    private static func trimSpurs(_ grid: [CellKey: Double]) -> [CellKey: Double] {
        let orthogonal = [(1, 0), (-1, 0), (0, 1), (0, -1)]
        var next: [CellKey: Double] = [:]
        for (cell, z) in grid {
            var neighbors = 0
            for step in orthogonal where grid[CellKey(x: cell.x + step.0, y: cell.y + step.1)] != nil {
                neighbors += 1
            }
            if neighbors >= 2 { next[cell] = z }
        }
        return next.isEmpty ? grid : next
    }

    private static func fitPlane(_ samples: [(Double, Double, Double)]) -> (a: Double, b: Double, c: Double, residual: Double)? {
        var count = 0.0
        var sx = 0.0, sy = 0.0, sz = 0.0
        var sxx = 0.0, syy = 0.0, sxy = 0.0, sxz = 0.0, syz = 0.0
        for (x, y, z) in samples {
            count += 1
            sx += x
            sy += y
            sz += z
            sxx += x * x
            syy += y * y
            sxy += x * y
            sxz += x * z
            syz += y * z
        }
        let matrix = [
            [count, sx, sy],
            [sx, sxx, sxy],
            [sy, sxy, syy]
        ]
        guard let solved = solve3(matrix, [sz, sxz, syz]) else { return nil }
        let c = solved[0]
        let a = solved[1]
        let b = solved[2]
        var residual = 0.0
        for (x, y, z) in samples {
            residual = max(residual, abs(a * x + b * y + c - z))
        }
        return (a, b, c, residual)
    }

    private static func solve3(_ matrix: [[Double]], _ rhs: [Double]) -> [Double]? {
        var rows = matrix
        var values = rhs
        for column in 0 ..< 3 {
            var pivot = column
            for row in (column + 1) ..< 3 where abs(rows[row][column]) > abs(rows[pivot][column]) {
                pivot = row
            }
            guard abs(rows[pivot][column]) > 1e-8 else { return nil }
            if pivot != column {
                rows.swapAt(pivot, column)
                values.swapAt(pivot, column)
            }
            let divisor = rows[column][column]
            for index in column ..< 3 { rows[column][index] /= divisor }
            values[column] /= divisor
            for row in 0 ..< 3 where row != column {
                let factor = rows[row][column]
                for index in column ..< 3 {
                    rows[row][index] -= factor * rows[column][index]
                }
                values[row] -= factor * values[column]
            }
        }
        return values
    }

    /// Give the sheet the thickness of a climbing panel so the edge is a wall, not paper.
    private static func thicken(_ mesh: WallMesh, depth: Double) -> WallMesh {
        guard mesh.isEmpty == false else { return mesh }
        let count = mesh.positions.count
        var positions = mesh.positions
        positions.append(contentsOf: mesh.positions.map { MeshPoint(x: $0.x, y: $0.y, z: $0.z - depth) })
        var indices = mesh.indices
        struct EdgeKey: Hashable {
            var a: Int
            var b: Int
            init(_ i: Int, _ j: Int) {
                if i < j { a = i; b = j } else { a = j; b = i }
            }
        }
        var uses: [EdgeKey: Int] = [:]
        var directed: [EdgeKey: (Int, Int)] = [:]
        var index = 0
        while index + 2 < mesh.indices.count {
            let tri = [mesh.indices[index], mesh.indices[index + 1], mesh.indices[index + 2]]
            indices.append(contentsOf: [tri[0] + count, tri[2] + count, tri[1] + count])
            for corner in 0 ..< 3 {
                let from = tri[corner]
                let to = tri[(corner + 1) % 3]
                let key = EdgeKey(from, to)
                uses[key, default: 0] += 1
                directed[key] = (from, to)
            }
            index += 3
        }
        for (key, countUses) in uses where countUses == 1 {
            guard let (from, to) = directed[key] else { continue }
            indices.append(contentsOf: [from, to, to + count, from, to + count, from + count])
        }
        return WallMesh(positions: positions, indices: indices)
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

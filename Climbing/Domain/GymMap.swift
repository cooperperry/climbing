import Foundation

/// One labeled spot on a gym floor plan, in 0...1 coordinates so pins stay
/// put if the photo is a different size later.
public struct GymMapPin: Equatable, Sendable, Identifiable {
    public var id: String
    public var name: String
    public var x: Double
    public var y: Double

    public init(id: String = UUID().uuidString, name: String, x: Double, y: Double) {
        self.id = id
        self.name = name
        let clamped = GymJoinMath.clampPin(x: x, y: y)
        self.x = clamped.x
        self.y = clamped.y
    }
}

public enum GymJoinMath {
    public static func normalizedName(_ name: String) -> String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let collapsed = trimmed.replacingOccurrences(
            of: "\\s+",
            with: " ",
            options: .regularExpression
        )
        return collapsed.lowercased()
    }

    public static func namesMatch(_ a: String, _ b: String) -> Bool {
        let left = normalizedName(a)
        let right = normalizedName(b)
        guard left.isEmpty == false, right.isEmpty == false else { return false }
        return left == right
    }

    /// Six-character code a climber can type to find a gym already on this phone.
    public static func joinCode(from uuid: UUID = UUID()) -> String {
        let hex = uuid.uuidString.replacingOccurrences(of: "-", with: "")
        return String(hex.prefix(6)).uppercased()
    }

    public static func codesMatch(_ a: String, _ b: String) -> Bool {
        let left = a.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        let right = b.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard left.count == 6, right.count == 6 else { return false }
        return left == right
    }

    public static func clampPin(x: Double, y: Double) -> (x: Double, y: Double) {
        (min(1, max(0, x)), min(1, max(0, y)))
    }

    public static func isUsableName(_ name: String) -> Bool {
        normalizedName(name).count >= 2
    }

    /// Place the next wall card in a left-to-right grid so a gym can be mapped
    /// without a floor-plan photo.
    public static func nextGridSlot(existingCount: Int, columns: Int = 3) -> (x: Double, y: Double) {
        let cols = max(1, columns)
        let col = existingCount % cols
        let row = existingCount / cols
        let x = (Double(col) + 0.5) / Double(cols)
        let y = min(0.92, 0.18 + Double(row) * 0.22)
        return clampPin(x: x, y: y)
    }
}

public struct PlanPoint: Codable, Equatable, Sendable {
    public var x: Double
    public var y: Double

    public init(x: Double, y: Double) {
        let clamped = GymJoinMath.clampPin(x: x, y: y)
        self.x = clamped.x
        self.y = clamped.y
    }
}

public enum FloorPlanMath {
    /// A short horizontal segment centered on the wall label anchor.
    public static func defaultSegment(anchor: PlanPoint, halfWidth: Double = 0.12) -> [PlanPoint] {
        [
            PlanPoint(x: anchor.x - halfWidth, y: anchor.y),
            PlanPoint(x: anchor.x + halfWidth, y: anchor.y),
        ]
    }

    public static func centroid(of points: [PlanPoint]) -> PlanPoint {
        guard points.isEmpty == false else { return PlanPoint(x: 0.5, y: 0.5) }
        let sumX = points.reduce(0.0) { $0 + $1.x }
        let sumY = points.reduce(0.0) { $0 + $1.y }
        let n = Double(points.count)
        return PlanPoint(x: sumX / n, y: sumY / n)
    }

    public static func translate(points: [PlanPoint], dx: Double, dy: Double) -> [PlanPoint] {
        points.map { PlanPoint(x: $0.x + dx, y: $0.y + dy) }
    }

    /// Append a point one step beyond the last segment (extend the wall line).
    public static func extendedPoint(after points: [PlanPoint], step: Double = 0.08) -> PlanPoint {
        guard points.count >= 2 else {
            let anchor = points.first ?? PlanPoint(x: 0.5, y: 0.5)
            return PlanPoint(x: anchor.x + step, y: anchor.y)
        }
        let last = points[points.count - 1]
        let prev = points[points.count - 2]
        let dx = last.x - prev.x
        let dy = last.y - prev.y
        let len = hypot(dx, dy)
        guard len > 1e-6 else {
            return PlanPoint(x: last.x + step, y: last.y)
        }
        return PlanPoint(x: last.x + dx / len * step, y: last.y + dy / len * step)
    }

    public static func encode(_ points: [PlanPoint]) -> Data? {
        guard points.isEmpty == false else { return nil }
        return try? JSONEncoder().encode(points)
    }

    public static func decode(_ data: Data?) -> [PlanPoint] {
        guard let data, data.isEmpty == false else { return [] }
        return (try? JSONDecoder().decode([PlanPoint].self, from: data)) ?? []
    }

    /// Squared distance from `p` to the segment `a`–`b`, in normalized board space.
    public static func distanceSquared(from p: PlanPoint, toSegmentFrom a: PlanPoint, to b: PlanPoint) -> Double {
        let abx = b.x - a.x
        let aby = b.y - a.y
        let apx = p.x - a.x
        let apy = p.y - a.y
        let abLenSq = abx * abx + aby * aby
        let t: Double
        if abLenSq <= 1e-12 {
            t = 0
        } else {
            t = min(1, max(0, (apx * abx + apy * aby) / abLenSq))
        }
        let cx = a.x + t * abx
        let cy = a.y + t * aby
        let dx = p.x - cx
        let dy = p.y - cy
        return dx * dx + dy * dy
    }

    public static func nearestSegmentIndex(in points: [PlanPoint], to p: PlanPoint) -> Int? {
        guard points.count >= 2 else { return nil }
        var bestIndex: Int?
        var bestDist = Double.greatestFiniteMagnitude
        for i in 0 ..< (points.count - 1) {
            let d = distanceSquared(from: p, toSegmentFrom: points[i], to: points[i + 1])
            if d < bestDist {
                bestDist = d
                bestIndex = i
            }
        }
        return bestIndex
    }

    /// Axis-aligned square centered on `center` with side length `size`.
    public static func square(center: PlanPoint, size: Double = 0.18) -> [PlanPoint] {
        let half = size / 2
        return [
            PlanPoint(x: center.x - half, y: center.y - half),
            PlanPoint(x: center.x + half, y: center.y - half),
            PlanPoint(x: center.x + half, y: center.y + half),
            PlanPoint(x: center.x - half, y: center.y + half),
        ]
    }

    /// Closest point on the segment `a`–`b` to `p`.
    public static func project(p: PlanPoint, ontoSegmentFrom a: PlanPoint, to b: PlanPoint) -> PlanPoint {
        let abx = b.x - a.x
        let aby = b.y - a.y
        let apx = p.x - a.x
        let apy = p.y - a.y
        let abLenSq = abx * abx + aby * aby
        let t: Double
        if abLenSq <= 1e-12 {
            t = 0
        } else {
            t = min(1, max(0, (apx * abx + apy * aby) / abLenSq))
        }
        return PlanPoint(x: a.x + t * abx, y: a.y + t * aby)
    }

    /// Insert a vertex on the nearest edge to `p`. Returns nil if too far or not enough points.
    public static func insertingVertex(in points: [PlanPoint], at p: PlanPoint, maxDistance: Double = 0.06) -> [PlanPoint]? {
        guard let index = nearestSegmentIndex(in: points, to: p), index < points.count - 1 else { return nil }
        let a = points[index]
        let b = points[index + 1]
        let projected = project(p: p, ontoSegmentFrom: a, to: b)
        let dist = hypot(p.x - projected.x, p.y - projected.y)
        guard dist <= maxDistance else { return nil }
        var next = points
        next.insert(projected, at: index + 1)
        return next
    }

    /// Split an open polyline at the nearest edge to `p` into two polylines.
    public static func split(points: [PlanPoint], at p: PlanPoint, maxDistance: Double = 0.06) -> (left: [PlanPoint], right: [PlanPoint])? {
        guard points.count >= 2, let index = nearestSegmentIndex(in: points, to: p) else { return nil }
        let a = points[index]
        let b = points[index + 1]
        let mid = project(p: p, ontoSegmentFrom: a, to: b)
        let dist = hypot(p.x - mid.x, p.y - mid.y)
        guard dist <= maxDistance else { return nil }
        let left = Array(points[0 ... index]) + [mid]
        let right = [mid] + Array(points[(index + 1)...])
        guard left.count >= 2, right.count >= 2 else { return nil }
        return (left, right)
    }
}

import Foundation

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
}

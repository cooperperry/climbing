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

    /// Unclamped point for chrome (extend handles may sit slightly off-board).
    public init(rawX: Double, rawY: Double) {
        self.x = rawX
        self.y = rawY
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
            return PlanPoint(rawX: anchor.x + step, rawY: anchor.y)
        }
        let last = points[points.count - 1]
        let prev = points[points.count - 2]
        let dx = last.x - prev.x
        let dy = last.y - prev.y
        let len = hypot(dx, dy)
        guard len > 1e-6 else {
            return PlanPoint(rawX: last.x + step, rawY: last.y)
        }
        return PlanPoint(rawX: last.x + dx / len * step, rawY: last.y + dy / len * step)
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

    /// Number of drawable edges in a polyline / polygon.
    public static func segmentCount(points: [PlanPoint], closed: Bool) -> Int {
        guard points.count >= 2 else { return 0 }
        return closed ? points.count : points.count - 1
    }

    public static func segmentEndpoints(
        points: [PlanPoint],
        closed: Bool,
        index: Int
    ) -> (PlanPoint, PlanPoint)? {
        let count = segmentCount(points: points, closed: closed)
        guard index >= 0, index < count else { return nil }
        if closed {
            return (points[index], points[(index + 1) % points.count])
        }
        return (points[index], points[index + 1])
    }

    public static func midpoint(of points: [PlanPoint], closed: Bool, segment index: Int) -> PlanPoint? {
        guard let (a, b) = segmentEndpoints(points: points, closed: closed, index: index) else { return nil }
        return PlanPoint(x: (a.x + b.x) / 2, y: (a.y + b.y) / 2)
    }

    public static func nearestSegmentIndex(
        in points: [PlanPoint],
        closed: Bool = false,
        to p: PlanPoint
    ) -> Int? {
        let count = segmentCount(points: points, closed: closed)
        guard count > 0 else { return nil }
        var bestIndex: Int?
        var bestDist = Double.greatestFiniteMagnitude
        for i in 0 ..< count {
            guard let (a, b) = segmentEndpoints(points: points, closed: closed, index: i) else { continue }
            let d = distanceSquared(from: p, toSegmentFrom: a, to: b)
            if d < bestDist {
                bestDist = d
                bestIndex = i
            }
        }
        return bestIndex
    }

    /// Result of deleting one edge from a wall outline.
    public enum SegmentRemoval: Equatable, Sendable {
        /// Nothing left — delete the wall.
        case empty
        /// One remaining outline (possibly opened if it was closed).
        case single(points: [PlanPoint], closed: Bool)
        /// Open polyline split into two walls.
        case split(left: [PlanPoint], right: [PlanPoint])
    }

    /// Delete the edge at `index`. Closed shapes open at the cut; open lines shorten or split.
    public static func removingSegment(
        at index: Int,
        from points: [PlanPoint],
        closed: Bool
    ) -> SegmentRemoval {
        let count = segmentCount(points: points, closed: closed)
        guard points.count >= 2, index >= 0, index < count else {
            return .single(points: points, closed: closed)
        }

        if closed {
            let n = points.count
            var opened: [PlanPoint] = []
            let start = (index + 1) % n
            for offset in 0 ..< n {
                opened.append(points[(start + offset) % n])
            }
            return .single(points: opened, closed: false)
        }

        if points.count == 2 {
            return .empty
        }
        if index == 0 {
            let rest = Array(points.dropFirst())
            return rest.count >= 2 ? .single(points: rest, closed: false) : .empty
        }
        if index == points.count - 2 {
            let rest = Array(points.dropLast())
            return rest.count >= 2 ? .single(points: rest, closed: false) : .empty
        }
        let left = Array(points[0 ... index])
        let right = Array(points[(index + 1)...])
        if left.count >= 2, right.count >= 2 {
            return .split(left: left, right: right)
        }
        if left.count >= 2 { return .single(points: left, closed: false) }
        if right.count >= 2 { return .single(points: right, closed: false) }
        return .empty
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

    /// Axis-aligned rectangle from one corner drag to the opposite corner.
    public static func rectangle(from a: PlanPoint, to b: PlanPoint) -> [PlanPoint] {
        let minX = min(a.x, b.x)
        let maxX = max(a.x, b.x)
        let minY = min(a.y, b.y)
        let maxY = max(a.y, b.y)
        return [
            PlanPoint(x: minX, y: minY),
            PlanPoint(x: maxX, y: minY),
            PlanPoint(x: maxX, y: maxY),
            PlanPoint(x: minX, y: maxY),
        ]
    }

    public static func distance(_ a: PlanPoint, _ b: PlanPoint) -> Double {
        hypot(a.x - b.x, a.y - b.y)
    }

    /// Tip beyond the last vertex — offset matches the length of the last segment.
    public static func addSegmentHandle(after points: [PlanPoint], step: Double? = nil) -> PlanPoint {
        let fallback = 0.12
        guard points.count >= 2 else {
            return extendedPoint(after: points, step: step ?? fallback)
        }
        let last = points[points.count - 1]
        let prev = points[points.count - 2]
        let length = max(distance(prev, last), 0.04)
        return extendedPoint(after: points, step: step ?? length)
    }

    /// Tip beyond the first vertex — offset matches the length of the first segment.
    public static func addSegmentHandle(before points: [PlanPoint], step: Double? = nil) -> PlanPoint {
        let fallback = 0.12
        guard points.count >= 2 else {
            let anchor = points.first ?? PlanPoint(x: 0.5, y: 0.5)
            let use = step ?? fallback
            return PlanPoint(rawX: anchor.x - use, rawY: anchor.y)
        }
        let first = points[0]
        let next = points[1]
        let length = max(distance(first, next), 0.04)
        let use = step ?? length
        let dx = first.x - next.x
        let dy = first.y - next.y
        let len = hypot(dx, dy)
        guard len > 1e-6 else {
            return PlanPoint(rawX: first.x - use, rawY: first.y)
        }
        return PlanPoint(rawX: first.x + dx / len * use, rawY: first.y + dy / len * use)
    }

    /// Trash / chrome offset above the shape centroid in board space.
    public static func chromeAnchor(for points: [PlanPoint]) -> PlanPoint {
        let c = centroid(of: points)
        return PlanPoint(x: c.x, y: max(0.04, c.y - 0.07))
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
    public static func insertingVertex(
        in points: [PlanPoint],
        closed: Bool = false,
        at p: PlanPoint,
        maxDistance: Double = 0.06
    ) -> [PlanPoint]? {
        guard let index = nearestSegmentIndex(in: points, closed: closed, to: p) else { return nil }
        guard let (a, b) = segmentEndpoints(points: points, closed: closed, index: index) else { return nil }
        let projected = project(p: p, ontoSegmentFrom: a, to: b)
        let dist = hypot(p.x - projected.x, p.y - projected.y)
        guard dist <= maxDistance else { return nil }
        if closed {
            var next = points
            next.insert(projected, at: index + 1)
            return next
        }
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

    /// Minimum drag length in board space before a stroke becomes a wall.
    public static let minimumStroke: Double = 0.04

    public static func isUsableStroke(from a: PlanPoint, to b: PlanPoint) -> Bool {
        distance(a, b) >= minimumStroke
    }

    public static func isUsableRectangle(_ points: [PlanPoint]) -> Bool {
        guard points.count == 4 else { return false }
        let width = distance(points[0], points[1])
        let height = distance(points[0], points[3])
        return width >= minimumStroke && height >= minimumStroke
    }

    /// Empty names are allowed; blank strings normalize to "".
    public static func optionalWallName(_ raw: String) -> String {
        raw.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Label for UI / Watch when the climber has not named the wall yet.
    public static func displayWallName(_ raw: String) -> String {
        let name = optionalWallName(raw)
        return name.isEmpty ? "Untitled" : name
    }

    /// Snap-close radius when finishing a polygon near its start.
    public static let closeSnapDistance: Double = 0.055

    public static func shouldClosePolygon(draft: [PlanPoint], to end: PlanPoint) -> Bool {
        guard draft.count >= 2, let first = draft.first else { return false }
        return distance(end, first) < closeSnapDistance
    }

    /// Point at fraction `t` (0...1) along an open or closed outline.
    public static func pointAlong(points: [PlanPoint], closed: Bool, t: Double) -> PlanPoint {
        let count = segmentCount(points: points, closed: closed)
        guard count > 0, let first = points.first else {
            return PlanPoint(x: 0.5, y: 0.5)
        }
        var lengths: [Double] = []
        var total = 0.0
        for i in 0 ..< count {
            guard let (a, b) = segmentEndpoints(points: points, closed: closed, index: i) else { continue }
            let len = distance(a, b)
            lengths.append(len)
            total += len
        }
        guard total > 1e-9 else { return first }
        var target = min(1, max(0, t)) * total
        for i in 0 ..< lengths.count {
            let len = lengths[i]
            if target <= len || i == lengths.count - 1 {
                guard let (a, b) = segmentEndpoints(points: points, closed: closed, index: i) else { return first }
                let u = len > 1e-9 ? target / len : 0
                return PlanPoint(x: a.x + (b.x - a.x) * u, y: a.y + (b.y - a.y) * u)
            }
            target -= len
        }
        return first
    }

    /// Evenly space `count` markers along the outline (for route dots on the floor plan).
    public static func routeSlots(count: Int, on points: [PlanPoint], closed: Bool) -> [PlanPoint] {
        guard count > 0 else { return [] }
        if count == 1 {
            return [pointAlong(points: points, closed: closed, t: 0.5)]
        }
        if closed {
            // Closed walls form a ring — space evenly around the full loop.
            return (0 ..< count).map { index in
                let t = Double(index) / Double(count)
                return pointAlong(points: points, closed: true, t: t)
            }
        }
        return (0 ..< count).map { index in
            let t = Double(index) / Double(count - 1)
            return pointAlong(points: points, closed: false, t: t)
        }
    }

    /// Route pins slightly off the stroke so they don't sit under extend/trash chrome.
    public static func routeSlotsClearOfStroke(
        count: Int,
        on points: [PlanPoint],
        closed: Bool,
        offset: Double = 0.032
    ) -> [PlanPoint] {
        let slots = routeSlots(count: count, on: points, closed: closed)
        guard slots.isEmpty == false else { return [] }
        let center = centroid(of: points)
        return slots.map { slot in
            let dx = slot.x - center.x
            let dy = slot.y - center.y
            let len = hypot(dx, dy)
            if len > 1e-6 {
                // Push outward from the shape center so tags sit outside the wall line.
                let scale = (len + offset) / len
                return PlanPoint(x: center.x + dx * scale, y: center.y + dy * scale)
            }
            // Degenerate (line through center): nudge "up" on the board.
            return PlanPoint(x: slot.x, y: max(0, slot.y - offset))
        }
    }

    /// Evenly space markers on a circle (grouped routes that fill a ring as count grows).
    public static func circleSlots(
        count: Int,
        center: PlanPoint,
        radius: Double,
        startAngle: Double = -.pi / 2
    ) -> [PlanPoint] {
        guard count > 0 else { return [] }
        if count == 1 {
            return [PlanPoint(x: center.x, y: max(0, min(1, center.y - radius)))]
        }
        let r = max(radius, 0.02)
        return (0 ..< count).map { index in
            let angle = startAngle + (Double.pi * 2) * Double(index) / Double(count)
            return PlanPoint(
                x: center.x + cos(angle) * r,
                y: center.y + sin(angle) * r
            )
        }
    }

    /// Preferred radius so a circle of `count` routes fits just outside a wall outline.
    public static func fittingRadius(around points: [PlanPoint], padding: Double = 0.04) -> Double {
        guard points.isEmpty == false else { return 0.08 }
        let center = centroid(of: points)
        let maxDist = points.map { distance($0, center) }.max() ?? 0.08
        return max(0.06, maxDist + padding)
    }

    /// Lay out routes on a wall: closed shapes → ring; open → along the line, clear of the stroke.
    public static func layoutRoutes(
        count: Int,
        on points: [PlanPoint],
        closed: Bool
    ) -> [PlanPoint] {
        guard count > 0 else { return [] }
        if closed, points.count >= 3 {
            let center = centroid(of: points)
            let radius = fittingRadius(around: points)
            return circleSlots(count: count, center: center, radius: radius)
        }
        return routeSlotsClearOfStroke(count: count, on: points, closed: closed)
    }

    /// Prefer a ring whenever the outline can support one (closed, or open ends nearly touching).
    public static func layoutRoutesMerged(
        count: Int,
        on points: [PlanPoint],
        closed: Bool
    ) -> [PlanPoint] {
        guard count > 0 else { return [] }
        let useRing = closed || shouldCloseOpenShape(points: points) || points.count >= 4
        if useRing, points.count >= 3 {
            let center = centroid(of: points)
            let radius = fittingRadius(around: points)
            return circleSlots(count: count, center: center, radius: radius)
        }
        return layoutRoutes(count: count, on: points, closed: closed)
    }

    /// Combine pin lists from several walls into one evenly spaced ring around their shared center.
    public static func mergeRouteLayout(
        routeCounts: Int,
        wallOutlines: [[PlanPoint]]
    ) -> [PlanPoint] {
        guard routeCounts > 0 else { return [] }
        let allPoints = wallOutlines.flatMap { $0 }
        guard allPoints.isEmpty == false else {
            return circleSlots(count: routeCounts, center: PlanPoint(x: 0.5, y: 0.5), radius: 0.12)
        }
        let center = centroid(of: allPoints)
        let radius = fittingRadius(around: allPoints, padding: 0.05)
        return circleSlots(count: routeCounts, center: center, radius: radius)
    }

    /// How close two route pins must be to snap-merge on drag.
    public static let routeMergeDistance: Double = 0.055

    /// Soft magnetic pull while dragging one pin toward another.
    public static func magneticPull(
        from point: PlanPoint,
        toward target: PlanPoint,
        threshold: Double = routeMergeDistance
    ) -> PlanPoint {
        let d = distance(point, target)
        guard d > 1e-9, d < threshold else { return point }
        let strength = 1 - (d / threshold)
        let t = min(1, strength * 0.55)
        return PlanPoint(
            x: point.x + (target.x - point.x) * t,
            y: point.y + (target.y - point.y) * t
        )
    }

    /// Circle layout for a drag-merged cluster around the drop point.
    public static func dragMergedCircle(
        count: Int,
        around center: PlanPoint,
        existing: [PlanPoint]
    ) -> [PlanPoint] {
        dragMergedSemiCircle(count: count, around: center, existing: existing)
    }

    /// Upper semi-circle of map pins (screen y-down: arc goes left → up → right).
    /// Sweep is slightly inset from a flat diameter so a 2-pin merge still fans upward.
    public static func semiCircleSlots(
        count: Int,
        center: PlanPoint,
        radius: Double,
        startAngle: Double = .pi + 0.4,
        sweep: Double = .pi - 0.8
    ) -> [PlanPoint] {
        guard count > 0 else { return [] }
        let r = max(radius, 0.03)
        if count == 1 {
            let angle = startAngle + sweep / 2
            return [PlanPoint(x: center.x + cos(angle) * r, y: center.y + sin(angle) * r)]
        }
        return (0 ..< count).map { index in
            let t = Double(index) / Double(count - 1)
            let angle = startAngle + sweep * t
            return PlanPoint(
                x: center.x + cos(angle) * r,
                y: center.y + sin(angle) * r
            )
        }
    }

    /// Semi-circle cluster used when two route pins snap together.
    public static func dragMergedSemiCircle(
        count: Int,
        around center: PlanPoint,
        existing: [PlanPoint]
    ) -> [PlanPoint] {
        guard count > 0 else { return [] }
        let radius: Double
        if existing.count >= 2 {
            let mean = existing.map { distance($0, center) }.reduce(0, +) / Double(existing.count)
            radius = max(0.04, mean)
        } else {
            radius = max(0.048, 0.032 + Double(count) * 0.014)
        }
        return semiCircleSlots(count: count, center: center, radius: radius)
    }

    /// Lay out `count` points in a circle using existing pins for center/radius when possible.
    public static func circleLayout(
        existing: [PlanPoint],
        count: Int,
        fallbackCenter: PlanPoint,
        fallbackRadius: Double = 0.08
    ) -> [PlanPoint] {
        guard count > 0 else { return [] }
        let center: PlanPoint
        let radius: Double
        if existing.isEmpty == false {
            center = centroid(of: existing)
            let mean = existing.map { distance($0, center) }.reduce(0, +) / Double(existing.count)
            radius = max(fallbackRadius, mean)
        } else {
            center = fallbackCenter
            radius = fallbackRadius
        }
        return circleSlots(count: count, center: center, radius: radius)
    }

    /// Distance under which open endpoints snap / link / close.
    public static let joinSnapDistance: Double = 0.045

    /// True when an open polyline's ends are close enough to become a closed shape.
    public static func shouldCloseOpenShape(points: [PlanPoint]) -> Bool {
        guard points.count >= 3, let first = points.first, let last = points.last else { return false }
        return distance(first, last) < joinSnapDistance
    }

    /// Merge two open polylines when any pair of endpoints is within `threshold`.
    /// Returns nil when they do not touch.
    public static func joinOpenPolylines(
        _ a: [PlanPoint],
        _ b: [PlanPoint],
        threshold: Double = joinSnapDistance
    ) -> [PlanPoint]? {
        guard a.count >= 2, b.count >= 2,
              let aStart = a.first, let aEnd = a.last,
              let bStart = b.first, let bEnd = b.last else { return nil }

        if distance(aEnd, bStart) < threshold {
            return a + Array(b.dropFirst())
        }
        if distance(aEnd, bEnd) < threshold {
            return a + Array(b.reversed().dropFirst())
        }
        if distance(aStart, bEnd) < threshold {
            return b + Array(a.dropFirst())
        }
        if distance(aStart, bStart) < threshold {
            return b.reversed() + Array(a.dropFirst())
        }
        return nil
    }

    /// Endpoints of an open shape, for link / snap chrome.
    public static func openEndpoints(_ points: [PlanPoint]) -> [PlanPoint] {
        guard points.count >= 2, let first = points.first, let last = points.last else { return [] }
        return [first, last]
    }

    // MARK: - Snap / grid (big-gym editing)

    public static let gridStep: Double = 0.05

    public static func snapToGrid(_ point: PlanPoint, step: Double = gridStep) -> PlanPoint {
        let s = max(step, 1e-6)
        return PlanPoint(
            x: (point.x / s).rounded() * s,
            y: (point.y / s).rounded() * s
        )
    }

    /// Snap the free end of a stroke to 0/45/90° relative to `origin`.
    public static func snapAngle(from origin: PlanPoint, to point: PlanPoint) -> PlanPoint {
        let dx = point.x - origin.x
        let dy = point.y - origin.y
        let len = hypot(dx, dy)
        guard len > 1e-6 else { return point }
        let angle = atan2(dy, dx)
        let step = Double.pi / 4
        let snapped = (angle / step).rounded() * step
        return PlanPoint(x: origin.x + cos(snapped) * len, y: origin.y + sin(snapped) * len)
    }

    public static func snapToNearby(
        _ point: PlanPoint,
        candidates: [PlanPoint],
        threshold: Double = 0.035
    ) -> PlanPoint {
        var best = point
        var bestDist = threshold
        for candidate in candidates {
            let d = distance(point, candidate)
            if d < bestDist {
                bestDist = d
                best = candidate
            }
        }
        return best
    }

    public static func applySnaps(
        _ point: PlanPoint,
        origin: PlanPoint?,
        otherPoints: [PlanPoint],
        grid: Bool,
        angle: Bool,
        vertices: Bool
    ) -> PlanPoint {
        var result = point
        if angle, let origin {
            result = snapAngle(from: origin, to: result)
        }
        if grid {
            result = snapToGrid(result)
        }
        if vertices {
            result = snapToNearby(result, candidates: otherPoints)
        }
        return result
    }

    public static func defaultFloorName(_ raw: String?) -> String {
        let name = optionalWallName(raw ?? "")
        return name.isEmpty ? "Main" : name
    }

    public static func defaultZoneName(_ raw: String?) -> String {
        let name = optionalWallName(raw ?? "")
        return name.isEmpty ? "General" : name
    }
}

/// Pre-built outlines for common gym map chunks.
public enum FloorPlanTemplates {
    public struct WallSpec: Equatable, Sendable {
        public var name: String
        public var points: [PlanPoint]
        public var closed: Bool
        public var zone: String
        public var floor: String

        public init(name: String, points: [PlanPoint], closed: Bool, zone: String, floor: String = "Main") {
            self.name = name
            self.points = points
            self.closed = closed
            self.zone = zone
            self.floor = floor
        }
    }

    /// Six open arcs around a center — chalkboard-style 360 A–F.
    public static func ring360(center: PlanPoint = PlanPoint(x: 0.5, y: 0.5), radius: Double = 0.22) -> [WallSpec] {
        let labels = ["360 A", "360 B", "360 C", "360 D", "360 E", "360 F"]
        return labels.enumerated().map { index, name in
            let start = Double(index) * (.pi * 2 / 6) - .pi / 2
            let end = start + (.pi * 2 / 6) * 0.85
            let a = PlanPoint(x: center.x + cos(start) * radius, y: center.y + sin(start) * radius)
            let midAngle = (start + end) / 2
            let b = PlanPoint(x: center.x + cos(midAngle) * radius, y: center.y + sin(midAngle) * radius)
            let c = PlanPoint(x: center.x + cos(end) * radius, y: center.y + sin(end) * radius)
            return WallSpec(name: name, points: [a, b, c], closed: false, zone: "360")
        }
    }

    public static func caveBox(center: PlanPoint = PlanPoint(x: 0.22, y: 0.55)) -> WallSpec {
        WallSpec(
            name: "Cave",
            points: FloorPlanMath.square(center: center, size: 0.2),
            closed: true,
            zone: "Cave"
        )
    }

    public static func duplicated(
        points: [PlanPoint],
        closed: Bool,
        dx: Double = 0.08,
        dy: Double = 0.08
    ) -> (points: [PlanPoint], closed: Bool) {
        (FloorPlanMath.translate(points: points, dx: dx, dy: dy), closed)
    }
}

import SwiftUI

/// One wall, fitted to the watch. Other walls stay off this screen.
struct WatchGymMap: View {
    var wall: WatchWall
    var highlightedID: String?
    var onSelect: (WatchRoutePin) -> Void = { _ in }

    var body: some View {
        GeometryReader { geo in
            let project = projector(in: geo.size)
            ZStack {
                Color.white.opacity(0.06)
                wallPath(project: project)
                    .stroke(
                        Color.white.opacity(0.9),
                        style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round)
                    )
                ForEach(placedPins(project: project)) { placed in
                    Text(placed.pin.grade)
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(placed.pin.holdColor.prefersDarkLabel ? Color.black : Color.white)
                        .frame(width: 40, height: 40)
                        .background(Color(hold: placed.pin.holdColor), in: Circle())
                        .overlay { Circle().strokeBorder(Color.white, lineWidth: 3) }
                        .position(placed.point)
                }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private func wallPath(project: (Double, Double) -> CGPoint) -> Path {
        Path { path in
            guard let first = wall.outline.first else { return }
            path.move(to: project(first.x, first.y))
            for point in wall.outline.dropFirst() {
                path.addLine(to: project(point.x, point.y))
            }
            if wall.closed {
                path.closeSubpath()
            }
        }
    }

    /// Fit the whole wall. Its shape is the landmark; other routes are left off
    /// because a stale set would point at the wrong place.
    private func projector(in size: CGSize) -> (Double, Double) -> CGPoint {
        var anchorsX = wall.outline.map(\.x)
        var anchorsY = wall.outline.map(\.y)
        if let pin = selectedPin {
            anchorsX.append(pin.x)
            anchorsY.append(pin.y)
        }
        let minX = anchorsX.min() ?? 0
        let maxX = anchorsX.max() ?? 1
        let minY = anchorsY.min() ?? 0
        let maxY = anchorsY.max() ?? 1
        let spanX = max(maxX - minX, 0.08)
        let spanY = max(maxY - minY, 0.08)
        let scale = min(
            (Double(size.width) - 36) / spanX,
            (Double(size.height) - 56) / spanY
        )
        let originX = (Double(size.width) - spanX * scale) / 2
        let originY = (Double(size.height) - 40 - spanY * scale) / 2
        return { x, y in
            CGPoint(
                x: originX + (x - minX) * scale,
                y: originY + (y - minY) * scale
            )
        }
    }

    private var selectedPin: WatchRoutePin? {
        wall.routes.first { $0.id == highlightedID }
    }

    private func placedPins(project: (Double, Double) -> CGPoint) -> [PlacedWatchPin] {
        guard let pin = selectedPin else { return [] }
        return [PlacedWatchPin(pin: pin, point: project(pin.x, pin.y), prominent: true)]
    }

    /// Where the pin sits along the wall, in the same left-to-right sense as the phone map.
    var placeCue: String {
        guard let pin = selectedPin else { return "Match this shape to where you're standing." }
        let xs = wall.outline.map(\.x)
        guard let minX = xs.min(), let maxX = xs.max(), maxX - minX > 0.04 else {
            return "Match this shape to where you're standing."
        }
        let t = (pin.x - minX) / (maxX - minX)
        if t < 0.34 { return "Left side of this shape" }
        if t > 0.66 { return "Right side of this shape" }
        return "Middle of this shape"
    }
}

private struct PlacedWatchPin: Identifiable {
    var pin: WatchRoutePin
    var point: CGPoint
    var prominent: Bool
    var id: String { pin.id }
}

struct WatchBoulderRow: Identifiable {
    var wall: WatchWall
    var pin: WatchRoutePin
    var id: String { pin.id }
}

struct WatchBoulderDetail: View {
    var wall: WatchWall
    var pin: WatchRoutePin
    var manager: WorkoutManager
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack(alignment: .bottom) {
            WatchGymMap(wall: wall, highlightedID: pin.id)
                .allowsHitTesting(false)
            VStack(spacing: 3) {
                Text(WatchGymMap(wall: wall, highlightedID: pin.id).placeCue)
                    .font(.caption2.bold())
                    .lineLimit(1)
                HStack(spacing: 6) {
                    logButton("Flashed", color: .yellow) {
                        manager.selectLogWall(wall.name)
                        manager.logRoute(pin, outcome: .flash)
                        dismiss()
                    }
                    logButton("Topped", color: .green) {
                        manager.selectLogWall(wall.name)
                        manager.logRoute(pin, outcome: .send)
                        dismiss()
                    }
                }
            }
            .padding(.horizontal, 4)
            .padding(.vertical, 4)
            .background(.black.opacity(0.55), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .navigationTitle(pin.label)
        .navigationBarTitleDisplayMode(.inline)
    }

    private func logButton(_ title: String, color: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.caption.bold())
                .foregroundStyle(.black)
                .frame(maxWidth: .infinity, minHeight: 26)
                .background(color, in: Capsule())
        }
        .buttonStyle(.plain)
    }
}

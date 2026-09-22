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
                    if placed.prominent {
                        Text(placed.pin.grade)
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(placed.pin.holdColor.prefersDarkLabel ? Color.black : Color.white)
                            .frame(width: 36, height: 36)
                            .background(Color(hold: placed.pin.holdColor), in: Circle())
                            .overlay { Circle().strokeBorder(Color.white, lineWidth: 3) }
                            .position(placed.point)
                    } else {
                        Circle()
                            .fill(Color(hold: placed.pin.holdColor).opacity(0.28))
                            .frame(width: 6, height: 6)
                            .position(placed.point)
                    }
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

    /// Fit this wall's outline and its routes into the watch, then nudge stacked grades apart.
    private func projector(in size: CGSize) -> (Double, Double) -> CGPoint {
        var anchorsX: [Double]
        var anchorsY: [Double]
        if wall.outline.count >= 2 {
            anchorsX = wall.outline.map(\.x)
            anchorsY = wall.outline.map(\.y)
        } else {
            anchorsX = wall.routes.map(\.x)
            anchorsY = wall.routes.map(\.y)
        }
        if let highlightedID, let pin = wall.routes.first(where: { $0.id == highlightedID }) {
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
            (Double(size.width) - 12) / spanX,
            (Double(size.height) - 12) / spanY
        )
        let originX = (Double(size.width) - spanX * scale) / 2
        let originY = (Double(size.height) - spanY * scale) / 2
        return { x, y in
            CGPoint(
                x: originX + (x - minX) * scale,
                y: originY + (y - minY) * scale
            )
        }
    }

    private func placedPins(project: (Double, Double) -> CGPoint) -> [PlacedWatchPin] {
        guard let highlightedID, let selected = wall.routes.first(where: { $0.id == highlightedID }) else {
            return wall.routes.map { pin in
                PlacedWatchPin(pin: pin, point: project(pin.x, pin.y), prominent: true)
            }
        }
        var placed = [
            PlacedWatchPin(pin: selected, point: project(selected.x, selected.y), prominent: true)
        ]
        for pin in wall.routes where pin.id != selected.id {
            placed.append(PlacedWatchPin(pin: pin, point: project(pin.x, pin.y), prominent: false))
        }
        return placed
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
                Text(wallLabel)
                    .font(.caption2.bold())
                    .foregroundStyle(wall.name == "Untitled" ? Color.orange : Color.white)
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

    private var wallLabel: String {
        wall.name == "Untitled" ? "Unnamed wall" : wall.name
    }
}

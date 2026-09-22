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
                ForEach(placedPins(in: geo.size, project: project)) { placed in
                    let selected = highlightedID == placed.pin.id
                    Button {
                        onSelect(placed.pin)
                    } label: {
                        Text(placed.pin.grade)
                            .font(.system(size: selected ? 12 : 10, weight: .bold))
                            .foregroundStyle(placed.pin.holdColor.prefersDarkLabel ? Color.black : Color.white)
                            .frame(minWidth: selected ? 34 : 22, minHeight: selected ? 34 : 22)
                            .background(Color(hold: placed.pin.holdColor), in: Circle())
                            .overlay {
                                if selected {
                                    Circle().strokeBorder(Color.white, lineWidth: 2)
                                }
                            }
                    }
                    .buttonStyle(.plain)
                    .opacity(highlightedID == nil || selected ? 1 : 0.35)
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

    /// Fit this wall's outline and its routes into the watch, then nudge stacked grades apart.
    private func projector(in size: CGSize) -> (Double, Double) -> CGPoint {
        let anchorsX: [Double]
        let anchorsY: [Double]
        if wall.outline.count >= 2 {
            anchorsX = wall.outline.map(\.x)
            anchorsY = wall.outline.map(\.y)
        } else {
            anchorsX = wall.routes.map(\.x)
            anchorsY = wall.routes.map(\.y)
        }
        let minX = anchorsX.min() ?? 0
        let maxX = anchorsX.max() ?? 1
        let minY = anchorsY.min() ?? 0
        let maxY = anchorsY.max() ?? 1
        let spanX = max(maxX - minX, 0.08)
        let spanY = max(maxY - minY, 0.08)
        let scale = min(
            (Double(size.width) - 28) / spanX,
            (Double(size.height) - 28) / spanY
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

    private func placedPins(in size: CGSize, project: (Double, Double) -> CGPoint) -> [PlacedWatchPin] {
        let groups = Dictionary(grouping: wall.routes) { pin in
            "\(Int((pin.x * 1000).rounded())):\(Int((pin.y * 1000).rounded()))"
        }
        var placed: [PlacedWatchPin] = []
        for group in groups.values {
            let sorted = group.sorted { $0.id < $1.id }
            let angles = FloorPlanMath.clusterAngles(count: sorted.count)
            for (index, pin) in sorted.enumerated() {
                let center = project(pin.x, pin.y)
                let angle = angles.indices.contains(index) ? angles[index] : 0
                let radius: CGFloat = sorted.count > 1 ? 16 : 0
                let point = CGPoint(
                    x: min(max(center.x + radius * sin(angle), 16), size.width - 16),
                    y: min(max(center.y - radius * cos(angle), 16), size.height - 16)
                )
                placed.append(PlacedWatchPin(pin: pin, point: point))
            }
        }
        return placed
    }
}

private struct PlacedWatchPin: Identifiable {
    var pin: WatchRoutePin
    var point: CGPoint
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
        VStack(spacing: 4) {
            Text(wall.name)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            WatchGymMap(wall: wall, highlightedID: pin.id)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .allowsHitTesting(false)
            HStack(spacing: 6) {
                Button("Flashed") {
                    manager.selectLogWall(wall.name)
                    manager.logRoute(pin, outcome: .flash)
                    dismiss()
                }
                .tint(.yellow)
                Button("Topped") {
                    manager.selectLogWall(wall.name)
                    manager.logRoute(pin, outcome: .send)
                    dismiss()
                }
                .tint(.green)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
        }
        .navigationTitle(pin.label)
        .navigationBarTitleDisplayMode(.inline)
    }
}

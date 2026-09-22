import SwiftUI

/// Overhead gym map. Tap a route to choose how you finished it.
struct WatchGymMap: View {
    var walls: [WatchWall]
    var onSelect: (WatchRoutePin) -> Void

    var body: some View {
        GeometryReader { geo in
            let size = geo.size
            ZStack {
                Color.white.opacity(0.06)
                ForEach(walls) { wall in
                    wallPath(wall, in: size)
                        .stroke(
                            Color.white.opacity(0.9),
                            style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round)
                        )
                }
                ForEach(placedPins(in: size)) { placed in
                    Button {
                        onSelect(placed.pin)
                    } label: {
                        Text(placed.pin.grade)
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(placed.pin.holdColor.prefersDarkLabel ? Color.black : Color.white)
                            .frame(minWidth: 26, minHeight: 26)
                            .background(Color(hold: placed.pin.holdColor), in: Circle())
                    }
                    .buttonStyle(.plain)
                    .position(x: placed.x * size.width, y: placed.y * size.height)
                }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .accessibilityElement(children: .contain)
    }

    private func wallPath(_ wall: WatchWall, in size: CGSize) -> Path {
        Path { path in
            guard let first = wall.outline.first else { return }
            path.move(to: CGPoint(x: first.x * size.width, y: first.y * size.height))
            for point in wall.outline.dropFirst() {
                path.addLine(to: CGPoint(x: point.x * size.width, y: point.y * size.height))
            }
            if wall.closed {
                path.closeSubpath()
            }
        }
    }

    /// Pins that share a tip fan out so each grade stays tappable.
    private func placedPins(in size: CGSize) -> [PlacedWatchPin] {
        let routes = walls.flatMap(\.routes)
        let groups = Dictionary(grouping: routes) { pin in
            "\(Int((pin.x * 1000).rounded())):\(Int((pin.y * 1000).rounded()))"
        }
        let orbit = min(size.width, size.height) * 0.12
        var placed: [PlacedWatchPin] = []
        for group in groups.values {
            let sorted = group.sorted { $0.id < $1.id }
            let angles = FloorPlanMath.clusterAngles(count: sorted.count)
            for (index, pin) in sorted.enumerated() {
                let angle = angles.indices.contains(index) ? angles[index] : 0
                let radius = sorted.count > 1 ? orbit : 0
                let x = pin.x + Double(radius) * sin(angle) / max(size.width, 1)
                let y = pin.y + Double(-radius) * cos(angle) / max(size.height, 1)
                placed.append(PlacedWatchPin(pin: pin, x: x, y: y))
            }
        }
        return placed
    }
}

private struct PlacedWatchPin: Identifiable {
    var pin: WatchRoutePin
    var x: Double
    var y: Double
    var id: String { pin.id }
}

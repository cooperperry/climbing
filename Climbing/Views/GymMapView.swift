import SwiftUI
import SwiftData

private enum MapMode: String, CaseIterable, Identifiable {
    case select
    case line
    case square
    case polygon

    var id: String { rawValue }

    var title: String {
        switch self {
        case .select: "Select"
        case .line: "Line"
        case .square: "Square"
        case .polygon: "Polygon"
        }
    }

    var systemImage: String {
        switch self {
        case .select: "hand.tap"
        case .line: "line.diagonal"
        case .square: "square"
        case .polygon: "pentagon"
        }
    }
}

/// Overhead floor plan: draw walls as lines, squares, or polygons, then set routes.
struct GymMapView: View {
    @Bindable var gym: ClimbGym
    @Environment(\.modelContext) private var context

    @Query(sort: \CustomGradeScale.createdAt)
    private var scales: [CustomGradeScale]
    @Query(sort: \ClimbGym.joinedAt)
    private var gyms: [ClimbGym]

    @State private var mode: MapMode = .select
    @State private var selectedWall: GymArea?
    @State private var routesWall: GymArea?
    @State private var wallNameDraft = ""
    @State private var namingPending: PendingShape?
    @State private var polygonDraft: [PlanPoint] = []
    @State private var lineStart: PlanPoint?
    @State private var shapeDragOrigin: [PlanPoint]?
    @State private var canvasSize: CGSize = .zero
    @State private var climberName = ClimberIdentity.name
    @State private var logDiscipline: ClimbDiscipline = .boulder
    @State private var logGrade: String?
    @State private var draftColor: HoldColor = .blue

    private struct PendingShape {
        var points: [PlanPoint]
        var closed: Bool
        var suggestedName: String
    }

    private var scale: CustomGradeScale? {
        let kind: GradeScaleKind = logDiscipline.usesRopeGrades ? .yds : .boulderVScale
        return scales.first { $0.kind == kind } ?? scales.first
    }

    private var walls: [GymArea] {
        gym.areas.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    private var trimmedClimberName: String {
        climberName.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var hint: String {
        switch mode {
        case .select:
            if let wall = selectedWall {
                if wall.shapeClosed {
                    return "\(wall.name) — drag corners, or tap an edge to add one."
                }
                return "\(wall.name) — drag corners, tap edge to bend, Extend / Break below."
            }
            return "Tap a wall to select. Tap again for routes."
        case .line:
            return lineStart == nil ? "Tap where the line starts." : "Tap the other end of the line."
        case .square:
            return "Tap the center of a new square wall."
        case .polygon:
            if polygonDraft.isEmpty {
                return "Tap corners to draw a polygon."
            }
            return "Tap to add a corner. Tap Close shape when done."
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            floorPlan
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            VStack(alignment: .leading, spacing: 10) {
                Text(hint)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)

                Picker("Mode", selection: $mode) {
                    ForEach(MapMode.allCases) { item in
                        Label(item.title, systemImage: item.systemImage).tag(item)
                    }
                }
                .pickerStyle(.segmented)
                .onChange(of: mode) { _, newMode in
                    lineStart = nil
                    if newMode != .polygon { polygonDraft = [] }
                    if newMode != .select { selectedWall = nil }
                }

                if mode == .polygon, polygonDraft.isEmpty == false {
                    HStack {
                        Button("Close shape") { finishPolygon() }
                            .buttonStyle(.borderedProminent)
                            .tint(.stravaOrange)
                            .disabled(polygonDraft.count < 3)
                        Button("Cancel", role: .cancel) { polygonDraft = [] }
                    }
                }

                if let wall = selectedWall, mode == .select {
                    selectedWallBar(wall)
                }
            }
            .padding()
            .background(.bar)
        }
        .navigationTitle(gym.name)
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            prepareGrades()
            climberName = ClimberIdentity.name
        }
        .onChange(of: logDiscipline) { _, _ in
            logGrade = scale?.grades.first
        }
        .alert("Name this wall", isPresented: Binding(
            get: { namingPending != nil },
            set: { if $0 == false { namingPending = nil; wallNameDraft = "" } }
        )) {
            TextField("Cave, 360 A, Center…", text: $wallNameDraft)
            Button("Add") { commitPendingWall() }
            Button("Cancel", role: .cancel) {
                namingPending = nil
                wallNameDraft = ""
            }
        } message: {
            Text("Give this section a short name from the gym floor plan.")
        }
        .sheet(item: $routesWall) { area in
            NavigationStack {
                ScrollView {
                    routeList(for: area)
                        .padding()
                }
                .navigationTitle(area.name)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") { routesWall = nil }
                    }
                }
            }
            .presentationDetents([.medium, .large])
        }
    }

    @ViewBuilder
    private func selectedWallBar(_ wall: GymArea) -> some View {
        HStack(spacing: 8) {
            Text(wall.name)
                .font(.subheadline.bold())
                .lineLimit(1)
            Spacer(minLength: 4)
            if wall.shapeClosed == false {
                Button("Extend") { extendLine(wall) }
                    .font(.caption.bold())
                Button("Break") { breakSelectedWall() }
                    .font(.caption.bold())
                    .disabled(wall.floorPlanPoints().count < 2)
            }
            Button("Routes") { openRoutes(for: wall) }
                .font(.caption.bold())
            Button("Delete", role: .destructive) { removeWall(wall) }
                .font(.caption.bold())
        }
        .padding(.top, 2)
    }

    private var floorPlan: some View {
        GeometryReader { geo in
            let size = geo.size
            ZStack {
                Color.black

                if walls.isEmpty && polygonDraft.isEmpty && lineStart == nil {
                    Text("Add a Line, Square, or Polygon\nto map your gym.")
                        .font(.subheadline.bold())
                        .foregroundStyle(.white.opacity(0.7))
                        .multilineTextAlignment(.center)
                }

                ForEach(walls) { wall in
                    shapeLayer(wall, in: size)
                }

                if let start = lineStart {
                    Circle()
                        .fill(Color.stravaOrange)
                        .frame(width: 14, height: 14)
                        .position(pixel(start, in: size))
                }

                if polygonDraft.isEmpty == false {
                    draftPolygon(in: size)
                }

                ForEach(walls) { wall in
                    nameTag(wall, in: size)
                }
            }
            .contentShape(Rectangle())
            .gesture(canvasGesture(in: size))
            .onAppear { canvasSize = size }
            .onChange(of: size.width) { _, _ in canvasSize = size }
            .onChange(of: size.height) { _, _ in canvasSize = size }
            .clipShape(RoundedRectangle(cornerRadius: 0))
        }
    }

    private func draftPolygon(in size: CGSize) -> some View {
        ZStack {
            Path { path in
                guard let first = polygonDraft.first else { return }
                path.move(to: pixel(first, in: size))
                for pt in polygonDraft.dropFirst() {
                    path.addLine(to: pixel(pt, in: size))
                }
            }
            .stroke(Color.stravaOrange, style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))

            ForEach(Array(polygonDraft.enumerated()), id: \.offset) { _, pt in
                Circle()
                    .fill(Color.stravaOrange)
                    .frame(width: 12, height: 12)
                    .position(pixel(pt, in: size))
            }
        }
        .allowsHitTesting(false)
    }

    private func shapeLayer(_ wall: GymArea, in size: CGSize) -> some View {
        let points = wall.floorPlanPoints()
        let focused = selectedWall?.id == wall.id
        let stroke = focused ? Color.stravaOrange : Color.white.opacity(0.9)
        return ZStack {
            Path { path in
                guard let first = points.first else { return }
                path.move(to: pixel(first, in: size))
                for pt in points.dropFirst() {
                    path.addLine(to: pixel(pt, in: size))
                }
                if wall.shapeClosed {
                    path.closeSubpath()
                }
            }
            .stroke(stroke, style: StrokeStyle(lineWidth: focused ? 4 : 2.5, lineCap: .round, lineJoin: .round))

            if focused, mode == .select {
                ForEach(Array(points.enumerated()), id: \.offset) { index, pt in
                    vertexHandle(wall: wall, index: index, point: pt, in: size)
                }
            }
        }
        .allowsHitTesting(false)
    }

    private func nameTag(_ wall: GymArea, in size: CGSize) -> some View {
        let center = FloorPlanMath.centroid(of: wall.floorPlanPoints())
        let focused = selectedWall?.id == wall.id
        return Text(wall.name)
            .font(.caption2.bold())
            .foregroundStyle(focused ? Color.black : Color.white)
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(focused ? Color.stravaOrange : Color.white.opacity(0.18), in: Capsule())
            .position(x: center.x * size.width, y: max(14, center.y * size.height - 18))
            .allowsHitTesting(false)
    }

    private func vertexHandle(wall: GymArea, index: Int, point: PlanPoint, in size: CGSize) -> some View {
        Circle()
            .fill(Color.stravaOrange)
            .frame(width: 20, height: 20)
            .overlay { Circle().strokeBorder(Color.white, lineWidth: 2) }
            .position(pixel(point, in: size))
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        var pts = wall.floorPlanPoints()
                        guard index < pts.count else { return }
                        let board = canvasSize == .zero ? size : canvasSize
                        let clamped = GymJoinMath.clampPin(
                            x: value.location.x / max(board.width, 1),
                            y: value.location.y / max(board.height, 1)
                        )
                        pts[index] = PlanPoint(x: clamped.x, y: clamped.y)
                        wall.setFloorPlanPoints(pts)
                    }
                    .onEnded { _ in persistMap() }
            )
    }

    private func canvasGesture(in size: CGSize) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                guard mode == .select, let wall = selectedWall else { return }
                // Whole-shape drag only when not near a vertex (vertex handles own their drag).
                let point = normalized(value.location, in: size)
                if nearVertex(of: wall, point: point) { return }
                if shapeDragOrigin == nil {
                    shapeDragOrigin = wall.floorPlanPoints()
                }
                guard let origin = shapeDragOrigin else { return }
                let start = normalized(value.startLocation, in: size)
                let dx = point.x - start.x
                let dy = point.y - start.y
                wall.setFloorPlanPoints(FloorPlanMath.translate(points: origin, dx: dx, dy: dy))
            }
            .onEnded { value in
                let moved = hypot(value.translation.width, value.translation.height) >= 10
                let point = normalized(value.location, in: size)
                defer { shapeDragOrigin = nil }

                if moved {
                    if mode == .select, selectedWall != nil {
                        persistMap()
                    }
                    return
                }

                handleTap(at: point)
            }
    }

    private func handleTap(at point: PlanPoint) {
        switch mode {
        case .select:
            if let wall = selectedWall,
               let next = FloorPlanMath.insertingVertex(in: wall.floorPlanPoints(), at: point) {
                // Mid-edge tap on the selected shape inserts a bend / corner.
                wall.setFloorPlanPoints(next)
                persistMap()
                return
            }
            if let hit = hitTest(point) {
                if selectedWall?.id == hit.id {
                    openRoutes(for: hit)
                } else {
                    selectedWall = hit
                    gym.currentWallName = hit.name
                    persistMap()
                }
            } else {
                selectedWall = nil
            }
        case .line:
            if let start = lineStart {
                let points = [start, point]
                lineStart = nil
                namingPending = PendingShape(points: points, closed: false, suggestedName: nextDefaultName(prefix: "Wall"))
                wallNameDraft = namingPending?.suggestedName ?? ""
            } else {
                lineStart = point
            }
        case .square:
            let points = FloorPlanMath.square(center: point)
            namingPending = PendingShape(points: points, closed: true, suggestedName: nextDefaultName(prefix: "Room"))
            wallNameDraft = namingPending?.suggestedName ?? ""
        case .polygon:
            polygonDraft.append(point)
        }
    }

    private func finishPolygon() {
        guard polygonDraft.count >= 3 else { return }
        let points = polygonDraft
        polygonDraft = []
        namingPending = PendingShape(points: points, closed: true, suggestedName: nextDefaultName(prefix: "Zone"))
        wallNameDraft = namingPending?.suggestedName ?? ""
        mode = .select
    }

    private func breakSelectedWall() {
        guard let wall = selectedWall, wall.shapeClosed == false else { return }
        let points = wall.floorPlanPoints()
        guard points.count >= 2 else { return }
        let midIndex = max(0, (points.count - 1) / 2)
        let a = points[midIndex]
        let b = points[min(midIndex + 1, points.count - 1)]
        let mid = FloorPlanMath.project(p: FloorPlanMath.centroid(of: [a, b]), ontoSegmentFrom: a, to: b)
        guard let parts = FloorPlanMath.split(points: points, at: mid, maxDistance: 1) else { return }
        wall.setFloorPlanPoints(parts.left)
        let right = GymArea(
            name: "\(wall.name) B",
            x: FloorPlanMath.centroid(of: parts.right).x,
            y: FloorPlanMath.centroid(of: parts.right).y,
            gym: gym,
            shapePointsData: FloorPlanMath.encode(parts.right),
            shapeClosed: false
        )
        context.insert(right)
        persistMap()
        selectedWall = wall
    }

    private func extendLine(_ wall: GymArea) {
        var pts = wall.floorPlanPoints()
        pts.append(FloorPlanMath.extendedPoint(after: pts))
        wall.setFloorPlanPoints(pts)
        persistMap()
    }

    private func commitPendingWall() {
        guard let pending = namingPending else { return }
        let name = wallNameDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        namingPending = nil
        wallNameDraft = ""
        guard GymJoinMath.isUsableName(name) else { return }
        let center = FloorPlanMath.centroid(of: pending.points)
        let area = GymArea(
            name: name,
            x: center.x,
            y: center.y,
            gym: gym,
            shapePointsData: FloorPlanMath.encode(pending.points),
            shapeClosed: pending.closed
        )
        context.insert(area)
        selectedWall = area
        mode = .select
        gym.currentWallName = name
        for item in gyms { item.isCurrent = (item.id == gym.id) }
        persistMap()
    }

    private func nextDefaultName(prefix: String) -> String {
        let n = gym.areas.count + 1
        return "\(prefix) \(n)"
    }

    private func hitTest(_ point: PlanPoint) -> GymArea? {
        var best: (GymArea, Double)?
        for wall in walls {
            let pts = wall.floorPlanPoints()
            if wall.shapeClosed, pts.count >= 3 {
                let c = FloorPlanMath.centroid(of: pts)
                let d = hypot(point.x - c.x, point.y - c.y)
                if d < 0.12, best == nil || d < best!.1 {
                    best = (wall, d)
                }
            }
            if let idx = FloorPlanMath.nearestSegmentIndex(in: pts, to: point) {
                let a = pts[idx]
                let b = pts[idx + 1]
                let proj = FloorPlanMath.project(p: point, ontoSegmentFrom: a, to: b)
                let d = hypot(point.x - proj.x, point.y - proj.y)
                if d < 0.05, best == nil || d < best!.1 {
                    best = (wall, d)
                }
            }
        }
        return best?.0
    }

    private func nearVertex(of wall: GymArea, point: PlanPoint) -> Bool {
        wall.floorPlanPoints().contains { hypot($0.x - point.x, $0.y - point.y) < 0.04 }
    }

    private func normalized(_ location: CGPoint, in size: CGSize) -> PlanPoint {
        let clamped = GymJoinMath.clampPin(
            x: location.x / max(size.width, 1),
            y: location.y / max(size.height, 1)
        )
        return PlanPoint(x: clamped.x, y: clamped.y)
    }

    private func pixel(_ point: PlanPoint, in size: CGSize) -> CGPoint {
        CGPoint(x: point.x * max(size.width, 1), y: point.y * max(size.height, 1))
    }

    private func openRoutes(for area: GymArea) {
        routesWall = area
        selectedWall = area
        gym.currentWallName = area.name
        for item in gyms { item.isCurrent = (item.id == gym.id) }
        persistMap()
    }

    private func persistMap() {
        try? context.save()
        PhoneWatchBridge.shared.publishSnapshot()
    }

    private func removeWall(_ area: GymArea) {
        let name = area.name
        if selectedWall?.id == area.id { selectedWall = nil }
        if routesWall?.id == area.id { routesWall = nil }
        context.delete(area)
        if gym.currentWallName == name {
            gym.currentWallName = gym.areas.first?.name
        }
        persistMap()
    }

    private func routeList(for area: GymArea) -> some View {
        let routes = area.routes.sorted { $0.createdAt < $1.createdAt }
        return VStack(alignment: .leading, spacing: 12) {
            TextField("Your name on updates", text: $climberName)
                .textFieldStyle(.roundedBorder)
                .onChange(of: climberName) { _, value in
                    ClimberIdentity.name = value
                }

            if routes.isEmpty {
                Text("No routes on this wall yet.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(routes) { route in
                    HStack {
                        Circle()
                            .fill(Color(hold: route.holdColor))
                            .frame(width: 12, height: 12)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(route.label)
                                .font(.subheadline.bold())
                            Text(RouteCredit.line(name: route.updatedBy, at: route.updatedAt))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button("Remove", role: .destructive) { removeRoute(route) }
                            .font(.caption.bold())
                    }
                }
            }

            Picker("Type", selection: $logDiscipline) {
                ForEach(ClimbDiscipline.allCases) { item in
                    Text(item.displayName).tag(item)
                }
            }
            .pickerStyle(.segmented)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(HoldColor.allCases) { color in
                        Button { draftColor = color } label: {
                            Circle()
                                .fill(Color(hold: color))
                                .frame(width: 26, height: 26)
                                .overlay {
                                    Circle().strokeBorder(draftColor == color ? Color.primary : Color.clear, lineWidth: 2)
                                }
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack {
                    ForEach(scale?.grades ?? [], id: \.self) { grade in
                        Button(grade) { logGrade = grade }
                            .font(.subheadline.bold())
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(
                                logGrade == grade ? AnyShapeStyle(.stravaOrange) : AnyShapeStyle(.quaternary),
                                in: Capsule()
                            )
                            .foregroundStyle(logGrade == grade ? Color.white : Color.primary)
                    }
                }
            }

            Button("Add route") { addRoute(on: area) }
                .buttonStyle(.borderedProminent)
                .tint(.stravaOrange)
                .disabled(logGrade == nil || GymJoinMath.isUsableName(trimmedClimberName) == false)
            if GymJoinMath.isUsableName(trimmedClimberName) == false {
                Text("Add your name so other climbers can see who set the route.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func addRoute(on area: GymArea) {
        let name = trimmedClimberName
        guard let grade = logGrade, GymJoinMath.isUsableName(name) else { return }
        ClimberIdentity.name = name
        let index = area.routes.count
        let route = GymRoute(
            grade: grade,
            colorName: draftColor.rawValue,
            x: 0.5,
            y: min(0.9, 0.18 + Double(index) * 0.12),
            discipline: logDiscipline,
            wall: area,
            updatedBy: name,
            updatedAt: .now
        )
        context.insert(route)
        persistMap()
    }

    private func removeRoute(_ route: GymRoute) {
        context.delete(route)
        persistMap()
    }

    private func prepareGrades() {
        if scales.contains(where: { $0.kind == .boulderVScale }) == false {
            context.insert(CustomGradeScale(template: .standardVScale(), isDefault: true))
        }
        if scales.contains(where: { $0.kind == .yds }) == false {
            context.insert(CustomGradeScale(template: .standardYDS()))
        }
        try? context.save()
        if logGrade == nil { logGrade = scale?.grades.first }
    }
}

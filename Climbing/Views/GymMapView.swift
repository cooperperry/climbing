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

private struct RubberBand: Equatable {
    var start: PlanPoint
    var current: PlanPoint
}

/// Overhead floor plan: drag to draw and resize walls, then set routes.
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
    @State private var renameDraft = ""
    @State private var polygonDraft: [PlanPoint] = []
    @State private var rubberBand: RubberBand?
    @State private var shapeDragOrigin: [PlanPoint]?
    @State private var canvasSize: CGSize = .zero
    @State private var climberName = ClimberIdentity.name
    @State private var logDiscipline: ClimbDiscipline = .boulder
    @State private var logGrade: String?
    @State private var draftColor: HoldColor = .blue
    @State private var extendingWallID: UUID?

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
            if selectedWall != nil {
                return "Drag corners to reshape. Drag + to add a segment. Name is optional below."
            }
            return "Tap a shape to edit it."
        case .line:
            return "Drag across the board to draw a wall."
        case .square:
            return "Drag to size a room or cave."
        case .polygon:
            if polygonDraft.isEmpty {
                return "Drag the first side, then keep dragging sides."
            }
            return "Drag the next side. Near the start closes it — or tap Done."
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
                    rubberBand = nil
                    extendingWallID = nil
                    if newMode != .polygon { polygonDraft = [] }
                    if newMode != .select { selectedWall = nil }
                }
                .onChange(of: selectedWall?.id) { _, _ in
                    renameDraft = selectedWall?.name ?? ""
                }

                if mode == .polygon, polygonDraft.count >= 2 {
                    HStack {
                        Button("Done") { finishPolygon(closed: polygonDraft.count >= 3) }
                            .buttonStyle(.borderedProminent)
                            .tint(.stravaOrange)
                        Button("Cancel", role: .cancel) {
                            polygonDraft = []
                            rubberBand = nil
                        }
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
        .sheet(item: $routesWall) { area in
            NavigationStack {
                ScrollView {
                    routeList(for: area)
                        .padding()
                }
                .navigationTitle(FloorPlanMath.displayWallName(area.name))
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
        VStack(alignment: .leading, spacing: 8) {
            TextField("Name (optional)", text: $renameDraft)
                .textFieldStyle(.roundedBorder)
                .submitLabel(.done)
                .onSubmit { applyRename(to: wall) }
                .onChange(of: renameDraft) { _, value in
                    wall.name = FloorPlanMath.optionalWallName(value)
                    if gym.currentWallName != nil || wall.name.isEmpty == false {
                        gym.currentWallName = wall.name.isEmpty ? nil : wall.name
                    }
                }

            HStack(spacing: 8) {
                if wall.shapeClosed == false {
                    if wall.floorPlanPoints().count >= 3 {
                        Button("Close") { closeShape(wall) }
                            .font(.caption.bold())
                    }
                    Button("Break") { breakSelectedWall() }
                        .font(.caption.bold())
                        .disabled(wall.floorPlanPoints().count < 2)
                }
                Button("Routes") { openRoutes(for: wall) }
                    .font(.caption.bold())
                Spacer(minLength: 4)
                Button("Delete", role: .destructive) { removeWall(wall) }
                    .font(.caption.bold())
            }
        }
        .padding(.top, 2)
    }

    private var floorPlan: some View {
        GeometryReader { geo in
            let size = geo.size
            ZStack {
                Color.black

                if walls.isEmpty && polygonDraft.isEmpty && rubberBand == nil {
                    Text("Drag a Line, Square, or Polygon\nto map your gym.")
                        .font(.subheadline.bold())
                        .foregroundStyle(.white.opacity(0.7))
                        .multilineTextAlignment(.center)
                }

                ForEach(walls) { wall in
                    shapeStroke(wall, in: size)
                }

                draftOverlay(in: size)

                ForEach(walls) { wall in
                    nameTag(wall, in: size)
                }

                if mode == .select, let wall = selectedWall {
                    editHandles(for: wall, in: size)
                }
            }
            .contentShape(Rectangle())
            .gesture(canvasGesture(in: size))
            .onAppear { canvasSize = size }
            .onChange(of: size.width) { _, _ in canvasSize = size }
            .onChange(of: size.height) { _, _ in canvasSize = size }
        }
    }

    @ViewBuilder
    private func draftOverlay(in size: CGSize) -> some View {
        if let band = rubberBand {
            switch mode {
            case .line:
                Path { path in
                    path.move(to: pixel(band.start, in: size))
                    path.addLine(to: pixel(band.current, in: size))
                }
                .stroke(Color.stravaOrange, style: StrokeStyle(lineWidth: 3, lineCap: .round))
            case .square:
                let rect = FloorPlanMath.rectangle(from: band.start, to: band.current)
                Path { path in
                    guard let first = rect.first else { return }
                    path.move(to: pixel(first, in: size))
                    for pt in rect.dropFirst() { path.addLine(to: pixel(pt, in: size)) }
                    path.closeSubpath()
                }
                .stroke(Color.stravaOrange, style: StrokeStyle(lineWidth: 3, lineJoin: .round))
            case .polygon:
                Path { path in
                    path.move(to: pixel(band.start, in: size))
                    path.addLine(to: pixel(band.current, in: size))
                }
                .stroke(Color.stravaOrange, style: StrokeStyle(lineWidth: 3, lineCap: .round, dash: [6, 4]))
            case .select:
                EmptyView()
            }
        }

        if polygonDraft.isEmpty == false {
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
    }

    private func shapeStroke(_ wall: GymArea, in size: CGSize) -> some View {
        let points = wall.floorPlanPoints()
        let focused = selectedWall?.id == wall.id
        let stroke = focused ? Color.stravaOrange : Color.white.opacity(0.9)
        return Path { path in
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
        .allowsHitTesting(false)
    }

    private func nameTag(_ wall: GymArea, in size: CGSize) -> some View {
        let label = FloorPlanMath.optionalWallName(wall.name)
        let center = FloorPlanMath.centroid(of: wall.floorPlanPoints())
        let focused = selectedWall?.id == wall.id
        return Group {
            if label.isEmpty == false || focused {
                Text(label.isEmpty ? "Name…" : label)
                    .font(.caption2.bold())
                    .foregroundStyle(focused ? Color.black : Color.white)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(focused ? Color.stravaOrange : Color.white.opacity(0.18), in: Capsule())
                    .position(x: center.x * size.width, y: max(14, center.y * size.height - 18))
            }
        }
        .allowsHitTesting(false)
    }

    @ViewBuilder
    private func editHandles(for wall: GymArea, in size: CGSize) -> some View {
        let points = wall.floorPlanPoints()
        ForEach(Array(points.enumerated()), id: \.offset) { index, pt in
            Circle()
                .fill(Color.stravaOrange)
                .frame(width: 22, height: 22)
                .overlay { Circle().strokeBorder(Color.white, lineWidth: 2) }
                .position(pixel(pt, in: size))
                .gesture(vertexDrag(wall: wall, index: index, in: size))
        }

        if wall.shapeClosed == false, points.isEmpty == false {
            let tip = FloorPlanMath.addSegmentHandle(after: points)
            ZStack {
                Circle()
                    .fill(Color.white)
                    .frame(width: 26, height: 26)
                Image(systemName: "plus")
                    .font(.caption.bold())
                    .foregroundStyle(Color.stravaOrange)
            }
            .position(pixel(tip, in: size))
            .gesture(addSegmentDrag(wall: wall, in: size))
        }
    }

    private func vertexDrag(wall: GymArea, index: Int, in size: CGSize) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                var pts = wall.floorPlanPoints()
                guard index < pts.count else { return }
                let board = canvasSize == .zero ? size : canvasSize
                pts[index] = normalized(value.location, in: board)
                wall.setFloorPlanPoints(pts)
            }
            .onEnded { _ in persistMap() }
    }

    private func addSegmentDrag(wall: GymArea, in size: CGSize) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                let board = canvasSize == .zero ? size : canvasSize
                let point = normalized(value.location, in: board)
                if extendingWallID != wall.id {
                    extendingWallID = wall.id
                    var pts = wall.floorPlanPoints()
                    pts.append(point)
                    wall.setFloorPlanPoints(pts)
                } else {
                    var pts = wall.floorPlanPoints()
                    guard pts.isEmpty == false else { return }
                    pts[pts.count - 1] = point
                    wall.setFloorPlanPoints(pts)
                }
            }
            .onEnded { _ in
                extendingWallID = nil
                persistMap()
            }
    }

    private func canvasGesture(in size: CGSize) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                let point = normalized(value.location, in: size)
                let start = normalized(value.startLocation, in: size)
                switch mode {
                case .line, .square:
                    rubberBand = RubberBand(start: start, current: point)
                case .polygon:
                    let from = polygonDraft.last ?? start
                    rubberBand = RubberBand(start: from, current: point)
                case .select:
                    guard let wall = selectedWall else { return }
                    if nearVertex(of: wall, point: start) { return }
                    if nearAddHandle(of: wall, point: start) { return }
                    if shapeDragOrigin == nil {
                        shapeDragOrigin = wall.floorPlanPoints()
                    }
                    guard let origin = shapeDragOrigin else { return }
                    wall.setFloorPlanPoints(FloorPlanMath.translate(
                        points: origin,
                        dx: point.x - start.x,
                        dy: point.y - start.y
                    ))
                }
            }
            .onEnded { value in
                let moved = hypot(value.translation.width, value.translation.height) >= 12
                let start = normalized(value.startLocation, in: size)
                let end = normalized(value.location, in: size)
                defer {
                    shapeDragOrigin = nil
                    rubberBand = nil
                }

                switch mode {
                case .line:
                    guard moved, FloorPlanMath.isUsableStroke(from: start, to: end) else { return }
                    createWall(points: [start, end], closed: false)
                case .square:
                    guard moved else { return }
                    let rect = FloorPlanMath.rectangle(from: start, to: end)
                    guard FloorPlanMath.isUsableRectangle(rect) else { return }
                    createWall(points: rect, closed: true)
                case .polygon:
                    commitPolygonDrag(start: start, end: end, moved: moved)
                case .select:
                    if moved {
                        if selectedWall != nil {
                            applyRename(to: selectedWall)
                            persistMap()
                        }
                        return
                    }
                    handleSelectTap(at: end)
                }
            }
    }

    private func commitPolygonDrag(start: PlanPoint, end: PlanPoint, moved: Bool) {
        if polygonDraft.isEmpty {
            guard moved, FloorPlanMath.isUsableStroke(from: start, to: end) else { return }
            polygonDraft = [start, end]
            return
        }
        guard moved else { return }
        if FloorPlanMath.shouldClosePolygon(draft: polygonDraft, to: end) {
            finishPolygon(closed: true)
            return
        }
        guard FloorPlanMath.isUsableStroke(from: polygonDraft.last ?? start, to: end) else { return }
        polygonDraft.append(end)
    }

    private func handleSelectTap(at point: PlanPoint) {
        if let wall = selectedWall,
           let next = FloorPlanMath.insertingVertex(in: wall.floorPlanPoints(), at: point) {
            wall.setFloorPlanPoints(next)
            persistMap()
            return
        }
        if let hit = hitTest(point) {
            applyRename(to: selectedWall)
            selectedWall = hit
            renameDraft = hit.name
            gym.currentWallName = hit.name.isEmpty ? nil : hit.name
            persistMap()
        } else {
            applyRename(to: selectedWall)
            selectedWall = nil
            renameDraft = ""
        }
    }

    private func createWall(points: [PlanPoint], closed: Bool) {
        let center = FloorPlanMath.centroid(of: points)
        let area = GymArea(
            name: "",
            x: center.x,
            y: center.y,
            gym: gym,
            shapePointsData: FloorPlanMath.encode(points),
            shapeClosed: closed
        )
        context.insert(area)
        for item in gyms { item.isCurrent = (item.id == gym.id) }
        persistMap()
    }

    private func finishPolygon(closed: Bool) {
        let points = polygonDraft
        polygonDraft = []
        rubberBand = nil
        let needs = closed ? 3 : 2
        guard points.count >= needs else { return }
        createWall(points: points, closed: closed && points.count >= 3)
    }

    private func applyRename(to wall: GymArea?) {
        guard let wall else { return }
        wall.name = FloorPlanMath.optionalWallName(renameDraft)
    }

    private func closeShape(_ wall: GymArea) {
        guard wall.floorPlanPoints().count >= 3 else { return }
        wall.shapeClosed = true
        persistMap()
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
        let rightName = wall.name.isEmpty ? "" : "\(wall.name) B"
        let right = GymArea(
            name: rightName,
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

    private func hitTest(_ point: PlanPoint) -> GymArea? {
        var best: (GymArea, Double)?
        for wall in walls {
            let pts = wall.floorPlanPoints()
            if wall.shapeClosed, pts.count >= 3 {
                let c = FloorPlanMath.centroid(of: pts)
                let d = FloorPlanMath.distance(point, c)
                if d < 0.12, best == nil || d < best!.1 {
                    best = (wall, d)
                }
            }
            if let idx = FloorPlanMath.nearestSegmentIndex(in: pts, to: point) {
                let a = pts[idx]
                let b = pts[idx + 1]
                let proj = FloorPlanMath.project(p: point, ontoSegmentFrom: a, to: b)
                let d = FloorPlanMath.distance(point, proj)
                if d < 0.05, best == nil || d < best!.1 {
                    best = (wall, d)
                }
            }
        }
        return best?.0
    }

    private func nearVertex(of wall: GymArea, point: PlanPoint) -> Bool {
        wall.floorPlanPoints().contains { FloorPlanMath.distance($0, point) < 0.045 }
    }

    private func nearAddHandle(of wall: GymArea, point: PlanPoint) -> Bool {
        guard wall.shapeClosed == false else { return false }
        let tip = FloorPlanMath.addSegmentHandle(after: wall.floorPlanPoints())
        return FloorPlanMath.distance(tip, point) < 0.05
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
        applyRename(to: area)
        routesWall = area
        selectedWall = area
        gym.currentWallName = area.name.isEmpty ? nil : area.name
        for item in gyms { item.isCurrent = (item.id == gym.id) }
        persistMap()
    }

    private func persistMap() {
        try? context.save()
        PhoneWatchBridge.shared.publishSnapshot()
    }

    private func removeWall(_ area: GymArea) {
        let name = area.name
        if selectedWall?.id == area.id {
            selectedWall = nil
            renameDraft = ""
        }
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

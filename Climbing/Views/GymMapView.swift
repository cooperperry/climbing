import PhotosUI
import SwiftUI
import SwiftData
import UIKit

private enum MapWorkspace: String, CaseIterable, Identifiable {
    case routes
    case buildMap

    var id: String { rawValue }

    var title: String {
        switch self {
        case .routes: "Routes"
        case .buildMap: "Build map"
        }
    }
}

private enum BuildTool: String, CaseIterable, Identifiable {
    case pan
    case line
    case square
    case polygon

    var id: String { rawValue }

    var title: String {
        switch self {
        case .pan: "Pan"
        case .line: "Line"
        case .square: "Square"
        case .polygon: "Polygon"
        }
    }

    var systemImage: String {
        switch self {
        case .pan: "hand.draw"
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

    @State private var workspace: MapWorkspace = .routes
    @State private var buildTool: BuildTool = .pan
    @State private var editEdges = false
    @State private var snapGrid = false
    @State private var snapAngle = false
    @State private var snapVertices = false

    @State private var zoomScale: CGFloat = 1.0
    @State private var panOffset: CGSize = .zero
    @State private var panAnchor: CGSize = .zero
    @GestureState private var pinchScale: CGFloat = 1.0

    @State private var selectedWall: GymArea?
    @State private var routesWall: GymArea?
    @State private var renameDraft = ""
    @State private var zoneDraft = ""
    @State private var polygonDraft: [PlanPoint] = []
    @State private var rubberBand: RubberBand?
    @State private var shapeDragOrigin: [PlanPoint]?
    @State private var canvasSize: CGSize = .zero
    @State private var climberName = ClimberIdentity.name
    @State private var logDiscipline: ClimbDiscipline = .boulder
    @State private var logGrade: String?
    @State private var draftColor: HoldColor = .blue
    @State private var extendingWallID: UUID?
    @State private var dragEditsShape = false
    @State private var isEditingName = false
    @State private var wallPendingDelete: GymArea?

    @State private var photoPickerItem: PhotosPickerItem?
    @State private var showAddFloor = false
    @State private var newFloorDraft = ""

    private var scale: CustomGradeScale? {
        let kind: GradeScaleKind = logDiscipline.usesRopeGrades ? .yds : .boulderVScale
        return scales.first { $0.kind == kind } ?? scales.first
    }

    private var currentFloorDisplay: String {
        FloorPlanMath.defaultFloorName(gym.currentFloorName)
    }

    private var activeFloorStorage: String {
        let trimmed = FloorPlanMath.optionalWallName(gym.currentFloorName ?? "")
        return trimmed == "Main" ? "" : trimmed
    }

    private var floorNames: [String] {
        var names = Set(gym.areas.map(\.displayFloor))
        names.insert(currentFloorDisplay)
        return names.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }

    private var wallsOnFloor: [GymArea] {
        gym.areas
            .filter { $0.displayFloor == currentFloorDisplay }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    private var wallsByZone: [(zone: String, walls: [GymArea])] {
        let grouped = Dictionary(grouping: wallsOnFloor) { $0.displayZone }
        return grouped.keys.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
            .map { ($0, grouped[$0]!.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }) }
    }

    private var trimmedClimberName: String {
        climberName.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var allowsZoomPan: Bool {
        workspace == .routes || buildTool == .pan
    }

    private var effectiveZoom: CGFloat {
        min(4, max(0.5, zoomScale * pinchScale))
    }

    private var drawMode: BuildTool? {
        guard workspace == .buildMap else { return nil }
        switch buildTool {
        case .pan: return nil
        case .line, .square, .polygon: return buildTool
        }
    }

    private var hint: String {
        if workspace == .routes {
            return "Pinch to zoom, drag to pan. Tap a wall for routes."
        }
        if selectedWall != nil, editEdges {
            return "Trash on an edge deletes that segment. Turn off Edit edges to move the whole wall."
        }
        if selectedWall != nil {
            return "Drag the shape to move it. Turn on Edit edges to adjust vertices."
        }
        switch buildTool {
        case .pan:
            return "Drag empty space to pan. Pinch to zoom — or drag a wall to move it."
        case .line:
            return "Drag to draw a wall — or tap any shape to select it."
        case .square:
            return "Drag to size a room — or tap any shape to select it."
        case .polygon:
            if polygonDraft.isEmpty {
                return "Drag sides for a polygon — or tap a shape to select it."
            }
            return "Drag the next side. Near the start closes it — or tap Done."
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            Picker("Workspace", selection: $workspace) {
                ForEach(MapWorkspace.allCases) { item in
                    Text(item.title).tag(item)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal)
            .padding(.top, 8)
            .onChange(of: workspace) { _, newValue in
                rubberBand = nil
                polygonDraft = []
                extendingWallID = nil
                dragEditsShape = false
                if newValue == .routes {
                    editEdges = false
                }
            }

            HStack(spacing: 0) {
                zoneSidebar
                floorPlan
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }

            if workspace == .buildMap {
                buildChrome
            } else {
                routesChrome
            }
        }
        .navigationTitle(gym.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if workspace == .buildMap {
                ToolbarItem(placement: .topBarTrailing) {
                    templatesMenu
                }
            }
        }
        .onAppear {
            prepareGrades()
            climberName = ClimberIdentity.name
            if gym.currentFloorName == nil {
                gym.currentFloorName = "Main"
            }
        }
        .onChange(of: logDiscipline) { _, _ in
            logGrade = scale?.grades.first
        }
        .onChange(of: selectedWall?.id) { _, _ in
            renameDraft = selectedWall?.name ?? ""
            zoneDraft = selectedWall?.zoneName ?? ""
            isEditingName = false
        }
        .onChange(of: photoPickerItem) { _, item in
            guard let item else { return }
            Task {
                if let data = try? await item.loadTransferable(type: Data.self) {
                    await MainActor.run {
                        gym.mapImageData = data
                        persistMap()
                    }
                }
            }
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
        .confirmationDialog(
            "Delete this entire wall?",
            isPresented: Binding(
                get: { wallPendingDelete != nil },
                set: { if $0 == false { wallPendingDelete = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Delete wall", role: .destructive) {
                if let wall = wallPendingDelete {
                    wallPendingDelete = nil
                    removeWall(wall)
                }
            }
            Button("Cancel", role: .cancel) { wallPendingDelete = nil }
        } message: {
            Text("This removes the whole shape, not just one segment.")
        }
        .alert("New floor", isPresented: $showAddFloor) {
            TextField("Basement, 2nd…", text: $newFloorDraft)
            Button("Add") { addFloor() }
            Button("Cancel", role: .cancel) { newFloorDraft = "" }
        } message: {
            Text("Walls you draw stay on the floor you have selected.")
        }
    }

    // MARK: - Chrome

    private var routesChrome: some View {
        Text(hint)
            .font(.footnote)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding()
            .background(.bar)
    }

    private var buildChrome: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                Text(hint)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)

                Picker("Tool", selection: $buildTool) {
                    ForEach(BuildTool.allCases) { item in
                        Label(item.title, systemImage: item.systemImage).tag(item)
                    }
                }
                .pickerStyle(.segmented)
                .onChange(of: buildTool) { _, newTool in
                    rubberBand = nil
                    extendingWallID = nil
                    dragEditsShape = false
                    if newTool != .polygon { polygonDraft = [] }
                }

                Toggle("Edit edges", isOn: $editEdges)

                HStack(spacing: 12) {
                    Toggle("Grid", isOn: $snapGrid)
                    Toggle("Angle", isOn: $snapAngle)
                    Toggle("Vertices", isOn: $snapVertices)
                }
                .font(.caption)

                floorPickerRow
                underlayRow

                if buildTool == .polygon, polygonDraft.count >= 2 {
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

                if let wall = selectedWall {
                    selectedWallBar(wall)
                }
            }
            .padding()
        }
        .frame(maxHeight: 280)
        .background(.bar)
    }

    private var floorPickerRow: some View {
        HStack(spacing: 8) {
            Picker("Floor", selection: floorBinding) {
                ForEach(floorNames, id: \.self) { floor in
                    Text(floor).tag(floor)
                }
            }
            .labelsHidden()
            Button("Add floor") { showAddFloor = true }
                .font(.caption.bold())
        }
    }

    private var floorBinding: Binding<String> {
        Binding(
            get: { currentFloorDisplay },
            set: { newValue in
                gym.currentFloorName = newValue
                if let selected = selectedWall, selected.displayFloor != newValue {
                    selectedWall = nil
                }
                persistMap()
            }
        )
    }

    private var underlayRow: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                PhotosPicker(selection: $photoPickerItem, matching: .images) {
                    Label("Underlay photo", systemImage: "photo")
                        .font(.caption.bold())
                }
                if gym.mapImageData != nil {
                    Button("Clear underlay", role: .destructive) {
                        gym.mapImageData = nil
                        photoPickerItem = nil
                        persistMap()
                    }
                    .font(.caption)
                }
            }
            if gym.mapImageData != nil {
                HStack {
                    Text("Opacity")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Slider(value: $gym.underlayOpacity, in: 0 ... 1)
                        .onChange(of: gym.underlayOpacity) { _, _ in persistMap() }
                }
            }
        }
    }

    private var templatesMenu: some View {
        Menu {
            Button("360 A–F ring") { insertTemplateRing360() }
            Button("Cave box") { insertTemplateCaveBox() }
            Button("Duplicate selected") { duplicateSelectedWall() }
                .disabled(selectedWall == nil)
        } label: {
            Label("Templates", systemImage: "square.on.square")
        }
    }

    private var zoneSidebar: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text(currentFloorDisplay)
                    .font(.caption.bold())
                    .foregroundStyle(.secondary)
                if wallsByZone.isEmpty {
                    Text("No walls on this floor.")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                } else {
                    ForEach(wallsByZone, id: \.zone) { group in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(group.zone)
                                .font(.caption2.bold())
                                .foregroundStyle(.secondary)
                            ForEach(group.walls) { wall in
                                Button {
                                    selectWall(wall)
                                } label: {
                                    HStack {
                                        Text(FloorPlanMath.displayWallName(wall.name))
                                            .font(.caption)
                                            .lineLimit(2)
                                            .multilineTextAlignment(.leading)
                                        Spacer(minLength: 0)
                                    }
                                    .padding(.vertical, 4)
                                    .padding(.horizontal, 6)
                                    .background(
                                        selectedWall?.id == wall.id
                                            ? Color.stravaOrange.opacity(0.25)
                                            : Color.primary.opacity(0.06),
                                        in: RoundedRectangle(cornerRadius: 6)
                                    )
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
            }
            .padding(10)
        }
        .frame(width: 118)
        .background(.bar)
    }

    @ViewBuilder
    private func selectedWallBar(_ wall: GymArea) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                if editEdges, wall.shapeClosed == false {
                    if wall.floorPlanPoints().count >= 3 {
                        Button("Close") { closeShape(wall) }
                            .font(.caption.bold())
                    }
                    Button("Break") { breakSelectedWall() }
                        .font(.caption.bold())
                        .disabled(wall.floorPlanPoints().count < 2)
                }
                if workspace == .buildMap {
                    Button("Routes") { openRoutes(for: wall) }
                        .font(.caption.bold())
                }
                Spacer(minLength: 4)
                nameControl(for: wall)
            }

            TextField("Zone (Cave, 360…)", text: $zoneDraft)
                .textFieldStyle(.roundedBorder)
                .font(.caption)
                .onChange(of: zoneDraft) { _, value in
                    wall.zoneName = FloorPlanMath.optionalWallName(value)
                }
                .onSubmit { persistMap() }

            Button(role: .destructive) {
                wallPendingDelete = wall
            } label: {
                Label("Delete wall", systemImage: "trash")
                    .font(.caption.bold())
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .tint(.red)

            if isEditingName {
                TextField("Cave, 360 A…", text: $renameDraft)
                    .textFieldStyle(.roundedBorder)
                    .submitLabel(.done)
                    .onSubmit {
                        applyRename(to: wall)
                        persistMap()
                        isEditingName = false
                    }
                    .onChange(of: renameDraft) { _, value in
                        wall.name = FloorPlanMath.optionalWallName(value)
                        gym.currentWallName = wall.name.isEmpty ? nil : wall.name
                    }
            }
        }
        .padding(.top, 2)
    }

    @ViewBuilder
    private func nameControl(for wall: GymArea) -> some View {
        let label = FloorPlanMath.optionalWallName(wall.name)
        if isEditingName {
            Button("Done") {
                applyRename(to: wall)
                persistMap()
                isEditingName = false
            }
            .font(.caption.bold())
        } else if label.isEmpty {
            Button("Add name") {
                renameDraft = ""
                isEditingName = true
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        } else {
            Button(label) {
                renameDraft = label
                isEditingName = true
            }
            .font(.caption.bold())
            .lineLimit(1)
        }
    }

    // MARK: - Canvas

    private var floorPlan: some View {
        GeometryReader { geo in
            let size = geo.size
            ZStack {
                Color.black

                if let data = gym.mapImageData, let image = UIImage(data: data) {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                        .opacity(gym.underlayOpacity)
                        .allowsHitTesting(false)
                }

                if snapGrid, workspace == .buildMap {
                    gridOverlay(in: size)
                }

                if wallsOnFloor.isEmpty && polygonDraft.isEmpty && rubberBand == nil {
                    Text(workspace == .routes
                        ? "Tap a wall for routes,\nor switch to Build map."
                        : "Drag a Line, Square, or Polygon\nto map your gym.")
                        .font(.subheadline.bold())
                        .foregroundStyle(.white.opacity(0.7))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                }

                ForEach(wallsOnFloor) { wall in
                    shapeStroke(wall, in: size)
                }

                draftOverlay(in: size)

                ForEach(wallsOnFloor) { wall in
                    nameTag(wall, in: size)
                }

                if workspace == .buildMap, editEdges, let wall = selectedWall {
                    editHandles(for: wall, in: size)
                }
            }
            .frame(width: size.width, height: size.height)
            .scaleEffect(effectiveZoom)
            .offset(panOffset)
            .contentShape(Rectangle())
            .gesture(canvasGesture(in: size))
            .simultaneousGesture(zoomGesture)
            .onAppear { canvasSize = size }
            .onChange(of: size.width) { _, _ in canvasSize = size }
            .onChange(of: size.height) { _, _ in canvasSize = size }
        }
    }

    private func gridOverlay(in size: CGSize) -> some View {
        let step = FloorPlanMath.gridStep
        return Path { path in
            var x = 0.0
            while x <= 1.0 + 1e-9 {
                path.move(to: pixel(PlanPoint(x: x, y: 0), in: size))
                path.addLine(to: pixel(PlanPoint(x: x, y: 1), in: size))
                x += step
            }
            var y = 0.0
            while y <= 1.0 + 1e-9 {
                path.move(to: pixel(PlanPoint(x: 0, y: y), in: size))
                path.addLine(to: pixel(PlanPoint(x: 1, y: y), in: size))
                y += step
            }
        }
        .stroke(Color.white.opacity(0.12), lineWidth: 1)
        .allowsHitTesting(false)
    }

    @ViewBuilder
    private func draftOverlay(in size: CGSize) -> some View {
        if let band = rubberBand, let mode = drawMode {
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
            case .pan:
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
            if label.isEmpty == false {
                Text(label)
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
        let isOpenLine = wall.shapeClosed == false
        let vertexSize: CGFloat = isOpenLine && points.count <= 3 ? 28 : 22
        let segmentCount = FloorPlanMath.segmentCount(points: points, closed: wall.shapeClosed)

        ForEach(Array(points.enumerated()), id: \.offset) { index, pt in
            Circle()
                .fill(Color.stravaOrange)
                .frame(width: vertexSize, height: vertexSize)
                .overlay { Circle().strokeBorder(Color.white, lineWidth: 2) }
                .contentShape(Circle().scale(1.4))
                .position(pixel(pt, in: size))
                .gesture(vertexDrag(wall: wall, index: index, in: size))
        }

        if isOpenLine, points.isEmpty == false {
            extendHandle(
                at: FloorPlanMath.addSegmentHandle(after: points),
                in: size,
                wall: wall,
                fromStart: false
            )
            extendHandle(
                at: FloorPlanMath.addSegmentHandle(before: points),
                in: size,
                wall: wall,
                fromStart: true
            )
        }

        ForEach(0 ..< segmentCount, id: \.self) { index in
            if let mid = FloorPlanMath.midpoint(of: points, closed: wall.shapeClosed, segment: index) {
                Button {
                    deleteSegment(at: index, on: wall)
                } label: {
                    Image(systemName: "trash.fill")
                        .font(.caption.bold())
                        .foregroundStyle(.white)
                        .frame(width: 28, height: 28)
                        .background(Color.red.opacity(0.92), in: Circle())
                        .shadow(color: .black.opacity(0.35), radius: 2, y: 1)
                }
                .buttonStyle(.plain)
                .position(pixel(mid, in: size))
            }
        }
    }

    private func extendHandle(at tip: PlanPoint, in size: CGSize, wall: GymArea, fromStart: Bool) -> some View {
        ZStack {
            Circle()
                .fill(Color.white)
                .frame(width: 36, height: 36)
                .shadow(color: .black.opacity(0.35), radius: 2, y: 1)
            Image(systemName: "plus")
                .font(.body.bold())
                .foregroundStyle(Color.stravaOrange)
        }
        .contentShape(Circle().scale(1.35))
        .position(pixel(tip, in: size))
        .gesture(addSegmentDrag(wall: wall, in: size, fromStart: fromStart))
    }

    private var zoomGesture: some Gesture {
        MagnificationGesture()
            .updating($pinchScale) { value, state, _ in
                guard allowsZoomPan else { return }
                state = value
            }
            .onEnded { value in
                guard allowsZoomPan else { return }
                zoomScale = min(4, max(0.5, zoomScale * value))
            }
    }

    private func vertexDrag(wall: GymArea, index: Int, in size: CGSize) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                var pts = wall.floorPlanPoints()
                guard index < pts.count else { return }
                let board = canvasSize == .zero ? size : canvasSize
                let raw = normalized(value.location, in: board)
                let origin = vertexSnapOrigin(points: pts, index: index)
                pts[index] = applySnaps(to: raw, origin: origin, excluding: wall)
                wall.setFloorPlanPoints(pts)
            }
            .onEnded { _ in persistMap() }
    }

    private func vertexSnapOrigin(points: [PlanPoint], index: Int) -> PlanPoint? {
        guard snapAngle else { return nil }
        if index > 0 { return points[index - 1] }
        if points.count > 1 { return points[1] }
        return nil
    }

    private func addSegmentDrag(wall: GymArea, in size: CGSize, fromStart: Bool) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                let board = canvasSize == .zero ? size : canvasSize
                var pts = wall.floorPlanPoints()
                let anchor = fromStart ? pts.first : pts.last
                let raw = normalized(value.location, in: board)
                let point = applySnaps(to: raw, origin: anchor, excluding: wall)

                if extendingWallID != wall.id {
                    extendingWallID = wall.id
                    if fromStart {
                        pts.insert(point, at: 0)
                    } else {
                        pts.append(point)
                    }
                    wall.setFloorPlanPoints(pts)
                } else {
                    guard pts.isEmpty == false else { return }
                    if fromStart {
                        pts[0] = point
                    } else {
                        pts[pts.count - 1] = point
                    }
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
                if workspace == .routes {
                    if allowsZoomPan {
                        panOffset = CGSize(
                            width: panAnchor.width + value.translation.width,
                            height: panAnchor.height + value.translation.height
                        )
                    }
                    return
                }

                if buildTool == .pan, allowsZoomPan {
                    let start = normalized(value.startLocation, in: size)
                    if shapeDragOrigin == nil && rubberBand == nil && dragEditsShape == false {
                        if hitTest(start) != nil {
                            // fall through to shape move
                        } else {
                            panOffset = CGSize(
                                width: panAnchor.width + value.translation.width,
                                height: panAnchor.height + value.translation.height
                            )
                            return
                        }
                    }
                }

                let point = snappedBoardPoint(from: value.location, in: size, strokeOrigin: rubberBand?.start ?? polygonDraft.last)
                let start = normalized(value.startLocation, in: size)

                if shapeDragOrigin == nil && rubberBand == nil && dragEditsShape == false {
                    if let hit = hitTest(start) {
                        dragEditsShape = true
                        if selectedWall?.id != hit.id {
                            applyRename(to: selectedWall)
                            selectedWall = hit
                            renameDraft = hit.name
                            zoneDraft = hit.zoneName
                        }
                        if editEdges,
                           nearVertex(of: hit, point: start)
                            || nearAddHandle(of: hit, point: start)
                            || nearTrash(of: hit, point: start) {
                            return
                        }
                        shapeDragOrigin = hit.floorPlanPoints()
                    } else if let selected = selectedWall,
                              editEdges,
                              nearVertex(of: selected, point: start)
                                || nearAddHandle(of: selected, point: start)
                                || nearTrash(of: selected, point: start) {
                        dragEditsShape = true
                        return
                    } else {
                        dragEditsShape = false
                    }
                }

                if dragEditsShape {
                    guard let wall = selectedWall else { return }
                    if editEdges,
                       nearVertex(of: wall, point: start)
                        || nearAddHandle(of: wall, point: start)
                        || nearTrash(of: wall, point: start) {
                        return
                    }
                    if shapeDragOrigin == nil {
                        shapeDragOrigin = wall.floorPlanPoints()
                    }
                    guard let origin = shapeDragOrigin else { return }
                    let snappedStart = start
                    let snappedPoint = point
                    wall.setFloorPlanPoints(FloorPlanMath.translate(
                        points: origin,
                        dx: snappedPoint.x - snappedStart.x,
                        dy: snappedPoint.y - snappedStart.y
                    ))
                    return
                }

                guard let mode = drawMode else { return }

                switch mode {
                case .line, .square:
                    let origin = normalized(value.startLocation, in: size)
                    let current = applySnaps(to: point, origin: origin, excluding: nil)
                    rubberBand = RubberBand(start: origin, current: current)
                case .polygon:
                    let from = polygonDraft.last ?? start
                    let current = applySnaps(to: point, origin: from, excluding: nil)
                    rubberBand = RubberBand(start: from, current: current)
                case .pan:
                    break
                }
            }
            .onEnded { value in
                let moved = hypot(value.translation.width, value.translation.height) >= 12
                let end = normalized(value.location, in: size)
                let start = normalized(value.startLocation, in: size)
                let wasEditing = dragEditsShape

                if workspace == .routes {
                    panAnchor = panOffset
                    if moved == false {
                        handleRoutesTap(at: end)
                    }
                    return
                }

                if buildTool == .pan, allowsZoomPan, wasEditing == false, shapeDragOrigin == nil, rubberBand == nil {
                    let pannedEmpty = hitTest(start) == nil
                    if pannedEmpty, moved {
                        panAnchor = panOffset
                        return
                    }
                }

                defer {
                    shapeDragOrigin = nil
                    rubberBand = nil
                    dragEditsShape = false
                }

                if wasEditing {
                    if moved {
                        applyRename(to: selectedWall)
                        persistMap()
                    } else {
                        handleSelectTap(at: end)
                    }
                    return
                }

                guard let mode = drawMode else {
                    if buildTool == .pan, moved == false {
                        handleSelectTap(at: end)
                    }
                    return
                }

                switch mode {
                case .line:
                    let a = applySnaps(to: start, origin: nil, excluding: nil)
                    let b = applySnaps(to: end, origin: a, excluding: nil)
                    guard moved, FloorPlanMath.isUsableStroke(from: a, to: b) else {
                        if moved == false { handleSelectTap(at: end) }
                        return
                    }
                    createWall(points: [a, b], closed: false)
                case .square:
                    guard moved else {
                        handleSelectTap(at: end)
                        return
                    }
                    let rect = FloorPlanMath.rectangle(from: start, to: end).map {
                        applySnaps(to: $0, origin: start, excluding: nil)
                    }
                    guard FloorPlanMath.isUsableRectangle(rect) else { return }
                    createWall(points: rect, closed: true)
                case .polygon:
                    if moved == false, polygonDraft.isEmpty {
                        handleSelectTap(at: end)
                        return
                    }
                    commitPolygonDrag(start: start, end: end, moved: moved)
                case .pan:
                    if moved == false { handleSelectTap(at: end) }
                }
            }
    }

    private func snappedBoardPoint(from location: CGPoint, in size: CGSize, strokeOrigin: PlanPoint?) -> PlanPoint {
        let raw = normalized(location, in: size)
        return applySnaps(to: raw, origin: strokeOrigin, excluding: selectedWall)
    }

    private func applySnaps(to point: PlanPoint, origin: PlanPoint?, excluding: GymArea?) -> PlanPoint {
        FloorPlanMath.applySnaps(
            point,
            origin: origin,
            otherPoints: snapVertexCandidates(excluding: excluding),
            grid: snapGrid,
            angle: snapAngle,
            vertices: snapVertices
        )
    }

    private func snapVertexCandidates(excluding: GymArea?) -> [PlanPoint] {
        wallsOnFloor.flatMap { wall -> [PlanPoint] in
            if wall.id == excluding?.id { return [] }
            return wall.floorPlanPoints()
        }
    }

    private func commitPolygonDrag(start: PlanPoint, end: PlanPoint, moved: Bool) {
        if polygonDraft.isEmpty {
            let a = applySnaps(to: start, origin: nil, excluding: nil)
            let b = applySnaps(to: end, origin: a, excluding: nil)
            guard moved, FloorPlanMath.isUsableStroke(from: a, to: b) else { return }
            polygonDraft = [a, b]
            return
        }
        guard moved else { return }
        let snappedEnd = applySnaps(to: end, origin: polygonDraft.last, excluding: nil)
        if FloorPlanMath.shouldClosePolygon(draft: polygonDraft, to: snappedEnd) {
            finishPolygon(closed: true)
            return
        }
        guard FloorPlanMath.isUsableStroke(from: polygonDraft.last ?? start, to: snappedEnd) else { return }
        polygonDraft.append(snappedEnd)
    }

    private func handleRoutesTap(at point: PlanPoint) {
        if let hit = hitTest(point) {
            openRoutes(for: hit)
        }
    }

    private func handleSelectTap(at point: PlanPoint) {
        if workspace == .buildMap, editEdges, let wall = selectedWall {
            let pts = wall.floorPlanPoints()
            if let next = FloorPlanMath.insertingVertex(in: pts, closed: wall.shapeClosed, at: point) {
                wall.setFloorPlanPoints(next)
                persistMap()
                return
            }
        }
        if let hit = hitTest(point) {
            selectWall(hit)
        } else {
            applyRename(to: selectedWall)
            selectedWall = nil
            renameDraft = ""
            zoneDraft = ""
        }
    }

    private func selectWall(_ hit: GymArea) {
        applyRename(to: selectedWall)
        selectedWall = hit
        renameDraft = hit.name
        zoneDraft = hit.zoneName
        gym.currentWallName = hit.name.isEmpty ? nil : hit.name
        persistMap()
    }

    private func deleteSegment(at index: Int, on wall: GymArea) {
        let points = wall.floorPlanPoints()
        let result = FloorPlanMath.removingSegment(at: index, from: points, closed: wall.shapeClosed)
        switch result {
        case .empty:
            removeWall(wall)
        case .single(let next, let closed):
            wall.setFloorPlanPoints(next)
            wall.shapeClosed = closed
            persistMap()
        case .split(let left, let right):
            wall.setFloorPlanPoints(left)
            wall.shapeClosed = false
            let rightWall = GymArea(
                name: "",
                x: FloorPlanMath.centroid(of: right).x,
                y: FloorPlanMath.centroid(of: right).y,
                gym: gym,
                shapePointsData: FloorPlanMath.encode(right),
                shapeClosed: false,
                zoneName: wall.zoneName,
                floorName: wall.floorName
            )
            context.insert(rightWall)
            persistMap()
            selectedWall = wall
        }
    }

    private func createWall(points: [PlanPoint], closed: Bool, name: String = "", zone: String = "") {
        let center = FloorPlanMath.centroid(of: points)
        let area = GymArea(
            name: name,
            x: center.x,
            y: center.y,
            gym: gym,
            shapePointsData: FloorPlanMath.encode(points),
            shapeClosed: closed,
            zoneName: zone,
            floorName: activeFloorStorage
        )
        context.insert(area)
        for item in gyms { item.isCurrent = (item.id == gym.id) }
        selectedWall = area
        renameDraft = name
        zoneDraft = zone
        isEditingName = false
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
            shapeClosed: false,
            zoneName: wall.zoneName,
            floorName: wall.floorName
        )
        context.insert(right)
        persistMap()
        selectedWall = wall
    }

    private func hitTest(_ point: PlanPoint) -> GymArea? {
        var best: (GymArea, Double)?
        for wall in wallsOnFloor {
            let pts = wall.floorPlanPoints()
            if wall.shapeClosed, pts.count >= 3 {
                let c = FloorPlanMath.centroid(of: pts)
                let d = FloorPlanMath.distance(point, c)
                if d < 0.12, best == nil || d < best!.1 {
                    best = (wall, d)
                }
            }
            if let idx = FloorPlanMath.nearestSegmentIndex(in: pts, closed: wall.shapeClosed, to: point),
               let (a, b) = FloorPlanMath.segmentEndpoints(points: pts, closed: wall.shapeClosed, index: idx) {
                let proj = FloorPlanMath.project(p: point, ontoSegmentFrom: a, to: b)
                let d = FloorPlanMath.distance(point, proj)
                if d < 0.07, best == nil || d < best!.1 {
                    best = (wall, d)
                }
            }
        }
        return best?.0
    }

    private func nearVertex(of wall: GymArea, point: PlanPoint) -> Bool {
        wall.floorPlanPoints().contains { FloorPlanMath.distance($0, point) < 0.055 }
    }

    private func nearAddHandle(of wall: GymArea, point: PlanPoint) -> Bool {
        guard wall.shapeClosed == false else { return false }
        let pts = wall.floorPlanPoints()
        let after = FloorPlanMath.addSegmentHandle(after: pts)
        let before = FloorPlanMath.addSegmentHandle(before: pts)
        return FloorPlanMath.distance(after, point) < 0.1
            || FloorPlanMath.distance(before, point) < 0.1
    }

    private func nearTrash(of wall: GymArea, point: PlanPoint) -> Bool {
        let points = wall.floorPlanPoints()
        let count = FloorPlanMath.segmentCount(points: points, closed: wall.shapeClosed)
        for index in 0 ..< count {
            if let mid = FloorPlanMath.midpoint(of: points, closed: wall.shapeClosed, segment: index),
               FloorPlanMath.distance(mid, point) < 0.06 {
                return true
            }
        }
        return false
    }

    private func boardLocation(_ location: CGPoint, in size: CGSize) -> CGPoint {
        let cx = size.width / 2
        let cy = size.height / 2
        let z = effectiveZoom
        return CGPoint(
            x: (location.x - cx - panOffset.width) / z + cx,
            y: (location.y - cy - panOffset.height) / z + cy
        )
    }

    private func normalized(_ location: CGPoint, in size: CGSize) -> PlanPoint {
        let local = boardLocation(location, in: size)
        let clamped = GymJoinMath.clampPin(
            x: local.x / max(size.width, 1),
            y: local.y / max(size.height, 1)
        )
        return PlanPoint(x: clamped.x, y: clamped.y)
    }

    private func pixel(_ point: PlanPoint, in size: CGSize) -> CGPoint {
        CGPoint(x: point.x * max(size.width, 1), y: point.y * max(size.height, 1))
    }

    // MARK: - Templates & floors

    private func addFloor() {
        let name = FloorPlanMath.optionalWallName(newFloorDraft)
        guard name.isEmpty == false else { return }
        gym.currentFloorName = name
        newFloorDraft = ""
        persistMap()
    }

    private func insertTemplateRing360() {
        let specs = FloorPlanTemplates.ring360()
        insertTemplateSpecs(specs)
    }

    private func insertTemplateCaveBox() {
        insertTemplateSpecs([FloorPlanTemplates.caveBox()])
    }

    private func insertTemplateSpecs(_ specs: [FloorPlanTemplates.WallSpec]) {
        for spec in specs {
            let center = FloorPlanMath.centroid(of: spec.points)
            let area = GymArea(
                name: spec.name,
                x: center.x,
                y: center.y,
                gym: gym,
                shapePointsData: FloorPlanMath.encode(spec.points),
                shapeClosed: spec.closed,
                zoneName: spec.zone == "General" ? "" : spec.zone,
                floorName: activeFloorStorage
            )
            context.insert(area)
        }
        for item in gyms { item.isCurrent = (item.id == gym.id) }
        persistMap()
    }

    private func duplicateSelectedWall() {
        guard let wall = selectedWall else { return }
        let points = wall.floorPlanPoints()
        let copy = FloorPlanTemplates.duplicated(points: points, closed: wall.shapeClosed)
        createWall(
            points: copy.points,
            closed: copy.closed,
            name: wall.name.isEmpty ? "" : "\(wall.name) copy",
            zone: wall.zoneName
        )
    }

    private func openRoutes(for area: GymArea) {
        applyRename(to: area)
        routesWall = area
        selectedWall = area
        renameDraft = area.name
        zoneDraft = area.zoneName
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
            zoneDraft = ""
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

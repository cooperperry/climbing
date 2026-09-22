import Observation
import PhotosUI
import SwiftUI
import SwiftData
import UIKit

private enum BuildTool: String, Identifiable {
    case line
    case square
    case polygon

    var id: String { rawValue }

    var title: String {
        switch self {
        case .line: "Line"
        case .square: "Square"
        case .polygon: "Polygon"
        }
    }

    var systemImage: String {
        switch self {
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

    @State private var drawTool: BuildTool?
    @State private var editingShape = false
    @State private var snapGrid = false
    @State private var snapAngle = false
    @State private var snapVertices = true

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
    @State private var draggingRouteID: UUID?
    @State private var routeDragSession = RouteDragSession()
    @State private var mergeTargetRouteID: UUID?
    @State private var mergingRouteIDs: Set<UUID> = []
    @State private var dragEditsShape = false
    @State private var isEditingName = false
    @State private var wallPendingDelete: GymArea?

    @State private var photoPickerItem: PhotosPickerItem?
    @State private var showAddFloor = false
    @State private var newFloorDraft = ""
    @State private var showMapSettings = false
    @State private var showWallList = false
    @State private var showUnlockFloor = false
    @State private var didCenterMap = false

    private var scale: CustomGradeScale? {
        let kind: GradeScaleKind = logDiscipline.usesRopeGrades ? .yds : .boulderVScale
        return scales.first { $0.kind == kind } ?? scales.first
    }

    private var currentFloorDisplay: String {
        FloorPlanMath.defaultFloorName(gym.currentFloorName)
    }

    private var floorIsLocked: Bool {
        lockedFloorNames.contains(currentFloorDisplay)
    }

    private var lockedFloorNames: Set<String> {
        Set(
            gym.lockedFloors
                .split(separator: ",")
                .map { FloorPlanMath.defaultFloorName(String($0)) }
        )
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

    private static let minMapZoom: CGFloat = 0.12
    private static let maxMapZoom: CGFloat = 5

    private var effectiveZoom: CGFloat {
        min(Self.maxMapZoom, max(Self.minMapZoom, zoomScale * pinchScale))
    }

    private var drawMode: BuildTool? { drawTool }

    private var hint: String {
        if editingShape, selectedWall != nil {
            return "Drag corners to reshape. Drag + to extend. Drag one end onto the other to close."
        }
        if let tool = drawTool {
            switch tool {
            case .line:
                return "Drag to draw a wall. Drag ends near each other or another wall to link."
            case .square:
                return "Drag to size a room."
            case .polygon:
                if polygonDraft.isEmpty {
                    return "Drag each side — keep going to build a full shape."
                }
                return "Drag the next side. Bring it to the start and it snaps closed."
            }
        }
        if selectedWall != nil, floorIsLocked {
            return "\(currentFloorDisplay) is locked. You can still place and move routes."
        }
        if selectedWall != nil {
            return "Drag a pin onto another to circle them around its tip. Hold a cluster to move it. Drag one pin away to unmerge."
        }
        return "Pinch to zoom out, drag to pan. Tap a wall to select it."
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            floorPlan
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            VStack(spacing: 0) {
                Text(hint)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(.ultraThinMaterial)
                Spacer()
            }
            .allowsHitTesting(false)

            VStack(spacing: 10) {
                if editingShape, routesWall == nil {
                    Button("Done editing") {
                        editingShape = false
                        applyRename(to: selectedWall)
                        persistMap()
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.stravaOrange)
                }

                if drawTool == .polygon, polygonDraft.count >= 2 {
                    HStack {
                        Button("Done") { finishPolygon(closed: polygonDraft.count >= 3) }
                            .buttonStyle(.borderedProminent)
                            .tint(.stravaOrange)
                        Button("Cancel", role: .cancel) {
                            polygonDraft = []
                            rubberBand = nil
                            drawTool = nil
                        }
                    }
                    .padding(.horizontal)
                }

                if let wall = selectedWall, routesWall == nil {
                    selectedWallCard(wall)
                }
            }
            .padding(.bottom, 8)
        }
        .navigationTitle(gym.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                if floorIsLocked == false {
                    addShapesMenu
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showMapSettings = true
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .accessibilityLabel("Map settings")
            }
        }
        .sheet(isPresented: $showMapSettings) {
            mapSettingsSheet
        }
        .sheet(isPresented: $showWallList) {
            wallListSheet
        }
        .onChange(of: drawTool) { _, newTool in
            rubberBand = nil
            extendingWallID = nil
            dragEditsShape = false
            if newTool != .polygon { polygonDraft = [] }
            if newTool != nil { editingShape = false }
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
            editingShape = false
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

    private var addShapesMenu: some View {
        Menu {
            Button {
                drawTool = .line
            } label: {
                Label("Wall line", systemImage: BuildTool.line.systemImage)
            }
            Button {
                drawTool = .polygon
            } label: {
                Label("Keep drawing", systemImage: BuildTool.polygon.systemImage)
            }
            Button {
                drawTool = .square
            } label: {
                Label("Room", systemImage: BuildTool.square.systemImage)
            }
            Divider()
            Button("Duplicate selected") { duplicateSelectedWall() }
                .disabled(selectedWall == nil)
        } label: {
            Image(systemName: "plus")
        }
        .accessibilityLabel("Add shape")
    }

    private var mapSettingsSheet: some View {
        NavigationStack {
            Form {
                Section("Underlay") {
                    underlayRow
                }
                Section("Floor") {
                    floorPickerRow
                }
                Section("Snap while drawing") {
                    Toggle("Grid", isOn: $snapGrid)
                    Toggle("Angle", isOn: $snapAngle)
                    Toggle("Vertices", isOn: $snapVertices)
                }
                Section {
                    if floorIsLocked {
                        Text("Walls on \(currentFloorDisplay) are locked. Route colors and grades can still change. Unlock only to fix the floor plan.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                        Button("Unlock \(currentFloorDisplay)", role: .destructive) {
                            showUnlockFloor = true
                        }
                    } else {
                        Text("Lock the walls when this floor is finished. Later updates can move routes without redrawing the gym.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                        Button("Lock \(currentFloorDisplay)") {
                            setFloorLocked(true)
                        }
                    }
                }
                Section {
                    Button("Fit gym") { fitGymToScreen(in: canvasSize) }
                    Button("Reset zoom") {
                        zoomScale = 1
                        panOffset = .zero
                        panAnchor = .zero
                    }
                    Button("Wall list by zone") {
                        showMapSettings = false
                        showWallList = true
                    }
                }
            }
            .navigationTitle("Map settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { showMapSettings = false }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .confirmationDialog(
            "Unlock \(currentFloorDisplay)?",
            isPresented: $showUnlockFloor,
            titleVisibility: .visible
        ) {
            Button("Unlock floor plan", role: .destructive) {
                setFloorLocked(false)
            }
            Button("Keep locked", role: .cancel) {}
        } message: {
            Text("Walls can be moved and deleted again. Routes stay where they are.")
        }
    }

    private var wallListSheet: some View {
        NavigationStack {
            ScrollView {
                wallListContent
                    .padding()
            }
            .navigationTitle(currentFloorDisplay)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { showWallList = false }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    @ViewBuilder
    private func selectedWallCard(_ wall: GymArea) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Button("Routes") { openRoutes(for: wall) }
                    .buttonStyle(.borderedProminent)
                    .tint(.stravaOrange)

                if editingShape {
                    if wall.shapeClosed == false {
                        if wall.floorPlanPoints().count >= 3 {
                            Button("Close shape") { closeShape(wall) }
                                .font(.caption.bold())
                            Button("Remove end") { removeLastPoint(on: wall) }
                                .font(.caption.bold())
                        }
                        Button("Break") { breakSelectedWall() }
                            .font(.caption.bold())
                            .disabled(wall.floorPlanPoints().count < 2)
                    }
                } else if floorIsLocked {
                    Text("Floor locked")
                        .font(.caption.bold())
                        .foregroundStyle(.secondary)
                } else {
                    Button("Edit shape") {
                        drawTool = nil
                        editingShape = true
                    }
                    .buttonStyle(.bordered)
                }

                Spacer(minLength: 0)
                nameControl(for: wall)
            }

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

            if floorIsLocked == false {
                Button(role: .destructive) {
                    wallPendingDelete = wall
                } label: {
                    Label("Delete wall", systemImage: "trash")
                        .font(.caption.bold())
                }
                .buttonStyle(.borderless)
            }
        }
        .padding(14)
        .background(.bar, in: RoundedRectangle(cornerRadius: 14))
        .padding(.horizontal, 10)
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

    private var wallListContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            if wallsByZone.isEmpty {
                Text("No walls on this floor.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(wallsByZone, id: \.zone) { group in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(group.zone)
                            .font(.caption.bold())
                            .foregroundStyle(.secondary)
                        ForEach(group.walls) { wall in
                            Button {
                                selectWall(wall)
                                showWallList = false
                            } label: {
                                HStack {
                                    Text(FloorPlanMath.displayWallName(wall.name))
                                        .font(.subheadline)
                                        .lineLimit(2)
                                        .multilineTextAlignment(.leading)
                                    Spacer(minLength: 0)
                                }
                                .padding(.vertical, 8)
                                .padding(.horizontal, 10)
                                .background(
                                    selectedWall?.id == wall.id
                                        ? Color.stravaOrange.opacity(0.2)
                                        : Color.primary.opacity(0.06),
                                    in: RoundedRectangle(cornerRadius: 8)
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
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

                if snapGrid {
                    gridOverlay(in: size)
                }

                if wallsOnFloor.isEmpty && polygonDraft.isEmpty && rubberBand == nil {
                    Text(drawTool == nil
                        ? "Tap + to add walls,\nor trace your gym from a photo."
                        : "Drag on the map to draw.")
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

                if editingShape, floorIsLocked == false, routesWall == nil, let wall = selectedWall {
                    editHandles(for: wall, in: size)
                }

                // Routes sit above shape chrome so tags stay tappable.
                ForEach(wallsOnFloor) { wall in
                    routeMarkers(for: wall, in: size)
                }
            }
            .frame(width: size.width, height: size.height)
            .scaleEffect(effectiveZoom)
            .offset(panOffset)
            .coordinateSpace(name: "gymMap")
            .contentShape(Rectangle())
            .gesture(canvasGesture(in: size))
            .simultaneousGesture(zoomGesture)
            .onAppear {
                canvasSize = size
                if didCenterMap == false {
                    didCenterMap = true
                    fitGymToScreen(in: size)
                }
            }
            .onChange(of: size.width) { _, _ in canvasSize = size }
            .onChange(of: size.height) { _, _ in canvasSize = size }
        }
    }

    private func gridOverlay(in size: CGSize) -> some View {
        let step = FloorPlanMath.gridStep
        let bounds = visibleBoardBounds(in: size)
        return Path { path in
            var x = (bounds.minX / step).rounded(.down) * step
            while x <= bounds.maxX + 1e-9 {
                path.move(to: CGPoint(x: x * size.width, y: bounds.minY * size.height))
                path.addLine(to: CGPoint(x: x * size.width, y: bounds.maxY * size.height))
                x += step
            }
            var y = (bounds.minY / step).rounded(.down) * step
            while y <= bounds.maxY + 1e-9 {
                path.move(to: CGPoint(x: bounds.minX * size.width, y: y * size.height))
                path.addLine(to: CGPoint(x: bounds.maxX * size.width, y: y * size.height))
                y += step
            }
        }
        .stroke(Color.white.opacity(0.12), lineWidth: 1)
        .allowsHitTesting(false)
    }

    /// Board rectangle currently on screen, so the grid covers the view instead of the old 0...1 box.
    private func visibleBoardBounds(in size: CGSize) -> (minX: Double, maxX: Double, minY: Double, maxY: Double) {
        let corners = [
            CGPoint.zero,
            CGPoint(x: size.width, y: 0),
            CGPoint(x: 0, y: size.height),
            CGPoint(x: size.width, y: size.height),
        ]
        let points = corners.map { boardLocation($0, in: size) }
        let xs = points.map { $0.x / max(size.width, 1) }
        let ys = points.map { $0.y / max(size.height, 1) }
        let minX = xs.min() ?? 0
        let maxX = xs.max() ?? 1
        let minY = ys.min() ?? 0
        let maxY = ys.max() ?? 1
        return (minX - 0.02, maxX + 0.02, minY - 0.02, maxY + 0.02)
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

    private func routeMarkers(for wall: GymArea, in size: CGSize) -> some View {
        let routes = wall.routes.sorted { $0.createdAt < $1.createdAt }
        return ForEach(routes) { route in
            let pos = PlanPoint(x: route.x, y: route.y)
            let merging = mergingRouteIDs.contains(route.id)
            let isTarget = mergeTargetRouteID == route.id
            let movingGroup = routeDragSession.movingCluster && route.groupKey == routeDragSession.groupKey
            let isDragging = draggingRouteID == route.id || movingGroup
            let tipAngle = pinTipAngle(for: route)
            let head = RouteMapPin.headOffset(for: tipAngle)
            RouteMapPin(
                grade: route.grade,
                holdColor: route.holdColor,
                highlighted: isDragging || isTarget || merging,
                tipAngle: tipAngle
            )
            .frame(width: 96, height: 96)
            .contentShape(
                CircleSpot(
                    center: CGPoint(x: 48 + head.width, y: 48 + head.height),
                    radius: 20
                )
            )
            .scaleEffect(
                isTarget ? 1.12
                    : merging ? 0.9
                    : isDragging ? 1.08
                    : 1.0
            )
            .opacity(merging ? 0.94 : 1.0)
            .position(pixel(pos, in: size))
            .animation(isDragging ? nil : Self.routeSpring, value: route.x)
            .animation(isDragging ? nil : Self.routeSpring, value: route.y)
            .animation(Self.routeSpring, value: merging)
            .animation(Self.routeSpring, value: isTarget)
            .animation(Self.routeSpring, value: tipAngle)
            .animation(Self.routeSpring, value: routeDragSession.groupKey)
            .highPriorityGesture(routeDrag(route, in: size))
        }
    }

    private static var routeSpring: Animation {
        .spring(response: 0.4, dampingFraction: 0.52)
    }

    @ViewBuilder
    private func editHandles(for wall: GymArea, in size: CGSize) -> some View {
        let points = wall.floorPlanPoints()
        let isOpenLine = wall.shapeClosed == false
        let vertexSize: CGFloat = isOpenLine && points.count <= 3 ? 28 : 22

        ForEach(Array(points.enumerated()), id: \.offset) { index, pt in
            Circle()
                .fill(Color.stravaOrange)
                .frame(width: vertexSize, height: vertexSize)
                .overlay { Circle().strokeBorder(Color.white, lineWidth: 2) }
                .contentShape(Circle().scale(1.4))
                .position(pixel(pt, in: size))
                .highPriorityGesture(vertexDrag(wall: wall, index: index, in: size))
        }

        if isOpenLine, points.isEmpty == false {
            extendHandle(
                at: extendAnchor(points: points, fromStart: false, in: size),
                in: size,
                wall: wall,
                fromStart: false
            )
            extendHandle(
                at: extendAnchor(points: points, fromStart: true, in: size),
                in: size,
                wall: wall,
                fromStart: true
            )
        }
    }

    /// A fixed gap past the endpoint, in screen points, so a long wall does not throw the + far away.
    private func extendAnchor(points: [PlanPoint], fromStart: Bool, in size: CGSize) -> PlanPoint {
        guard let end = fromStart ? points.first : points.last else {
            return PlanPoint(x: 0.5, y: 0.5)
        }
        let other: PlanPoint? = points.count >= 2 ? (fromStart ? points[1] : points[points.count - 2]) : nil
        let dx = other.map { end.x - $0.x } ?? (fromStart ? -1 : 1)
        let dy = other.map { end.y - $0.y } ?? 0
        let pixelLength = hypot(dx * size.width, dy * size.height)
        let ux = pixelLength > 1 ? dx * size.width / pixelLength : (fromStart ? -1 : 1)
        let uy = pixelLength > 1 ? dy * size.height / pixelLength : 0
        let gap = 32 / max(effectiveZoom, 0.35)
        let tipX = end.x * size.width + ux * gap
        let tipY = end.y * size.height + uy * gap
        return PlanPoint(rawX: tipX / max(size.width, 1), rawY: tipY / max(size.height, 1))
    }

    private func extendHandle(at tip: PlanPoint, in size: CGSize, wall: GymArea, fromStart: Bool) -> some View {
        ZStack {
            Circle()
                .fill(Color.white)
                .frame(width: 28, height: 28)
                .shadow(color: .black.opacity(0.35), radius: 2, y: 1)
            Image(systemName: "plus")
                .font(.caption.bold())
                .foregroundStyle(Color.stravaOrange)
        }
        .contentShape(Circle().scale(1.4))
        .scaleEffect(1 / max(effectiveZoom, 0.35))
        .position(pixel(tip, in: size))
        .highPriorityGesture(addSegmentDrag(wall: wall, in: size, fromStart: fromStart))
    }

    private var zoomGesture: some Gesture {
        MagnificationGesture()
            .updating($pinchScale) { value, state, _ in
                state = value
            }
            .onEnded { value in
                zoomScale = min(Self.maxMapZoom, max(Self.minMapZoom, zoomScale * value))
            }
    }

    private func vertexDrag(wall: GymArea, index: Int, in size: CGSize) -> some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .named("gymMap"))
            .onChanged { value in
                var pts = wall.floorPlanPoints()
                guard index < pts.count else { return }
                let board = canvasSize == .zero ? size : canvasSize
                let raw = normalized(value.location, in: board)
                let origin = vertexSnapOrigin(points: pts, index: index)
                pts[index] = applySnaps(to: raw, origin: origin, excluding: wall)
                wall.setFloorPlanPoints(pts)
                keepVisible(pts[index], in: board)
            }
            .onEnded { _ in
                tryLinkOrClose(wall)
                persistMap()
            }
    }

    /// Slide the map so a dragged corner or + handle stays on screen.
    private func keepVisible(_ point: PlanPoint, in size: CGSize) {
        let local = CGPoint(x: point.x * size.width, y: point.y * size.height)
        let center = CGPoint(x: size.width / 2, y: size.height / 2)
        let zoom = effectiveZoom
        let screen = CGPoint(
            x: center.x + (local.x - center.x) * zoom + panOffset.width,
            y: center.y + (local.y - center.y) * zoom + panOffset.height
        )
        let margin: CGFloat = 64
        var shift = CGSize.zero
        if screen.x < margin { shift.width = margin - screen.x }
        if screen.x > size.width - margin { shift.width = size.width - margin - screen.x }
        if screen.y < margin { shift.height = margin - screen.y }
        if screen.y > size.height - margin { shift.height = size.height - margin - screen.y }
        guard shift != .zero else { return }
        panOffset.width += shift.width
        panOffset.height += shift.height
        panAnchor = panOffset
    }

    private func removeLastPoint(on wall: GymArea) {
        var points = wall.floorPlanPoints()
        guard points.count > 2 else { return }
        points.removeLast()
        wall.setFloorPlanPoints(points)
        wall.shapeClosed = false
        persistMap()
    }

    private func vertexSnapOrigin(points: [PlanPoint], index: Int) -> PlanPoint? {
        guard snapAngle else { return nil }
        if index > 0 { return points[index - 1] }
        if points.count > 1 { return points[1] }
        return nil
    }

    private func routeDrag(_ route: GymRoute, in size: CGSize) -> some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .named("gymMap"))
            .onChanged { value in
                let board = canvasSize == .zero ? size : canvasSize
                let finger = normalized(value.location, in: board)
                if routeDragSession.routeID != route.id {
                    routeDragSession.beginTracking(route, finger: finger)
                    scheduleClusterHold(for: route, session: routeDragSession)
                }
                routeDragSession.lastFinger = finger
                let start = routeDragSession.fingerStart ?? finger
                let slop = 16 / max(effectiveZoom, 0.5) / max(board.width, 1)
                if FloorPlanMath.distance(finger, start) > slop {
                    routeDragSession.cancelHold()
                }

                if routeDragSession.movingCluster {
                    let lock = routeDragSession.fingerAtLock ?? finger
                    var transaction = Transaction()
                    transaction.disablesAnimations = true
                    withTransaction(transaction) {
                        shiftCluster(dx: finger.x - lock.x, dy: finger.y - lock.y)
                    }
                    return
                }

                draggingRouteID = route.id
                let tip = PlanPoint(
                    x: finger.x + routeDragSession.grabDeltaX,
                    y: finger.y + routeDragSession.grabDeltaY
                )
                if let other = nearestRoutePin(
                    to: tip,
                    excluding: route.id,
                    ignoringGroup: route.groupKey,
                    draggedAngle: pinTipAngle(for: route),
                    in: board
                ) {
                    mergeTargetRouteID = other.id
                } else {
                    mergeTargetRouteID = nil
                }
                var transaction = Transaction()
                transaction.disablesAnimations = true
                withTransaction(transaction) {
                    route.setPin(x: tip.x, y: tip.y)
                }
            }
            .onEnded { _ in
                let movedCluster = routeDragSession.movingCluster
                routeDragSession.cancelHold()
                if movedCluster {
                    draggingRouteID = nil
                    mergeTargetRouteID = nil
                    routeDragSession.end()
                    persistMap()
                    return
                }
                if let targetID = mergeTargetRouteID,
                   let target = routeOnFloor(id: targetID) {
                    snapMergeRoutes(dragged: route, onto: target)
                } else if let origin = routeDragSession.origin, route.groupKey != nil {
                    let moved = FloorPlanMath.distance(
                        PlanPoint(x: route.x, y: route.y),
                        origin
                    )
                    if moved >= FloorPlanMath.routeUnmergeDistance {
                        unmergeRoute(route)
                    } else {
                        route.setPin(x: origin.x, y: origin.y)
                    }
                }
                draggingRouteID = nil
                mergeTargetRouteID = nil
                routeDragSession.end()
                persistMap()
            }
    }

    /// After a short still hold, the whole merged circle follows the finger.
    private func scheduleClusterHold(for route: GymRoute, session: RouteDragSession) {
        guard let key = route.groupKey else { return }
        let mates = allFloorRoutes().filter { $0.groupKey == key }
        guard mates.count > 1 else { return }
        let token = session.holdToken
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
            guard session.holdToken == token, session.routeID == route.id else { return }
            guard session.movingCluster == false else { return }
            session.armCluster(mates, finger: session.lastFinger ?? session.fingerStart)
            session.playHaptic()
        }
    }

    private func shiftCluster(dx: Double, dy: Double) {
        for (id, origin) in routeDragSession.clusterOrigins {
            guard let mate = routeOnFloor(id: id) else { continue }
            mate.setPin(x: origin.x + dx, y: origin.y + dy)
        }
    }

    /// Clockwise angle that puts this pin's head on the circle around the shared tip.
    private func pinTipAngle(for route: GymRoute) -> Angle {
        guard let key = route.groupKey else { return .zero }
        let mates = allFloorRoutes()
            .filter { $0.groupKey == key }
            .sorted { $0.createdAt < $1.createdAt }
        guard mates.count > 1,
              let index = mates.firstIndex(where: { $0.id == route.id })
        else { return .zero }
        return .radians(FloorPlanMath.clusterAngles(count: mates.count)[index])
    }

    private func allFloorRoutes() -> [GymRoute] {
        wallsOnFloor.flatMap(\.routes)
    }

    private func routeOnFloor(id: UUID) -> GymRoute? {
        allFloorRoutes().first { $0.id == id }
    }

    private func nearestRoutePin(
        to point: PlanPoint,
        excluding id: UUID,
        ignoringGroup group: String? = nil,
        draggedAngle: Angle = .zero,
        in size: CGSize
    ) -> GymRoute? {
        let draggedHead = headBoardPoint(tip: point, angle: draggedAngle, in: size)
        var best: (GymRoute, Double)?
        for route in allFloorRoutes() where route.id != id {
            if let group, route.groupKey == group { continue }
            let tip = PlanPoint(x: route.x, y: route.y)
            let head = headBoardPoint(tip: tip, angle: pinTipAngle(for: route), in: size)
            let d = min(
                FloorPlanMath.distance(point, tip),
                FloorPlanMath.distance(draggedHead, head)
            )
            if d < FloorPlanMath.routeMergeDistance, best == nil || d < best!.1 {
                best = (route, d)
            }
        }
        return best?.0
    }

    /// Board position of a pin head. Angle 0 is straight above the tip.
    private func headBoardPoint(tip: PlanPoint, angle: Angle, in size: CGSize) -> PlanPoint {
        let head = RouteMapPin.headOffset(for: angle)
        return PlanPoint(
            x: tip.x + Double(head.width) / max(size.width, 1),
            y: tip.y + Double(head.height) / max(size.height, 1)
        )
    }

    /// Drop one pin on another. Only the dragged pin joins the target — former
    /// partners stay behind so two pins can be paired on their own.
    private func snapMergeRoutes(dragged: GymRoute, onto target: GymRoute) {
        guard dragged.id != target.id else { return }
        if let draggedKey = dragged.groupKey, draggedKey == target.groupKey {
            let tip = PlanPoint(x: target.x, y: target.y)
            animateRouteLayout([dragged], to: [tip])
            return
        }

        let previousKey = dragged.groupKey
        let host = target.wall ?? dragged.wall
        let key = target.groupKey ?? UUID().uuidString

        dragged.groupKey = nil
        dissolveGroupIfSparse(previousKey)

        dragged.wall = host
        dragged.groupKey = key
        target.groupKey = key

        let center = PlanPoint(x: target.x, y: target.y)
        let cluster = allFloorRoutes()
            .filter { $0.groupKey == key }
            .sorted { $0.createdAt < $1.createdAt }
        let slots = FloorPlanMath.mergeCluster(count: cluster.count, around: center)

        if let host {
            selectedWall = host
            if routesWall != nil { routesWall = host }
        }
        animateRouteLayout(cluster, to: slots)
    }

    /// Drag a pin off its cluster. A leftover single pin becomes independent too.
    private func unmergeRoute(_ route: GymRoute) {
        guard let key = route.groupKey else { return }
        route.groupKey = nil
        dissolveGroupIfSparse(key)
    }

    private func dissolveGroupIfSparse(_ key: String?) {
        guard let key else { return }
        let rest = allFloorRoutes().filter { $0.groupKey == key }
        if rest.count <= 1 {
            for route in rest {
                route.groupKey = nil
            }
        }
    }

    private func addSegmentDrag(wall: GymArea, in size: CGSize, fromStart: Bool) -> some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .named("gymMap"))
            .onChanged { value in
                let board = canvasSize == .zero ? size : canvasSize
                var pts = wall.floorPlanPoints()
                let anchor = fromStart ? pts.first : pts.last
                let raw = normalized(value.location, in: board)
                var point = applySnaps(to: raw, origin: anchor, excluding: wall)
                if pts.count >= 3 {
                    let otherEnd = fromStart ? pts.last : pts.first
                    if let otherEnd, FloorPlanMath.distance(point, otherEnd) < FloorPlanMath.closeSnapDistance {
                        point = otherEnd
                    }
                }

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
                keepVisible(point, in: board)
            }
            .onEnded { _ in
                extendingWallID = nil
                tryLinkOrClose(wall)
                persistMap()
            }
    }

    private func canvasGesture(in size: CGSize) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                if draggingRouteID != nil { return }
                if floorIsLocked {
                    let start = normalized(value.startLocation, in: size)
                    if nearAnyRoute(start) { return }
                    panOffset = CGSize(
                        width: panAnchor.width + value.translation.width,
                        height: panAnchor.height + value.translation.height
                    )
                    return
                }

                if drawTool == nil {
                    let start = normalized(value.startLocation, in: size)
                    if shapeDragOrigin == nil && rubberBand == nil && dragEditsShape == false {
                        if nearAnyRoute(start) { return }
                        if hitTest(start) == nil {
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
                if nearAnyRoute(start) { return }

                if shapeDragOrigin == nil && rubberBand == nil && dragEditsShape == false {
                    if let hit = hitTest(start) {
                        dragEditsShape = true
                        if selectedWall?.id != hit.id {
                            applyRename(to: selectedWall)
                            selectedWall = hit
                            renameDraft = hit.name
                            zoneDraft = hit.zoneName
                        }
                        if nearShapeChrome(of: hit, point: start) {
                            return
                        }
                        shapeDragOrigin = hit.floorPlanPoints()
                    } else if let selected = selectedWall,
                              nearShapeChrome(of: selected, point: start) {
                        dragEditsShape = true
                        return
                    } else {
                        dragEditsShape = false
                    }
                }

                if dragEditsShape {
                    guard let wall = selectedWall else { return }
                    if nearShapeChrome(of: wall, point: start) {
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
                    var current = applySnaps(to: point, origin: from, excluding: nil)
                    if polygonDraft.count >= 2,
                       FloorPlanMath.shouldClosePolygon(draft: polygonDraft, to: current),
                       let first = polygonDraft.first {
                        current = first
                    }
                    rubberBand = RubberBand(start: from, current: current)
                }
            }
            .onEnded { value in
                if floorIsLocked {
                    let moved = hypot(value.translation.width, value.translation.height) >= 12
                    panAnchor = panOffset
                    if moved == false {
                        handleBrowseTap(at: normalized(value.location, in: size))
                    }
                    return
                }
                let moved = hypot(value.translation.width, value.translation.height) >= 12
                let end = normalized(value.location, in: size)
                let start = normalized(value.startLocation, in: size)
                let wasEditing = dragEditsShape
                let browsing = drawTool == nil

                if browsing, wasEditing == false, shapeDragOrigin == nil, rubberBand == nil {
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
                    } else if browsing {
                        handleBrowseTap(at: end)
                    } else {
                        handleSelectTap(at: end)
                    }
                    return
                }

                guard let mode = drawMode else {
                    panAnchor = panOffset
                    if moved == false {
                        handleBrowseTap(at: end)
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

    private func handleBrowseTap(at point: PlanPoint) {
        if let hit = hitTest(point) {
            selectWall(hit)
        } else {
            applyRename(to: selectedWall)
            selectedWall = nil
            renameDraft = ""
            zoneDraft = ""
        }
    }

    private func handleSelectTap(at point: PlanPoint) {
        if editingShape, let wall = selectedWall {
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
        drawTool = nil
        persistMap()
    }

    private func finishPolygon(closed: Bool) {
        let points = polygonDraft
        polygonDraft = []
        rubberBand = nil
        drawTool = nil
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
        mergeRoutes(on: wall, preferRing: true)
    }

    /// Snap open ends together into a closed loop, or merge into a neighboring open wall.
    private func tryLinkOrClose(_ wall: GymArea) {
        guard wall.shapeClosed == false else { return }
        let points = wall.floorPlanPoints()
        guard points.count >= 2 else { return }

        if FloorPlanMath.shouldCloseOpenShape(points: points) {
            wall.shapeClosed = true
            mergeRoutes(on: wall, preferRing: true)
            return
        }

        for other in wallsOnFloor where other.id != wall.id && other.shapeClosed == false {
            let otherPoints = other.floorPlanPoints()
            guard let joined = FloorPlanMath.joinOpenPolylines(points, otherPoints) else { continue }
            wall.setFloorPlanPoints(joined)
            let absorbed = other.routes
            for route in absorbed {
                route.wall = wall
            }
            if selectedWall?.id == other.id {
                selectedWall = wall
            }
            if routesWall?.id == other.id {
                routesWall = wall
            }
            context.delete(other)
            if FloorPlanMath.shouldCloseOpenShape(points: joined) {
                wall.shapeClosed = true
            }
            mergeRoutes(on: wall, preferRing: wall.shapeClosed || joined.count >= 4)
            return
        }
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

    private func nearShapeChrome(of wall: GymArea, point: PlanPoint) -> Bool {
        guard editingShape, routesWall == nil else { return false }
        return nearAddHandle(of: wall, point: point)
            || nearVertex(of: wall, point: point)
            || nearTrash(of: wall, point: point)
    }

    private func nearAnyRoute(_ point: PlanPoint) -> Bool {
        for wall in wallsOnFloor {
            for route in wall.routes {
                if FloorPlanMath.distance(PlanPoint(x: route.x, y: route.y), point) < 0.05 {
                    return true
                }
            }
        }
        return false
    }

    private func nearVertex(of wall: GymArea, point: PlanPoint) -> Bool {
        wall.floorPlanPoints().contains { FloorPlanMath.distance($0, point) < 0.055 }
    }

    private func nearAddHandle(of wall: GymArea, point: PlanPoint) -> Bool {
        guard wall.shapeClosed == false else { return false }
        let pts = wall.floorPlanPoints()
        let after = FloorPlanMath.addSegmentHandle(after: pts)
        let before = FloorPlanMath.addSegmentHandle(before: pts)
        return FloorPlanMath.distance(after, point) < 0.12
            || FloorPlanMath.distance(before, point) < 0.12
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
        return PlanPoint(
            x: local.x / max(size.width, 1),
            y: local.y / max(size.height, 1)
        )
    }

    private func pixel(_ point: PlanPoint, in size: CGSize) -> CGPoint {
        CGPoint(x: point.x * max(size.width, 1), y: point.y * max(size.height, 1))
    }

    /// Frame every wall and pin in the phone-shaped canvas.
    private func fitGymToScreen(in size: CGSize) {
        guard size.width > 1, size.height > 1 else { return }
        var xs: [Double] = []
        var ys: [Double] = []
        for wall in wallsOnFloor {
            for point in wall.floorPlanPoints() {
                xs.append(point.x)
                ys.append(point.y)
            }
            for route in wall.routes {
                xs.append(route.x)
                ys.append(route.y)
            }
        }
        guard let minX = xs.min(), let maxX = xs.max(), let minY = ys.min(), let maxY = ys.max() else {
            zoomScale = 1
            panOffset = .zero
            panAnchor = .zero
            return
        }
        let pad = 0.06
        let left = minX - pad
        let right = maxX + pad
        let top = minY - pad
        let bottom = maxY + pad
        let contentW = max((right - left) * size.width, 1)
        let contentH = max((bottom - top) * size.height, 1)
        let scale = min(size.width / contentW, size.height / contentH)
        let zoom = min(Self.maxMapZoom, max(Self.minMapZoom, scale))
        zoomScale = zoom
        let midX = (left + right) / 2 * size.width
        let midY = (top + bottom) / 2 * size.height
        panOffset = CGSize(
            width: (size.width / 2 - midX) * zoom,
            height: (size.height / 2 - midY) * zoom
        )
        panAnchor = panOffset
    }

    // MARK: - Floors

    private func setFloorLocked(_ locked: Bool) {
        var names = lockedFloorNames
        if locked {
            names.insert(currentFloorDisplay)
            editingShape = false
            drawTool = nil
            polygonDraft = []
            rubberBand = nil
        } else {
            names.remove(currentFloorDisplay)
        }
        gym.lockedFloors = names.sorted().joined(separator: ",")
        persistMap()
    }

    private func addFloor() {
        let name = FloorPlanMath.optionalWallName(newFloorDraft)
        guard name.isEmpty == false else { return }
        gym.currentFloorName = name
        newFloorDraft = ""
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
        editingShape = false
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
        let zonePeers = wallsOnFloor.filter {
            $0.id != area.id && $0.displayZone == area.displayZone && $0.routes.isEmpty == false
        }
        let peerRouteCount = zonePeers.reduce(0) { $0 + $1.routes.count }
        return VStack(alignment: .leading, spacing: 12) {
            TextField("Your name on updates", text: $climberName)
                .textFieldStyle(.roundedBorder)
                .onChange(of: climberName) { _, value in
                    ClimberIdentity.name = value
                }

            Text("Drag a pin onto another to join its cluster — they bounce into a semi-circle. Unrelated pins stay put.")
                .font(.caption)
                .foregroundStyle(.secondary)

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
                        Button("Remove", role: .destructive) { removeRoute(route, on: area) }
                            .font(.caption.bold())
                    }
                }

                if routes.count > 1 {
                    Button("Redistribute") {
                        mergeRoutes(on: area, preferRing: area.shapeClosed || routes.count >= 3)
                    }
                    .buttonStyle(.bordered)
                }
            }

            if peerRouteCount > 0 {
                Button("Merge \(peerRouteCount) nearby into a circle") {
                    mergeZoneRoutes(into: area)
                }
                .buttonStyle(.borderedProminent)
                .tint(.stravaOrange)
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
        let anchor = FloorPlanMath.centroid(of: area.floorPlanPoints())
        let step = Double(area.routes.count)
        let angle = step * 1.15
        let spot = PlanPoint(
            x: anchor.x + cos(angle) * 0.045,
            y: anchor.y + sin(angle) * 0.045
        )
        let route = GymRoute(
            grade: grade,
            colorName: draftColor.rawValue,
            x: spot.x,
            y: spot.y,
            discipline: logDiscipline,
            wall: area,
            updatedBy: name,
            updatedAt: .now,
            groupKey: nil
        )
        context.insert(route)
        persistMap()
    }

    private func mergeZoneRoutes(into area: GymArea) {
        let peers = wallsOnFloor.filter {
            $0.id != area.id && $0.displayZone == area.displayZone
        }
        let key = UUID().uuidString
        var absorbed: [GymRoute] = []
        for peer in peers {
            for route in peer.routes {
                route.wall = area
                route.groupKey = key
                absorbed.append(route)
            }
        }
        for route in area.routes {
            route.groupKey = key
        }
        guard absorbed.isEmpty == false || area.routes.count > 1 else { return }
        let outlines = ([area] + peers).map { $0.floorPlanPoints() }
        let routes = area.routes.sorted { $0.createdAt < $1.createdAt }
        let slots = FloorPlanMath.mergeRouteLayout(
            routeCounts: routes.count,
            wallOutlines: outlines
        )
        animateRouteLayout(routes, to: slots)
        persistMap()
    }

    private func mergeRoutes(on area: GymArea, preferRing: Bool) {
        let routes = area.routes.sorted { $0.createdAt < $1.createdAt }
        guard routes.isEmpty == false else {
            persistMap()
            return
        }
        let key = UUID().uuidString
        for route in routes {
            route.groupKey = key
        }
        let points = area.floorPlanPoints()
        let slots = preferRing
            ? FloorPlanMath.layoutRoutesMerged(count: routes.count, on: points, closed: area.shapeClosed)
            : FloorPlanMath.layoutRoutes(count: routes.count, on: points, closed: area.shapeClosed)
        animateRouteLayout(routes, to: slots)
        persistMap()
    }

    private func animateRouteLayout(_ routes: [GymRoute], to slots: [PlanPoint]) {
        let ids = Set(routes.map(\.id))
        mergingRouteIDs = ids
        for (index, route) in routes.enumerated() {
            guard index < slots.count else { continue }
            let target = slots[index]
            let delay = Double(index) * 0.045
            withAnimation(Self.routeSpring.delay(delay)) {
                route.setPin(x: target.x, y: target.y)
            }
        }
        let settle = 0.48 + Double(max(routes.count - 1, 0)) * 0.045 + 0.12
        DispatchQueue.main.asyncAfter(deadline: .now() + settle) {
            withAnimation(Self.routeSpring) {
                mergingRouteIDs = []
            }
        }
    }

    private func removeRoute(_ route: GymRoute, on area: GymArea) {
        let key = route.groupKey
        context.delete(route)
        if let key {
            let rest = area.routes.filter { $0.id != route.id && $0.groupKey == key }
            if rest.count <= 1 {
                for mate in rest {
                    mate.groupKey = nil
                }
            }
        }
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

private struct CircleSpot: Shape {
    var center: CGPoint
    var radius: CGFloat

    func path(in rect: CGRect) -> Path {
        Path(ellipseIn: CGRect(
            x: center.x - radius,
            y: center.y - radius,
            width: radius * 2,
            height: radius * 2
        ))
    }
}

/// Remembers where a pin drag started. A class so updates are visible inside the gesture
/// before SwiftUI flushes `@State`.
@Observable
private final class RouteDragSession {
    var routeID: UUID?
    var origin: PlanPoint?
    var fingerStart: PlanPoint?
    var lastFinger: PlanPoint?
    var fingerAtLock: PlanPoint?
    var grabDeltaX: Double = 0
    var grabDeltaY: Double = 0
    var movingCluster = false
    var groupKey: String?
    var clusterOrigins: [UUID: PlanPoint] = [:]
    var holdToken = 0
    private let haptic = UIImpactFeedbackGenerator(style: .medium)

    func beginTracking(_ route: GymRoute, finger: PlanPoint) {
        let tip = PlanPoint(x: route.x, y: route.y)
        routeID = route.id
        origin = tip
        fingerStart = finger
        lastFinger = finger
        grabDeltaX = tip.x - finger.x
        grabDeltaY = tip.y - finger.y
        fingerAtLock = nil
        movingCluster = false
        groupKey = nil
        clusterOrigins = [:]
        holdToken += 1
        haptic.prepare()
    }

    func cancelHold() {
        holdToken += 1
    }

    func playHaptic() {
        haptic.impactOccurred(intensity: 0.9)
    }

    func armCluster(_ routes: [GymRoute], finger: PlanPoint?) {
        movingCluster = true
        groupKey = routes.first?.groupKey
        fingerAtLock = finger
        clusterOrigins = Dictionary(uniqueKeysWithValues: routes.map {
            ($0.id, PlanPoint(x: $0.x, y: $0.y))
        })
    }

    func end() {
        routeID = nil
        origin = nil
        fingerStart = nil
        lastFinger = nil
        fingerAtLock = nil
        movingCluster = false
        groupKey = nil
        clusterOrigins = [:]
        holdToken += 1
    }
}

/// Google Maps–style teardrop. The view's center is the tip, so a cluster can
/// rotate each pin around that shared point while the grade stays upright.
private struct RouteMapPin: View {
    var grade: String
    var holdColor: HoldColor
    var highlighted: Bool = false
    var tipAngle: Angle = .zero

    static let pinWidth: CGFloat = 30
    static let pinHeight: CGFloat = 38

    /// Head center relative to the tip. Angle 0 keeps the head straight above the tip.
    static func headOffset(for angle: Angle) -> CGSize {
        let headRadius = min(pinWidth, pinHeight * 0.62) / 2
        let orbit = pinHeight - headRadius
        let radians = CGFloat(angle.radians)
        return CGSize(width: orbit * sin(radians), height: -orbit * cos(radians))
    }

    var body: some View {
        let head = Self.headOffset(for: tipAngle)
        ZStack {
            MapPinShape()
                .fill(Color(hold: holdColor))
                .overlay {
                    MapPinShape()
                        .strokeBorder(
                            highlighted ? Color.stravaOrange : Color.white.opacity(0.9),
                            lineWidth: highlighted ? 2 : 1
                        )
                }
                .shadow(color: .black.opacity(0.35), radius: highlighted ? 4 : 2, y: 1)
                .frame(width: Self.pinWidth, height: Self.pinHeight)
                .offset(y: -Self.pinHeight / 2)
                .rotationEffect(tipAngle)
                .allowsHitTesting(false)

            Text(grade)
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(holdColor.prefersDarkLabel ? Color.black : Color.white)
                .minimumScaleFactor(0.7)
                .lineLimit(1)
                .offset(x: head.width, y: head.height)
                .allowsHitTesting(false)
        }
        .frame(width: Self.pinWidth, height: Self.pinHeight)
        .accessibilityLabel(grade)
    }
}

/// Classic map-pin silhouette: round head, pointed tip at the bottom center.
private struct MapPinShape: InsettableShape {
    var insetAmount: CGFloat = 0

    func path(in rect: CGRect) -> Path {
        let r = rect.insetBy(dx: insetAmount, dy: insetAmount)
        let w = r.width
        let h = r.height
        let cx = r.midX
        let headRadius = min(w, h * 0.62) / 2
        let headCenterY = r.minY + headRadius
        let tipY = r.maxY
        let neckY = headCenterY + headRadius * 0.55

        var path = Path()
        path.addArc(
            center: CGPoint(x: cx, y: headCenterY),
            radius: headRadius,
            startAngle: .degrees(200),
            endAngle: .degrees(-20),
            clockwise: false
        )
        path.addLine(to: CGPoint(x: cx, y: tipY))
        path.addLine(to: CGPoint(x: cx - headRadius * 0.72, y: neckY))
        path.closeSubpath()
        return path
    }

    func inset(by amount: CGFloat) -> MapPinShape {
        MapPinShape(insetAmount: insetAmount + amount)
    }
}

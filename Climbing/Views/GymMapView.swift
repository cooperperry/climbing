import SwiftUI
import SwiftData

private enum FloorPlanTool: String, CaseIterable, Identifiable {
    case routes
    case move
    case editShape

    var id: String { rawValue }

    var label: String {
        switch self {
        case .routes: "Routes"
        case .move: "Move"
        case .editShape: "Shape"
        }
    }

    var systemImage: String {
        switch self {
        case .routes: "list.bullet"
        case .move: "arrow.up.and.down.and.arrow.left.and.right"
        case .editShape: "line.diagonal"
        }
    }
}

/// Overhead floor plan of a gym: wall segments you draw and drag, plus routes on each wall.
struct GymMapView: View {
    @Bindable var gym: ClimbGym
    @Environment(\.modelContext) private var context

    @Query(sort: \CustomGradeScale.createdAt)
    private var scales: [CustomGradeScale]
    @Query(sort: \ClimbGym.joinedAt)
    private var gyms: [ClimbGym]

    @State private var selectedArea: GymArea?
    @State private var shapeFocusArea: GymArea?
    @State private var climberName = ClimberIdentity.name
    @State private var showingAddWall = false
    @State private var wallName = ""
    @State private var logDiscipline: ClimbDiscipline = .boulder
    @State private var logGrade: String?
    @State private var draftColor: HoldColor = .blue
    @State private var dragOrigin: [UUID: CGPoint] = [:]
    @State private var shapeDragOrigin: [UUID: [PlanPoint]] = [:]
    @State private var canvasSize: CGSize = CGSize(width: 320, height: 340)
    @State private var floorTool: FloorPlanTool = .routes

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

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Draw wall lines, drag corners to reshape, tap a label for routes.")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            TextField("Your name on updates", text: $climberName)
                .textFieldStyle(.roundedBorder)
                .onChange(of: climberName) { _, value in
                    ClimberIdentity.name = value
                }

            Picker("Tool", selection: $floorTool) {
                ForEach(FloorPlanTool.allCases) { tool in
                    Label(tool.label, systemImage: tool.systemImage).tag(tool)
                }
            }
            .pickerStyle(.segmented)

            if floorTool == .editShape, let focus = shapeFocusArea {
                shapeToolbar(for: focus)
            }

            floorPlan
                .frame(maxWidth: .infinity)
                .frame(height: 340)
        }
        .padding()
        .navigationTitle(gym.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Add wall", systemImage: "plus") { showingAddWall = true }
            }
        }
        .onAppear {
            prepareGrades()
            climberName = ClimberIdentity.name
        }
        .onChange(of: logDiscipline) { _, _ in
            logGrade = scale?.grades.first
        }
        .onChange(of: floorTool) { _, tool in
            if tool != .editShape { shapeFocusArea = nil }
        }
        .alert("Add a wall", isPresented: $showingAddWall) {
            TextField("Cave, Center, 360 A…", text: $wallName)
            Button("Add") { addWall() }
            Button("Cancel", role: .cancel) { wallName = "" }
        } message: {
            Text("Name a section, then drag its line into place on the floor plan.")
        }
        .sheet(item: $selectedArea) { area in
            NavigationStack {
                ScrollView {
                    routeList(for: area)
                        .padding()
                }
                .navigationTitle(area.name)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") { selectedArea = nil }
                    }
                }
            }
            .presentationDetents([.medium, .large])
        }
    }

    @ViewBuilder
    private func shapeToolbar(for area: GymArea) -> some View {
        HStack(spacing: 8) {
            Text(area.name)
                .font(.caption.bold())
                .lineLimit(1)
            Spacer()
            Button("Extend line", systemImage: "plus") { extendShape(on: area) }
                .font(.caption.bold())
            Button("Done", systemImage: "checkmark") {
                shapeFocusArea = nil
                floorTool = .routes
            }
            .font(.caption.bold())
        }
    }

    private var floorPlan: some View {
        GeometryReader { geo in
            let size = geo.size
            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color.black)

                if walls.isEmpty {
                    Text("Tap + and add Cave, Center, 360…")
                        .font(.subheadline.bold())
                        .foregroundStyle(.white.opacity(0.75))
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .padding()
                }

                ForEach(walls) { area in
                    wallSegment(area, in: size)
                }

                ForEach(walls) { area in
                    wallLabel(area, in: size)
                }
            }
            .coordinateSpace(name: "floor")
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .onAppear { canvasSize = size }
            .onChange(of: size.width) { _, _ in canvasSize = size }
            .onChange(of: size.height) { _, _ in canvasSize = size }
        }
    }

    private func wallSegment(_ area: GymArea, in size: CGSize) -> some View {
        let points = area.floorPlanPoints()
        let focused = shapeFocusArea?.id == area.id
        let stroke = focused ? Color.stravaOrange : Color.white.opacity(0.85)
        return ZStack {
            Path { path in
                guard let first = points.first else { return }
                let start = pixel(first, in: size)
                path.move(to: start)
                for pt in points.dropFirst() {
                    path.addLine(to: pixel(pt, in: size))
                }
            }
            .stroke(stroke, style: StrokeStyle(lineWidth: focused ? 5 : 3, lineCap: .round, lineJoin: .round))

            if floorTool == .editShape, focused {
                ForEach(Array(points.enumerated()), id: \.offset) { index, pt in
                    vertexHandle(area: area, index: index, normalized: pt, in: size)
                }
            }
        }
        .contentShape(Path { path in
            guard let first = points.first else { return }
            path.move(to: pixel(first, in: size))
            for pt in points.dropFirst() {
                path.addLine(to: pixel(pt, in: size))
            }
        })
        .gesture(segmentDragGesture(area: area, points: points))
    }

    private func vertexHandle(area: GymArea, index: Int, normalized: PlanPoint, in size: CGSize) -> some View {
        let pos = pixel(normalized, in: size)
        return Circle()
            .fill(Color.stravaOrange)
            .frame(width: 22, height: 22)
            .overlay { Circle().strokeBorder(Color.white, lineWidth: 2) }
            .position(pos)
            .gesture(
                DragGesture(minimumDistance: 0, coordinateSpace: .named("floor"))
                    .onChanged { value in
                        var pts = resolvedStoredPoints(for: area)
                        guard index < pts.count else { return }
                        let board = canvasSize == .zero ? size : canvasSize
                        let nx = value.location.x / max(board.width, 1)
                        let ny = value.location.y / max(board.height, 1)
                        let clamped = GymJoinMath.clampPin(x: nx, y: ny)
                        pts[index] = PlanPoint(x: clamped.x, y: clamped.y)
                        area.setFloorPlanPoints(pts)
                    }
                    .onEnded { _ in
                        persistMap()
                    }
            )
    }

    private func segmentDragGesture(area: GymArea, points: [PlanPoint]) -> some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .named("floor"))
            .onChanged { value in
                guard floorTool == .move || (floorTool == .editShape && shapeFocusArea?.id == area.id) else { return }
                let originKey = area.id
                if shapeDragOrigin[originKey] == nil {
                    shapeDragOrigin[originKey] = resolvedStoredPoints(for: area)
                }
                guard let origin = shapeDragOrigin[originKey] else { return }
                let board = canvasSize == .zero ? CGSize(width: 320, height: 340) : canvasSize
                let dx = value.translation.width / max(board.width, 1)
                let dy = value.translation.height / max(board.height, 1)
                area.setFloorPlanPoints(FloorPlanMath.translate(points: origin, dx: dx, dy: dy))
            }
            .onEnded { value in
                shapeDragOrigin[area.id] = nil
                let moved = hypot(value.translation.width, value.translation.height) >= 8
                if floorTool == .move, moved == false {
                    openRoutes(for: area)
                } else if moved {
                    persistMap()
                } else if floorTool == .editShape {
                    shapeFocusArea = area
                }
            }
    }

    private func wallLabel(_ area: GymArea, in size: CGSize) -> some View {
        let center = FloorPlanMath.centroid(of: area.floorPlanPoints())
        let selected = selectedArea?.id == area.id
        let width = max(size.width, 1)
        let height = max(size.height, 1)
        return VStack(spacing: 2) {
            Text(area.name)
                .font(.caption.bold())
                .lineLimit(2)
                .multilineTextAlignment(.center)
            Text(area.routes.count == 1 ? "1 route" : "\(area.routes.count) routes")
                .font(.caption2)
                .foregroundStyle(selected ? Color.black.opacity(0.7) : Color.white.opacity(0.7))
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .frame(minWidth: 72)
        .background(selected ? Color.stravaOrange : Color.white.opacity(0.16), in: RoundedRectangle(cornerRadius: 10))
        .foregroundStyle(selected ? Color.black : Color.white)
        .fixedSize()
        .position(x: center.x * width, y: center.y * height)
        .gesture(
            DragGesture(minimumDistance: 0, coordinateSpace: .named("floor"))
                .onChanged { value in
                    guard floorTool == .move else { return }
                    let origin = dragOrigin[area.id] ?? CGPoint(x: area.x, y: area.y)
                    if dragOrigin[area.id] == nil {
                        dragOrigin[area.id] = origin
                        shapeDragOrigin[area.id] = resolvedStoredPoints(for: area)
                    }
                    let board = canvasSize == .zero ? size : canvasSize
                    let dx = value.translation.width / max(board.width, 1)
                    let dy = value.translation.height / max(board.height, 1)
                    if let base = shapeDragOrigin[area.id] {
                        area.setFloorPlanPoints(FloorPlanMath.translate(points: base, dx: dx, dy: dy))
                    } else {
                        let clamped = GymJoinMath.clampPin(x: origin.x + dx, y: origin.y + dy)
                        area.x = clamped.x
                        area.y = clamped.y
                    }
                }
                .onEnded { value in
                    dragOrigin[area.id] = nil
                    shapeDragOrigin[area.id] = nil
                    if floorTool == .move {
                        if hypot(value.translation.width, value.translation.height) < 8 {
                            openRoutes(for: area)
                        } else {
                            persistMap()
                        }
                    } else if floorTool == .routes {
                        if hypot(value.translation.width, value.translation.height) < 8 {
                            openRoutes(for: area)
                        }
                    } else if floorTool == .editShape {
                        if hypot(value.translation.width, value.translation.height) < 8 {
                            shapeFocusArea = area
                        } else {
                            persistMap()
                        }
                    }
                }
        )
        .simultaneousGesture(
            TapGesture().onEnded {
                switch floorTool {
                case .routes:
                    openRoutes(for: area)
                case .editShape:
                    shapeFocusArea = area
                case .move:
                    break
                }
            }
        )
    }

    private func pixel(_ point: PlanPoint, in size: CGSize) -> CGPoint {
        CGPoint(x: point.x * max(size.width, 1), y: point.y * max(size.height, 1))
    }

    private func resolvedStoredPoints(for area: GymArea) -> [PlanPoint] {
        let stored = area.shapePoints
        if stored.isEmpty {
            return area.floorPlanPoints()
        }
        return stored
    }

    private func extendShape(on area: GymArea) {
        var pts = resolvedStoredPoints(for: area)
        pts.append(FloorPlanMath.extendedPoint(after: pts))
        area.setFloorPlanPoints(pts)
        persistMap()
    }

    private func routeList(for area: GymArea) -> some View {
        let routes = area.routes.sorted { $0.createdAt < $1.createdAt }
        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(area.name)
                    .font(.headline)
                Spacer()
                if gym.currentWallName == area.name {
                    Text("Watch")
                        .font(.caption.bold())
                        .foregroundStyle(.stravaOrange)
                }
                Button("Edit shape") {
                    selectedArea = nil
                    floorTool = .editShape
                    shapeFocusArea = area
                }
                .font(.caption.bold())
                Button("Remove wall", role: .destructive) { removeWall(area) }
                    .font(.caption.bold())
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
                        Button {
                            draftColor = color
                        } label: {
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
        .padding()
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 16))
    }

    private func openRoutes(for area: GymArea) {
        selectedArea = area
        gym.currentWallName = area.name
        for item in gyms { item.isCurrent = (item.id == gym.id) }
        persistMap()
    }

    private func persistMap() {
        try? context.save()
        PhoneWatchBridge.shared.publishSnapshot()
    }

    private func addWall() {
        let raw = wallName
        wallName = ""
        guard GymJoinMath.isUsableName(raw) else { return }
        let slot = GymJoinMath.nextGridSlot(existingCount: gym.areas.count)
        let anchor = PlanPoint(x: slot.x, y: slot.y)
        let segment = FloorPlanMath.defaultSegment(anchor: anchor)
        let area = GymArea(
            name: raw.trimmingCharacters(in: .whitespacesAndNewlines),
            x: slot.x,
            y: slot.y,
            gym: gym,
            shapePointsData: FloorPlanMath.encode(segment)
        )
        context.insert(area)
        try? context.save()
        shapeFocusArea = area
        floorTool = .editShape
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

    private func removeWall(_ area: GymArea) {
        let name = area.name
        if selectedArea?.id == area.id { selectedArea = nil }
        if shapeFocusArea?.id == area.id { shapeFocusArea = nil }
        context.delete(area)
        if gym.currentWallName == name {
            gym.currentWallName = gym.areas.first?.name
            selectedArea = gym.areas.first
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

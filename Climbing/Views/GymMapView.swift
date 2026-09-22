import SwiftUI
import SwiftData

/// Overhead floor plan of a gym: named walls you drag into place, and the
/// current set of routes on each wall. Each route records who set it and when.
struct GymMapView: View {
    @Bindable var gym: ClimbGym
    @Environment(\.modelContext) private var context

    @Query(sort: \CustomGradeScale.createdAt)
    private var scales: [CustomGradeScale]
    @Query(sort: \ClimbGym.joinedAt)
    private var gyms: [ClimbGym]

    @State private var selectedArea: GymArea?
    @State private var climberName = ClimberIdentity.name
    @State private var showingAddWall = false
    @State private var wallName = ""
    @State private var logDiscipline: ClimbDiscipline = .boulder
    @State private var logGrade: String?
    @State private var draftColor: HoldColor = .blue
    @State private var dragOrigin: [UUID: CGPoint] = [:]

    private var scale: CustomGradeScale? {
        let kind: GradeScaleKind = logDiscipline.usesRopeGrades ? .yds : .boulderVScale
        return scales.first { $0.kind == kind } ?? scales.first
    }

    private var walls: [GymArea] {
        gym.areas.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Lay the walls out like the gym's floor plan. Routes live on a wall, and each one shows who set it and when.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                TextField("Your name on updates", text: $climberName)
                    .textFieldStyle(.roundedBorder)
                    .onChange(of: climberName) { _, value in
                        ClimberIdentity.name = value
                    }

                floorPlan

                if let selectedArea {
                    routeList(for: selectedArea)
                }
            }
            .padding()
        }
        .navigationTitle(gym.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Add wall", systemImage: "plus") { showingAddWall = true }
            }
        }
        .onAppear {
            prepareGrades()
            if selectedArea == nil, let name = gym.currentWallName {
                selectedArea = walls.first { $0.name == name }
            }
        }
        .onChange(of: logDiscipline) { _, _ in
            logGrade = scale?.grades.first
        }
        .alert("Add a wall", isPresented: $showingAddWall) {
            TextField("Cave, Center, 360 A…", text: $wallName)
            Button("Add") { addWall() }
            Button("Cancel", role: .cancel) { wallName = "" }
        } message: {
            Text("Name a section from the gym's floor plan, then drag it into place.")
        }
    }

    private var floorPlan: some View {
        GeometryReader { geo in
            ZStack {
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color.black)
                if walls.isEmpty {
                    Text("Add the walls from the gym's drawing")
                        .font(.subheadline.bold())
                        .foregroundStyle(.white.opacity(0.7))
                        .multilineTextAlignment(.center)
                        .padding()
                }
                ForEach(walls) { area in
                    wallMark(area, in: geo.size)
                }
            }
        }
        .frame(height: 380)
    }

    private func wallMark(_ area: GymArea, in size: CGSize) -> some View {
        let selected = selectedArea?.id == area.id
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
        .background(selected ? Color.stravaOrange : Color.white.opacity(0.14), in: RoundedRectangle(cornerRadius: 10))
        .foregroundStyle(selected ? Color.black : Color.white)
        .position(x: area.x * size.width, y: area.y * size.height)
        .onTapGesture { select(area) }
        .gesture(
            DragGesture(minimumDistance: 8)
                .onChanged { value in
                    let origin = dragOrigin[area.id] ?? CGPoint(x: area.x, y: area.y)
                    if dragOrigin[area.id] == nil {
                        dragOrigin[area.id] = origin
                    }
                    let clamped = GymJoinMath.clampPin(
                        x: origin.x + value.translation.width / max(size.width, 1),
                        y: origin.y + value.translation.height / max(size.height, 1)
                    )
                    area.x = clamped.x
                    area.y = clamped.y
                }
                .onEnded { _ in
                    dragOrigin[area.id] = nil
                    try? context.save()
                    PhoneWatchBridge.shared.publishSnapshot()
                }
        )
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
                .disabled(logGrade == nil || ClimberIdentity.name.count < 2)
            if ClimberIdentity.name.count < 2 {
                Text("Add your name so other climbers can see who set the route.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 16))
    }

    private func select(_ area: GymArea) {
        selectedArea = area
        gym.currentWallName = area.name
        for item in gyms { item.isCurrent = (item.id == gym.id) }
        try? context.save()
        PhoneWatchBridge.shared.publishSnapshot()
    }

    private func addWall() {
        let raw = wallName
        wallName = ""
        guard GymJoinMath.isUsableName(raw) else { return }
        let slot = GymJoinMath.nextGridSlot(existingCount: gym.areas.count)
        let area = GymArea(
            name: raw.trimmingCharacters(in: .whitespacesAndNewlines),
            x: slot.x,
            y: slot.y,
            gym: gym
        )
        context.insert(area)
        select(area)
    }

    private func addRoute(on area: GymArea) {
        guard let grade = logGrade, ClimberIdentity.name.count >= 2 else { return }
        let index = area.routes.count
        let route = GymRoute(
            grade: grade,
            colorName: draftColor.rawValue,
            x: 0.5,
            y: min(0.9, 0.18 + Double(index) * 0.12),
            discipline: logDiscipline,
            wall: area,
            updatedBy: ClimberIdentity.name,
            updatedAt: .now
        )
        context.insert(route)
        select(area)
    }

    private func removeRoute(_ route: GymRoute) {
        context.delete(route)
        try? context.save()
        PhoneWatchBridge.shared.publishSnapshot()
    }

    private func removeWall(_ area: GymArea) {
        let name = area.name
        if selectedArea?.id == area.id { selectedArea = nil }
        context.delete(area)
        if gym.currentWallName == name {
            gym.currentWallName = gym.areas.first?.name
            selectedArea = gym.areas.first
        }
        try? context.save()
        PhoneWatchBridge.shared.publishSnapshot()
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

import SwiftUI
import SwiftData
import PhotosUI

/// Floor-plan map for one gym. Drop walls, move them, and log a send on a pin.
struct GymMapView: View {
    @Bindable var gym: ClimbGym
    @Environment(\.modelContext) private var context

    @Query(sort: \CustomGradeScale.createdAt)
    private var scales: [CustomGradeScale]
    @Query(
        filter: #Predicate<ClimbingSession> { $0.endTime == nil },
        sort: \ClimbingSession.startTime,
        order: .reverse
    )
    private var activeSessions: [ClimbingSession]
    @Query(sort: \ClimbLog.loggedAt, order: .reverse)
    private var allLogs: [ClimbLog]
    @Query(sort: \ClimbGym.joinedAt)
    private var gyms: [ClimbGym]

    @State private var editing = false
    @State private var photoItem: PhotosPickerItem?
    @State private var pendingPin: CGPoint?
    @State private var newAreaName = ""
    @State private var showingName = false
    @State private var selectedArea: GymArea?
    @State private var logDiscipline: ClimbDiscipline = .boulder
    @State private var logGrade: String?
    @State private var sendTrigger = 0
    @State private var pendingSize: CGSize = .zero

    private var scale: CustomGradeScale? {
        let kind: GradeScaleKind = logDiscipline.usesRopeGrades ? .yds : .boulderVScale
        return scales.first { $0.kind == kind } ?? scales.first
    }

    private var gymLogs: [ClimbLog] {
        allLogs.filter { $0.gym?.id == gym.id }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                map
                if let selectedArea {
                    logCard(for: selectedArea)
                } else {
                    Text(editing ? "Tap the map to add a wall. Drag a pin to move it." : "Tap a wall to log a send there.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            .padding()
        }
        .navigationTitle(gym.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button(editing ? "Done" : "Edit map") { editing.toggle() }
            }
        }
        .onAppear { prepareGrades() }
        .onChange(of: logDiscipline) { _, _ in
            logGrade = scale?.grades.first
        }
        .onChange(of: photoItem) { _, item in
            Task { await loadPhoto(item) }
        }
        .alert("Wall name", isPresented: $showingName) {
            TextField("Cave, Comp, Moonboard…", text: $newAreaName)
            Button("Add") { addPendingArea() }
            Button("Cancel", role: .cancel) {
                pendingPin = nil
                newAreaName = ""
            }
        }
        .sensoryFeedback(.success, trigger: sendTrigger)
    }

    private var map: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Map")
                    .font(.headline)
                Spacer()
                PhotosPicker(selection: $photoItem, matching: .images) {
                    Label(gym.mapImageData == nil ? "Add floor plan" : "Change photo", systemImage: "photo")
                        .font(.caption.bold())
                }
            }

            GeometryReader { geo in
                ZStack {
                    mapBackground
                    ForEach(gym.areas) { area in
                        pin(area, in: geo.size)
                    }
                }
                .coordinateSpace(name: "gymMap")
                .contentShape(Rectangle())
                .onTapGesture { location in
                    handleTap(location, size: geo.size)
                }
            }
            .frame(height: 280)
            .clipShape(RoundedRectangle(cornerRadius: 16))
        }
    }

    @ViewBuilder
    private var mapBackground: some View {
        if let data = gym.mapImageData, let image = UIImage(data: data) {
            Image(uiImage: image)
                .resizable()
                .scaledToFit()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(.secondarySystemBackground))
                .overlay {
                    VStack(spacing: 6) {
                        Image(systemName: "map")
                            .font(.title)
                        Text("Gym floor")
                            .font(.caption.bold())
                    }
                    .foregroundStyle(.secondary)
                }
        }
    }

    private func pin(_ area: GymArea, in size: CGSize) -> some View {
        let selected = selectedArea?.id == area.id
        return Text(area.name)
            .font(.caption2.bold())
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(selected ? Color.stravaOrange : Color.black.opacity(0.75), in: Capsule())
            .foregroundStyle(.white)
            .position(x: area.x * size.width, y: area.y * size.height)
            .gesture(
                DragGesture(coordinateSpace: .named("gymMap"))
                    .onChanged { value in
                        guard editing else { return }
                        let clamped = GymJoinMath.clampPin(
                            x: value.location.x / max(size.width, 1),
                            y: value.location.y / max(size.height, 1)
                        )
                        area.x = clamped.x
                        area.y = clamped.y
                    }
                    .onEnded { _ in
                        guard editing else { return }
                        try? context.save()
                    }
            )
            .onTapGesture {
                if editing == false { selectedArea = area }
            }
    }

    private func handleTap(_ location: CGPoint, size: CGSize) {
        if editing {
            pendingPin = location
            newAreaName = ""
            showingName = true
            pendingSize = size
            return
        }
        selectedArea = nearestArea(to: location, in: size)
    }

    private func nearestArea(to location: CGPoint, in size: CGSize) -> GymArea? {
        gym.areas.min(by: { lhs, rhs in
            distance(location, pin: lhs, size: size) < distance(location, pin: rhs, size: size)
        }).flatMap { area in
            distance(location, pin: area, size: size) < 44 ? area : nil
        }
    }

    private func distance(_ location: CGPoint, pin: GymArea, size: CGSize) -> CGFloat {
        let dx = location.x - pin.x * size.width
        let dy = location.y - pin.y * size.height
        return sqrt(dx * dx + dy * dy)
    }

    private func addPendingArea() {
        guard let pendingPin, GymJoinMath.isUsableName(newAreaName) else { return }
        let size = pendingSize
        let clamped = GymJoinMath.clampPin(
            x: pendingPin.x / max(size.width, 1),
            y: pendingPin.y / max(size.height, 1)
        )
        let area = GymArea(
            name: newAreaName.trimmingCharacters(in: .whitespacesAndNewlines),
            x: clamped.x,
            y: clamped.y,
            gym: gym
        )
        context.insert(area)
        try? context.save()
        selectedArea = area
        self.pendingPin = nil
        newAreaName = ""
    }

    private func logCard(for area: GymArea) -> some View {
        let rows = gymLogs.filter { $0.areaName == area.name }
        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(area.name)
                    .font(.headline)
                Spacer()
                if editing {
                    Button("Remove wall", role: .destructive) {
                        if selectedArea?.id == area.id { selectedArea = nil }
                        context.delete(area)
                        try? context.save()
                    }
                    .font(.caption.bold())
                }
            }

            Picker("Type", selection: $logDiscipline) {
                ForEach(ClimbDiscipline.allCases) { item in
                    Text(item.displayName).tag(item)
                }
            }
            .pickerStyle(.segmented)

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

            HStack {
                Button("First try") { log(outcome: .flash, attempts: 1, area: area) }
                    .tint(.yellow)
                Button("Topped") { log(outcome: .send, attempts: 2, area: area) }
                    .tint(.green)
            }
            .buttonStyle(.borderedProminent)
            .disabled(logGrade == nil)

            if rows.isEmpty {
                Text("No sends on this wall yet")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(rows.prefix(8)) { entry in
                    HStack {
                        Text(entry.gradeLabel).bold()
                        Text(entry.outcome.displayName)
                            .foregroundStyle(.secondary)
                        Spacer()
                    }
                    .font(.subheadline)
                }
            }
        }
        .padding()
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 16))
    }

    private func log(outcome: ClimbOutcome, attempts: Int, area: GymArea) {
        guard let grade = logGrade else { return }
        for item in gyms { item.isCurrent = (item.id == gym.id) }
        let entry = ClimbLog(
            gradeLabel: grade,
            attempts: attempts,
            outcome: outcome,
            discipline: logDiscipline,
            gym: gym,
            areaName: area.name,
            session: todaySession(),
            gradeScale: scale
        )
        context.insert(entry)
        try? context.save()
        sendTrigger += 1
    }

    private func todaySession() -> ClimbingSession {
        if let existing = activeSessions.first { return existing }
        let session = ClimbingSession()
        context.insert(session)
        try? context.save()
        return session
    }

    private func prepareGrades() {
        if scales.contains(where: { $0.kind == .boulderVScale }) == false {
            context.insert(CustomGradeScale(template: .standardVScale(), isDefault: true))
        }
        if scales.contains(where: { $0.kind == .yds }) == false {
            context.insert(CustomGradeScale(template: .standardYDS()))
        }
        try? context.save()
        if logGrade == nil {
            logGrade = scale?.grades.first
        }
    }

    private func loadPhoto(_ item: PhotosPickerItem?) async {
        guard let item, let data = try? await item.loadTransferable(type: Data.self) else { return }
        let image = UIImage(data: data)
        gym.mapImageData = image?.jpegData(compressionQuality: 0.7) ?? data
        try? context.save()
    }
}

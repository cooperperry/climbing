import SwiftUI
import SwiftData
import PhotosUI
import UIKit

/// A gym mapped as the walls you've stood in front of — snap the wall, name it,
/// log sends on that photo. No floor plan required.
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

    @State private var showingAdd = false
    @State private var showingCamera = false
    @State private var photoItem: PhotosPickerItem?
    @State private var draftImage: UIImage?
    @State private var draftName = ""
    @State private var selectedArea: GymArea?
    @State private var logDiscipline: ClimbDiscipline = .boulder
    @State private var logGrade: String?
    @State private var sendTrigger = 0
    @FocusState private var nameFocused: Bool

    private var scale: CustomGradeScale? {
        let kind: GradeScaleKind = logDiscipline.usesRopeGrades ? .yds : .boulderVScale
        return scales.first { $0.kind == kind } ?? scales.first
    }

    private var gymLogs: [ClimbLog] {
        allLogs.filter { $0.gym?.id == gym.id }
    }

    private var walls: [GymArea] {
        gym.areas.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if walls.isEmpty {
                    emptyBoard
                } else {
                    wallBoard
                }
                if let selectedArea {
                    logCard(for: selectedArea)
                }
            }
            .padding()
        }
        .navigationTitle(gym.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Add wall", systemImage: "camera.fill") { openAdd() }
            }
        }
        .onAppear { prepareGrades() }
        .onChange(of: logDiscipline) { _, _ in
            logGrade = scale?.grades.first
        }
        .onChange(of: photoItem) { _, item in
            Task { await loadLibraryPhoto(item) }
        }
        .sheet(isPresented: $showingAdd, onDismiss: resetDraft) {
            addWallSheet
        }
        .fullScreenCover(isPresented: $showingCamera) {
            CameraPicker(image: $draftImage)
                .ignoresSafeArea()
        }
        .sensoryFeedback(.success, trigger: sendTrigger)
    }

    private var emptyBoard: some View {
        VStack(spacing: 14) {
            Image(systemName: "camera.viewfinder")
                .font(.system(size: 44))
                .foregroundStyle(.stravaOrange)
            Text("Walk up to a wall and add it")
                .font(.title3.bold())
                .multilineTextAlignment(.center)
            Text("Snap the wall in front of you and give it a name. That photo is the map — no floor plan needed.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button {
                openAdd()
            } label: {
                Label("Add this wall", systemImage: "camera.fill")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
            }
            .buttonStyle(.borderedProminent)
            .tint(.stravaOrange)
        }
        .frame(maxWidth: .infinity)
        .padding(24)
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 20))
    }

    private var wallBoard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Walls")
                .font(.headline)
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
                ForEach(walls) { area in
                    wallTile(area)
                }
                Button {
                    openAdd()
                } label: {
                    VStack(spacing: 8) {
                        Image(systemName: "plus")
                            .font(.title)
                        Text("Add wall")
                            .font(.caption.bold())
                    }
                    .frame(maxWidth: .infinity, minHeight: 140)
                    .foregroundStyle(.secondary)
                    .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 16))
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func wallTile(_ area: GymArea) -> some View {
        let selected = selectedArea?.id == area.id
        let sends = gymLogs.filter { $0.areaName == area.name && $0.outcome.isCompletion }.count
        return Button {
            selectedArea = area
        } label: {
            VStack(alignment: .leading, spacing: 0) {
                wallPhoto(area)
                    .frame(height: 120)
                    .clipped()
                VStack(alignment: .leading, spacing: 2) {
                    Text(area.name)
                        .font(.subheadline.bold())
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    Text(sends == 1 ? "1 send" : "\(sends) sends")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(8)
            }
            .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 16))
            .overlay {
                RoundedRectangle(cornerRadius: 16)
                    .strokeBorder(selected ? Color.stravaOrange : .clear, lineWidth: 3)
            }
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func wallPhoto(_ area: GymArea) -> some View {
        if let data = area.photoData, let image = UIImage(data: data) {
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
        } else {
            ZStack {
                Color(.tertiarySystemFill)
                Image(systemName: "photo")
                    .font(.title)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var addWallSheet: some View {
        NavigationStack {
            VStack(spacing: 16) {
                ZStack {
                    RoundedRectangle(cornerRadius: 16)
                        .fill(Color(.secondarySystemBackground))
                    if let draftImage {
                        Image(uiImage: draftImage)
                            .resizable()
                            .scaledToFill()
                            .clipShape(RoundedRectangle(cornerRadius: 16))
                    } else {
                        VStack(spacing: 8) {
                            Image(systemName: "camera.viewfinder")
                                .font(.largeTitle)
                            Text("Photo the wall you're on")
                                .font(.subheadline.bold())
                        }
                        .foregroundStyle(.secondary)
                    }
                }
                .frame(height: 220)
                .clipped()

                HStack {
                    if UIImagePickerController.isSourceTypeAvailable(.camera) {
                        Button {
                            showingCamera = true
                        } label: {
                            Label("Take photo", systemImage: "camera.fill")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.stravaOrange)
                    }
                    PhotosPicker(selection: $photoItem, matching: .images) {
                        Label("Library", systemImage: "photo")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                }

                TextField("Name this wall", text: $draftName)
                    .textFieldStyle(.roundedBorder)
                    .focused($nameFocused)
                    .submitLabel(.done)

                Text("Cave, Comp, Moonboard, the slab on the right…")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)

                Spacer()
            }
            .padding()
            .navigationTitle("Add wall")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { showingAdd = false }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { saveWall() }
                        .disabled(GymJoinMath.isUsableName(draftName) == false)
                }
            }
            .onAppear { nameFocused = true }
        }
        .presentationDetents([.medium, .large])
    }

    private func logCard(for area: GymArea) -> some View {
        let rows = gymLogs.filter { $0.areaName == area.name }
        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(area.name)
                    .font(.headline)
                Spacer()
                Button("Remove", role: .destructive) {
                    if selectedArea?.id == area.id { selectedArea = nil }
                    context.delete(area)
                    try? context.save()
                }
                .font(.caption.bold())
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

    private func openAdd() {
        resetDraft()
        showingAdd = true
    }

    private func resetDraft() {
        draftName = ""
        draftImage = nil
        photoItem = nil
    }

    private func saveWall() {
        guard GymJoinMath.isUsableName(draftName) else { return }
        let slot = GymJoinMath.nextGridSlot(existingCount: gym.areas.count)
        let area = GymArea(
            name: draftName.trimmingCharacters(in: .whitespacesAndNewlines),
            x: slot.x,
            y: slot.y,
            gym: gym,
            photoData: draftImage?.jpegData(compressionQuality: 0.7)
        )
        context.insert(area)
        try? context.save()
        selectedArea = area
        showingAdd = false
        sendTrigger += 1
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

    private func loadLibraryPhoto(_ item: PhotosPickerItem?) async {
        guard let item, let data = try? await item.loadTransferable(type: Data.self) else { return }
        draftImage = UIImage(data: data)
    }
}

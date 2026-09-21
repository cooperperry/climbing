import SwiftUI
import SwiftData

/// Join or create a gym, then open its map to drop walls and log sends.
struct GymListView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \ClimbGym.joinedAt, order: .reverse)
    private var gyms: [ClimbGym]
    @State private var joinText = ""
    @State private var showingJoin = false

    private var current: ClimbGym? { gyms.first(where: \.isCurrent) }

    var body: some View {
        NavigationStack {
            Group {
                if gyms.isEmpty {
                    ContentUnavailableView {
                        Label("No gym yet", systemImage: "building.2")
                    } description: {
                        Text("Join the gym you're climbing at. Walk up to a wall, snap it, and log sends on that photo.")
                    } actions: {
                        Button("Join a gym") { showingJoin = true }
                    }
                } else {
                    List {
                        if let current {
                            Section("Climbing here") {
                                NavigationLink(value: current.id) {
                                    gymRow(current, showHere: false)
                                }
                            }
                        }
                        Section("Gyms") {
                            ForEach(gyms) { gym in
                                NavigationLink(value: gym.id) {
                                    gymRow(gym, showHere: true)
                                }
                                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                    Button("I'm here") { setCurrent(gym) }
                                        .tint(.stravaOrange)
                                    Button("Leave", role: .destructive) { leave(gym) }
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Gyms")
            .navigationDestination(for: UUID.self) { id in
                if let gym = gyms.first(where: { $0.id == id }) {
                    GymMapView(gym: gym)
                }
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Join", systemImage: "plus") { showingJoin = true }
                }
            }
            .alert("Join a gym", isPresented: $showingJoin) {
                TextField("Gym name", text: $joinText)
                Button("Join") { join() }
                Button("Cancel", role: .cancel) { joinText = "" }
            } message: {
                Text("Use the gym's name. If it's already on this phone, you'll join that map.")
            }
        }
    }

    private func gymRow(_ gym: ClimbGym, showHere: Bool) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(gym.name)
                    .font(.headline)
                if showHere, gym.isCurrent {
                    Text("HERE")
                        .font(.caption2.bold())
                        .foregroundStyle(.white)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.stravaOrange, in: Capsule())
                }
            }
            Text("\(gym.areas.count) walls · \(gym.logs.filter(\.outcome.isCompletion).count) sends")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func join() {
        let raw = joinText
        joinText = ""
        if let match = gyms.first(where: { GymJoinMath.codesMatch($0.joinCode, raw) })
            ?? gyms.first(where: { GymJoinMath.namesMatch($0.name, raw) }) {
            setCurrent(match)
            return
        }
        guard GymJoinMath.isUsableName(raw) else { return }
        let gym = ClimbGym(
            name: raw.trimmingCharacters(in: .whitespacesAndNewlines),
            isCurrent: true
        )
        for other in gyms { other.isCurrent = false }
        context.insert(gym)
        try? context.save()
    }

    private func setCurrent(_ gym: ClimbGym) {
        for item in gyms { item.isCurrent = (item.id == gym.id) }
        try? context.save()
    }

    private func leave(_ gym: ClimbGym) {
        context.delete(gym)
        try? context.save()
    }
}

#Preview {
    GymListView()
        .modelContainer(
            for: [ClimbGym.self, GymArea.self, ClimbLog.self, ClimbingSession.self, CustomGradeScale.self],
            inMemory: true
        )
}

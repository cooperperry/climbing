import AppIntents
import Foundation

/// A gym the climber has joined, for picking “I'm here” from Shortcuts.
struct GymEntity: AppEntity, Identifiable, Hashable {
    static var typeDisplayRepresentation: TypeDisplayRepresentation {
        TypeDisplayRepresentation(name: "Gym")
    }

    static var defaultQuery = GymEntityQuery()

    var id: UUID
    var name: String

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(name)")
    }
}

struct GymEntityQuery: EntityStringQuery {
    func entities(for identifiers: [UUID]) async throws -> [GymEntity] {
        await MainActor.run {
            PhoneWatchBridge.shared.gymEntities(matching: identifiers)
        }
    }

    func suggestedEntities() async throws -> [GymEntity] {
        await MainActor.run {
            PhoneWatchBridge.shared.gymEntities()
        }
    }

    func entities(matching string: String) async throws -> [GymEntity] {
        let all = try await suggestedEntities()
        return all.filter { GymJoinMath.namesMatch($0.name, string) || $0.name.localizedCaseInsensitiveContains(string) }
    }
}

/// Starts a Climber session and the Watch workout. Pair this with a Shortcuts
/// Arrive automation at your gym.
struct StartClimbingWorkoutIntent: AppIntent {
    static var title: LocalizedStringResource = "Start Climbing Workout"
    static var description = IntentDescription(
        "Starts a climbing session and the Watch workout. Pick a gym to mark it as I'm here so sends land on that map."
    )
    static var openAppWhenRun: Bool { true }

    @Parameter(
        title: "Gym",
        description: "Optional. Marks this gym as I'm here."
    )
    var gym: GymEntity?

    static var parameterSummary: some ParameterSummary {
        Summary("Start climbing \(\.$gym)")
    }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        PhoneWatchBridge.shared.startClimbingWorkout(gymID: gym?.id)
        if let name = gym?.name {
            return .result(dialog: "Started climbing at \(name).")
        }
        return .result(dialog: "Started climbing workout.")
    }
}

struct ClimberShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: StartClimbingWorkoutIntent(),
            phrases: [
                "Start a climbing workout in \(.applicationName)",
                "Start climbing with \(.applicationName)",
                "Start a session in \(.applicationName)",
            ],
            shortTitle: "Start Workout",
            systemImageName: "figure.climbing"
        )
    }
}

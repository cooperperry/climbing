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

/// Starts a Climber session and the Watch workout without opening the app,
/// so an Arrive automation can run while the phone is locked.
struct StartClimbingWorkoutIntent: AppIntent {
    static var title: LocalizedStringResource = "Start Climbing Workout"
    static var description = IntentDescription(
        "Starts a climbing session and the Watch workout while the phone stays locked. Pick a gym to mark it as I'm here."
    )
    static var openAppWhenRun: Bool { false }
    static var authenticationPolicy: IntentAuthenticationPolicy { .alwaysAllowed }

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

struct EndClimbingWorkoutIntent: AppIntent {
    static var title: LocalizedStringResource = "End Climbing Workout"
    static var description = IntentDescription(
        "Ends the current climbing session and the Watch workout."
    )
    static var openAppWhenRun: Bool { false }
    static var authenticationPolicy: IntentAuthenticationPolicy { .alwaysAllowed }

    static var parameterSummary: some ParameterSummary {
        Summary("End climbing workout")
    }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        if PhoneWatchBridge.shared.endClimbingWorkout() {
            return .result(dialog: "Ended climbing workout.")
        }
        return .result(dialog: "No climbing workout was running.")
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
        AppShortcut(
            intent: EndClimbingWorkoutIntent(),
            phrases: [
                "End a climbing workout in \(.applicationName)",
                "Stop climbing with \(.applicationName)",
                "End a session in \(.applicationName)",
            ],
            shortTitle: "End Workout",
            systemImageName: "stop.circle.fill"
        )
    }
}

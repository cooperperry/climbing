import SwiftUI
import SwiftData

@main
struct ClimbingApp: App {
    let container: ModelContainer

    init() {
        do {
            container = try ModelContainer(
                for: ClimbingSession.self, ClimbLog.self, CustomGradeScale.self
            )
        } catch {
            fatalError("Failed to create the SwiftData ModelContainer: \(error)")
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .modelContainer(container)
    }
}

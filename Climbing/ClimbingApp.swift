import SwiftUI
import SwiftData

@main
struct ClimbingApp: App {
    let container: ModelContainer

    init() {
        do {
            container = try ModelContainer(
                for: ClimbSession.self, ClimbingSession.self, ClimbLog.self, CustomGradeScale.self
            )
        } catch {
            fatalError("Failed to create the SwiftData ModelContainer: \(error)")
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .onAppear {
                    PhoneWatchBridge.shared.attach(context: container.mainContext)
                }
        }
        .modelContainer(container)
    }
}

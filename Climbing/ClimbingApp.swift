import SwiftUI
import SwiftData

@main
struct ClimbingApp: App {
    let container: ModelContainer

    init() {
        do {
            container = try ModelContainer(
                for: ClimbSession.self, ClimbingSession.self, ClimbLog.self, CustomGradeScale.self, ClimbGym.self, GymArea.self, GymRoute.self
            )
        } catch {
            fatalError("Failed to create the SwiftData ModelContainer: \(error)")
        }
        PhoneWatchBridge.shared.attach(context: container.mainContext)
        PhoneWatchBridge.shared.prepareArrivalNotification()
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

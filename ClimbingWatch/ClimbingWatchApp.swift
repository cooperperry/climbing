import SwiftUI
import WatchKit
import HealthKit

@main
struct ClimbingWatchApp: App {
    @WKApplicationDelegateAdaptor(WatchAppDelegate.self) private var delegate

    init() {
        _ = WatchStore.shared
        _ = WorkoutManager.shared
        WorkoutManager.shared.prepare()
    }

    var body: some Scene {
        WindowGroup {
            NavigationStack {
                WatchWorkoutView()
            }
        }
    }
}

final class WatchAppDelegate: NSObject, WKApplicationDelegate {
    func handle(_ workoutConfiguration: HKWorkoutConfiguration) {
        Task { await WorkoutManager.shared.start(configuration: workoutConfiguration) }
    }
}

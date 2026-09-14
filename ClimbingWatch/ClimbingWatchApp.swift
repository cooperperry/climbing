import SwiftUI
import WatchKit
import HealthKit

@main
struct ClimbingWatchApp: App {
    @WKApplicationDelegateAdaptor(WatchAppDelegate.self) private var delegate

    init() {
        _ = WatchStore.shared
        _ = WatchWorkoutController.shared
    }

    var body: some Scene {
        WindowGroup {
            TabView {
                NavigationStack { WatchSessionView() }
                NavigationStack { WatchProgressView() }
            }
        }
    }
}

final class WatchAppDelegate: NSObject, WKApplicationDelegate {
    func handle(_ workoutConfiguration: HKWorkoutConfiguration) {
        Task { await WatchWorkoutController.shared.start(configuration: workoutConfiguration) }
    }
}

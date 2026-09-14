import SwiftUI
import WatchKit
import HealthKit

@main
struct ClimbingWatchApp: App {
    @WKApplicationDelegateAdaptor(WatchAppDelegate.self) private var delegate

    init() {
        _ = WorkoutMotionManager.shared
    }

    var body: some Scene {
        WindowGroup {
            WatchRootView()
        }
    }
}

final class WatchAppDelegate: NSObject, WKApplicationDelegate {
    func handle(_ workoutConfiguration: HKWorkoutConfiguration) {
        Task { await WorkoutMotionManager.shared.start(configuration: workoutConfiguration) }
    }
}

/// Honest about what the Watch records: wrist effort, not a map of the route.
struct WatchRootView: View {
    var body: some View {
        ScrollView {
            VStack(spacing: 10) {
                Image(systemName: "figure.climbing")
                    .font(.largeTitle)
                    .foregroundStyle(.orange)
                Text("Send traces")
                    .font(.headline)
                Text("Start a session on iPhone and this Watch records wrist motion. After a send or flash, iPhone shows an effort strip with heart rate — not an outline of the route.")
                    .font(.footnote)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
            }
            .padding()
        }
    }
}

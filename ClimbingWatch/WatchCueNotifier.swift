import Foundation
import UserNotifications
import WatchKit

/// Local Watch pings for start, warmup done, and rest-complete.
enum WatchCueNotifier {
    static func requestAuthorization() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    static func workoutStarted() {
        ping(
            id: "workout-start",
            title: "Climb started",
            body: "Warm up on easy terrain before you send.",
            haptic: .start
        )
    }

    static func warmupComplete() {
        ping(
            id: "warmup-complete",
            title: "Warmed up",
            body: "Heart and fingers are ready. Go climb.",
            haptic: .success
        )
    }

    static func restComplete() {
        ping(
            id: "rest-complete",
            title: "Rest done",
            body: "You're recovered. Attempt a send.",
            haptic: .notification
        )
    }

    private static func ping(id: String, title: String, body: String, haptic: WKHapticType) {
        WKInterfaceDevice.current().play(haptic)
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        let request = UNNotificationRequest(identifier: id, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }
}

enum LifetimeGainStore {
    static let key = "lifetimeVerticalGainMeters"

    static func load() -> Double {
        max(0, UserDefaults.standard.double(forKey: key))
    }

    static func merge(_ meters: Double) {
        let value = max(0, meters)
        guard value > load() else { return }
        UserDefaults.standard.set(value, forKey: key)
    }

    static func addSession(_ meters: Double) {
        UserDefaults.standard.set(load() + max(0, meters), forKey: key)
    }
}

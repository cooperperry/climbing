import Foundation

/// The name stamped on gym-map edits from this phone.
enum ClimberIdentity {
    private static let key = "climberDisplayName"

    static var name: String {
        get { UserDefaults.standard.string(forKey: key) ?? "" }
        set { UserDefaults.standard.set(newValue.trimmingCharacters(in: .whitespacesAndNewlines), forKey: key) }
    }
}

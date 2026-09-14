import SwiftUI

/// Root view. The session tab is the app's home base for logging climbs.
struct ContentView: View {
    var body: some View {
        SessionView()
    }
}

#Preview {
    ContentView()
        .modelContainer(for: [ClimbingSession.self, ClimbLog.self, CustomGradeScale.self],
                        inMemory: true)
}

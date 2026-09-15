import SwiftUI

/// Root: SummitPulse activity feed.
struct ContentView: View {
    var body: some View {
        ActivityFeedView()
            .tint(.stravaOrange)
    }
}

#Preview {
    ContentView()
        .modelContainer(for: [ClimbSession.self], inMemory: true)
}

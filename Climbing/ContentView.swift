import SwiftUI

/// Root tab layout: log the current session, or review lifetime progress.
struct ContentView: View {
    var body: some View {
        TabView {
            SessionView()
                .tabItem { Label("Session", systemImage: "figure.climbing") }
            StatsView()
                .tabItem { Label("Progress", systemImage: "chart.bar.fill") }
        }
        .tint(.stravaOrange)
    }
}

#Preview {
    ContentView()
        .modelContainer(for: [ClimbingSession.self, ClimbLog.self, CustomGradeScale.self],
                        inMemory: true)
}

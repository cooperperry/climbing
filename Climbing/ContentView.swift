import SwiftUI

/// Phone home: log routes without a Watch, and browse Watch health sessions.
struct ContentView: View {
    var body: some View {
        TabView {
            RouteLogView()
                .tabItem { Label("Routes", systemImage: "checkmark.circle.fill") }
            GymListView()
                .tabItem { Label("Gyms", systemImage: "building.2.fill") }
            ActivityFeedView()
                .tabItem { Label("Sessions", systemImage: "heart.fill") }
            StatsView()
                .tabItem { Label("Progress", systemImage: "chart.bar.fill") }
        }
        .tint(.stravaOrange)
    }
}

#Preview {
    ContentView()
        .modelContainer(
            for: [ClimbSession.self, ClimbingSession.self, ClimbLog.self, CustomGradeScale.self, ClimbGym.self, GymArea.self, GymRoute.self],
            inMemory: true
        )
}

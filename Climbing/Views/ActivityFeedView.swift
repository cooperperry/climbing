import SwiftUI
import SwiftData

/// Strava-style feed of SummitPulse sessions.
struct ActivityFeedView: View {
    @Query(sort: \ClimbSession.startDate, order: .reverse)
    private var sessions: [ClimbSession]

    private var lifetimeGain: Double {
        sessions.reduce(0) { $0 + $1.totalElevationGain }
    }

    var body: some View {
        NavigationStack {
            Group {
                if sessions.isEmpty {
                    ContentUnavailableView {
                        Label("SummitPulse", systemImage: "mountain.2.fill")
                    } description: {
                        Text("Start a climb on Apple Watch. Elevation, heart rate, and strain show up here when you end the workout.")
                    }
                } else {
                    ScrollView {
                        VStack(spacing: 16) {
                            if let latest = sessions.first {
                                sessionHeader(latest)
                                heroGrid(latest)
                            }
                            milestoneCarousel
                            ForEach(sessions.prefix(20)) { session in
                                sessionRow(session)
                            }
                        }
                        .padding()
                    }
                }
            }
            .navigationTitle("Activity")
        }
    }

    private func sessionHeader(_ session: ClimbSession) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(session.payload.sessionTitle)
                .font(.title.bold())
            Text(session.startDate, format: .dateTime.weekday().month().day().hour().minute())
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func heroGrid(_ session: ClimbSession) -> some View {
        let target = LandmarkMath.sessionTarget(gainMeters: session.totalElevationGain)
        let progress = LandmarkMath.progress(gainMeters: session.totalElevationGain, toward: target)
        return LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
            heroCard(
                value: ElevationFormat.gain(meters: session.totalElevationGain),
                label: target.name,
                badge: "\(Int((progress.lapPercent * 100).rounded()))%"
            )
            heroCard(
                value: "\(Int(session.activeCalories.rounded()))",
                label: "Active kcal"
            )
            heroCard(
                value: String(format: "%.1f", session.bodyStressIndex),
                label: "Body stress"
            )
            heroCard(
                value: ratioText(session),
                label: "Climb / rest"
            )
        }
    }

    private var milestoneCarousel: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Landmarks")
                .font(.headline)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(Landmark.all) { landmark in
                        let progress = LandmarkMath.progress(gainMeters: lifetimeGain, toward: landmark)
                        VStack(alignment: .leading, spacing: 6) {
                            Text(landmark.name)
                                .font(.subheadline.bold())
                                .lineLimit(2)
                            Text(String(format: "%.1f×", progress.completions))
                                .font(.title2.bold())
                                .foregroundStyle(.stravaOrange)
                            ProgressView(value: progress.lapPercent)
                                .tint(.stravaOrange)
                        }
                        .padding()
                        .frame(width: 180, alignment: .leading)
                        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 16))
                    }
                }
            }
        }
    }

    private func sessionRow(_ session: ClimbSession) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(session.startDate, format: .dateTime.month().day())
                    .font(.subheadline.bold())
                Text(ElevationFormat.gain(meters: session.totalElevationGain))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text("\(Int(session.activeCalories.rounded())) kcal")
                .font(.subheadline.monospacedDigit())
        }
        .padding()
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 16))
    }

    private func heroCard(value: String, label: String, badge: String? = nil) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            if let badge {
                Text(badge)
                    .font(.caption2.bold())
                    .foregroundStyle(.stravaOrange)
            }
            Text(value)
                .font(.title2.bold())
                .minimumScaleFactor(0.6)
                .lineLimit(1)
            Text(label.uppercased())
                .font(.caption2.bold())
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 16))
    }

    private func ratioText(_ session: ClimbSession) -> String {
        let rest = max(session.restingTime, 1)
        return String(format: "%.1f×", session.climbingTime / rest)
    }
}

#Preview {
    ActivityFeedView()
        .modelContainer(for: [ClimbSession.self], inMemory: true)
}

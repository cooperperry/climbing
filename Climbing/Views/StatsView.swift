import SwiftUI
import SwiftData
import Charts

/// Strava-style progress dashboard: lifetime level, headline stats, a send
/// pyramid, and recent sessions. Clean and data-forward — no confetti.
struct StatsView: View {
    @Query private var logs: [ClimbLog]

    @Query(sort: \ClimbingSession.startTime, order: .reverse)
    private var sessions: [ClimbingSession]

    private var totalPoints: Int {
        logs.reduce(0) { $0 + $1.points }
    }

    private var level: ClimberLevel { ScoreEngine.level(forTotalPoints: totalPoints) }
    private var progress: Double { ScoreEngine.progressToNextLevel(forTotalPoints: totalPoints) }

    private var sends: [ClimbLog] { logs.filter { $0.outcome.isCompletion } }
    private var flashes: Int { logs.filter { $0.outcome == .flash }.count }
    private var hardestSend: ClimbLog? { sends.max { $0.gradeIndex < $1.gradeIndex } }

    var body: some View {
        NavigationStack {
            Group {
                if logs.isEmpty {
                    emptyState
                } else {
                    ScrollView {
                        VStack(spacing: 16) {
                            levelCard
                            statGrid
                            pyramidCard
                            recentSessionsCard
                        }
                        .padding()
                    }
                }
            }
            .navigationTitle("Progress")
        }
    }

    // MARK: - Empty

    private var emptyState: some View {
        ContentUnavailableView {
            Label("No Stats Yet", systemImage: "chart.bar")
        } description: {
            Text("Log climbs in a session and your progress will show up here.")
        }
    }

    // MARK: - Level

    private var levelCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("LEVEL \(level.number)")
                        .font(.caption.bold())
                        .foregroundStyle(.secondary)
                    Text(level.title)
                        .font(.title2.bold())
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text("\(totalPoints)")
                        .font(.system(size: 34, weight: .bold, design: .rounded))
                        .monospacedDigit()
                    Text("POINTS")
                        .font(.caption2.bold())
                        .foregroundStyle(.secondary)
                }
            }

            ProgressView(value: progress)
                .tint(.stravaOrange)

            Text(level.isMaxLevel
                 ? "Top tier reached"
                 : "\(ScoreEngine.pointsToNextLevel(forTotalPoints: totalPoints)) pts to next level")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .cardStyle()
    }

    // MARK: - Stat grid

    private var statGrid: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
            statCard(value: "\(logs.count)", label: "Climbs", systemImage: "figure.climbing")
            statCard(value: "\(sends.count)", label: "Sends", systemImage: "checkmark.circle.fill")
            statCard(value: "\(flashes)", label: "Flashes", systemImage: "bolt.fill")
            statCard(
                value: hardestSend?.gradeLabel ?? "—",
                label: "Hardest Send",
                systemImage: "trophy.fill"
            )
        }
    }

    private func statCard(value: String, label: String, systemImage: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: systemImage)
                .foregroundStyle(.stravaOrange)
            Text(value)
                .font(.title2.bold())
                .monospacedDigit()
            Text(label.uppercased())
                .font(.caption2.bold())
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardStyle()
    }

    // MARK: - Send pyramid

    private struct GradeTally: Identifiable {
        let grade: String
        let index: Int
        let count: Int
        var id: String { grade }
    }

    private var pyramid: [GradeTally] {
        var tallies: [String: (index: Int, count: Int)] = [:]
        for log in sends {
            let existing = tallies[log.gradeLabel]
            tallies[log.gradeLabel] = (existing?.index ?? log.gradeIndex,
                                       (existing?.count ?? 0) + 1)
        }
        return tallies
            .map { GradeTally(grade: $0.key, index: $0.value.index, count: $0.value.count) }
            .sorted { $0.index < $1.index }
    }

    @ViewBuilder
    private var pyramidCard: some View {
        if !pyramid.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                Text("Send Pyramid")
                    .font(.headline)
                Chart(pyramid) { tally in
                    BarMark(
                        x: .value("Sends", tally.count),
                        y: .value("Grade", tally.grade)
                    )
                    .foregroundStyle(.stravaOrange)
                    .annotation(position: .trailing) {
                        Text("\(tally.count)")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                .chartXAxis(.hidden)
                .frame(height: max(120, CGFloat(pyramid.count) * 34))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .cardStyle()
        }
    }

    // MARK: - Recent sessions

    @ViewBuilder
    private var recentSessionsCard: some View {
        let recent = sessions.filter { !$0.isActive }.prefix(5)
        if !recent.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                Text("Recent Sessions")
                    .font(.headline)
                ForEach(Array(recent)) { session in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(session.startTime, format: .dateTime.weekday().month().day())
                                .font(.subheadline.bold())
                            Text("\(session.logs.count) climbs • \(SessionClock.format(session.duration()))")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text("\(session.score) pts")
                            .font(.subheadline.bold())
                            .monospacedDigit()
                            .foregroundStyle(.stravaOrange)
                    }
                    .padding(.vertical, 4)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .cardStyle()
        }
    }
}

private extension View {
    /// Shared card container styling used across the dashboard.
    func cardStyle() -> some View {
        padding()
            .background(Color(.secondarySystemBackground),
                        in: RoundedRectangle(cornerRadius: 16))
    }
}

#Preview {
    StatsView()
        .modelContainer(for: [ClimbingSession.self, ClimbLog.self, CustomGradeScale.self],
                        inMemory: true)
}

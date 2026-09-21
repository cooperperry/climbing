import SwiftUI
import SwiftData
import Charts

/// Strava-style progress dashboard: lifetime level, headline stats, a send
/// pyramid, and recent sessions. Clean and data-forward — no confetti.
struct StatsView: View {
    @Query private var logs: [ClimbLog]

    @Query(sort: \ClimbingSession.startTime, order: .reverse)
    private var sessions: [ClimbingSession]

    @Query(sort: \ClimbSession.startDate, order: .reverse)
    private var workouts: [ClimbSession]

    private var lifetimeGain: Double {
        workouts.filter { $0.endDate != nil }.reduce(0) { $0 + $1.totalElevationGain }
    }

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
                if logs.isEmpty && lifetimeGain == 0 {
                    emptyState
                } else {
                    ScrollView {
                        VStack(spacing: 16) {
                            if !logs.isEmpty {
                                levelCard
                                statGrid
                                styleCard
                                pyramidCard
                                recentSessionsCard
                            }
                            if lifetimeGain > 0 {
                                landmarkCard
                            }
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
            Text("Log a top on the Routes tab, or start a Watch climb. Height toward El Cap stacks across sessions.")
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
        VStack(spacing: 12) {
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

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                ForEach(ClimbDiscipline.allCases) { item in
                    statCard(
                        value: "\(sends.filter { $0.resolvedDiscipline == item }.count)",
                        label: item.displayName,
                        systemImage: item.symbolName
                    )
                }
            }
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

    // MARK: - Style weak spot

    private var styleInsight: StyleInsight {
        StyleWeakSpotMath.insight(
            logs: logs.compactMap { log in
                guard let style = log.style else { return nil }
                return StyleLog(style: style, outcome: log.outcome, loggedAt: log.loggedAt)
            },
            now: Date()
        )
    }

    private var styleCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Style")
                    .font(.headline)
                Spacer()
                Text("Last \(styleInsight.windowDays) days")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if styleInsight.hasEnoughData {
                if let headline = styleInsight.headline {
                    Text(headline)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                ForEach(styleInsight.spots) { spot in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(spot.style.displayName)
                                .font(.subheadline.bold())
                            Spacer()
                            Text(spot.percentText)
                                .font(.subheadline.bold())
                                .monospacedDigit()
                                .foregroundStyle(spot.style == styleInsight.weakest?.style ? Color.stravaOrange : Color.secondary)
                            Text("\(spot.sends)/\(spot.goes)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .monospacedDigit()
                        }
                        ProgressView(value: spot.sendRate)
                            .tint(spot.style == styleInsight.weakest?.style ? .stravaOrange : .green)
                    }
                }
                Text("Send rate on tagged holds — skip tagging if you don't care")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            } else {
                Text("After a go, you can tag holds and wall (a climb can be both crimpy and overhanging). Tag 3+ of the same hold type to see send rate.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
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

    // MARK: - Lifetime height

    @ViewBuilder
    private var landmarkCard: some View {
        let target = LandmarkMath.sessionTarget(gainMeters: lifetimeGain)
        let progress = LandmarkMath.progress(gainMeters: lifetimeGain, toward: target)
        let remainingFt = Int((progress.remainingMeters / 0.3048).rounded())
        VStack(alignment: .leading, spacing: 12) {
            Text("Lifetime height")
                .font(.headline)
            Text("Keeps going across sessions — El Cap is thousands of gym goes.")
                .font(.caption)
                .foregroundStyle(.secondary)
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(target.name)
                        .font(.subheadline.bold())
                    Text("\(remainingFt) ft to go")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Text(ElevationFormat.gain(meters: lifetimeGain))
                    .font(.title3.bold().monospacedDigit())
            }
            ProgressView(value: progress.lapPercent)
                .tint(.stravaOrange)
            ForEach(Landmark.all) { landmark in
                let done = landmark.completions(gainMeters: lifetimeGain)
                HStack {
                    Text(landmark.name)
                        .font(.caption)
                    Spacer()
                    Text(String(format: "%.1f×", done))
                        .font(.caption.bold().monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardStyle()
    }

    // MARK: - Recent sessions

    @ViewBuilder
    private var recentSessionsCard: some View {
        let recent: [ClimbingSession] = Array(sessions.filter { !$0.isActive }.prefix(5))
        if !recent.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                Text("Recent Sessions")
                    .font(.headline)
                ForEach(recent) { session in
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
        .modelContainer(for: [ClimbingSession.self, ClimbLog.self, CustomGradeScale.self, ClimbSession.self],
                        inMemory: true)
}

import SwiftUI
import SwiftData

/// Journal of gym days: the routes you topped, plus Watch health for that day.
struct ActivityFeedView: View {
    @Query(sort: \ClimbSession.startDate, order: .reverse)
    private var workouts: [ClimbSession]
    @Query(sort: \ClimbLog.loggedAt, order: .reverse)
    private var logs: [ClimbLog]
    @State private var bridge = PhoneWatchBridge.shared
    @State private var filter: DayFilter = .all

    private var live: ClimbSessionPayload? {
        if let payload = bridge.liveWorkout, payload.isLive { return payload }
        return workouts.first(where: \.isActive)?.payload
    }

    private var days: [GymDay] {
        GymDayMath.group(
            climbs: logs.map {
                DayClimb(
                    loggedAt: $0.loggedAt,
                    gradeLabel: $0.gradeLabel,
                    outcome: $0.outcome,
                    discipline: $0.resolvedDiscipline
                )
            },
            workouts: workouts.filter { $0.endDate != nil }.map { workout in
                let payload = workout.payload
                return DayHealth(
                    startDate: workout.startDate,
                    calories: workout.activeCalories,
                    gainMeters: workout.totalElevationGain,
                    peakBPM: payload.peakBPM,
                    averageBPM: payload.averageBPM,
                    bodyStress: workout.bodyStressIndex,
                    duration: workout.endDate.map { $0.timeIntervalSince(workout.startDate) } ?? payload.elapsed,
                    heartRates: workout.heartRateSeries
                )
            }
        )
    }

    private var visibleDays: [GymDay] {
        switch filter {
        case .all:
            return days
        case .day(let start):
            return days.filter { $0.dayStart == start }
        }
    }

    private var lifetimeGain: Double {
        workouts.reduce(0) { $0 + $1.totalElevationGain }
    }

    var body: some View {
        NavigationStack {
            Group {
                if live == nil && days.isEmpty {
                    ContentUnavailableView {
                        Label("No sessions yet", systemImage: "calendar")
                    } description: {
                        Text("Log a top on Routes, or start a climb on Watch. Each day keeps those together.")
                    }
                } else {
                    ScrollView {
                        VStack(spacing: 16) {
                            if let live {
                                liveNowCard(live)
                            }
                            ForEach(visibleDays) { day in
                                dayCard(day, expanded: filter != .all || visibleDays.count == 1)
                            }
                            if filter == .all {
                                milestoneCarousel
                            }
                        }
                        .padding()
                    }
                }
            }
            .navigationTitle("Sessions")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    dayMenu
                }
            }
        }
    }

    private var dayMenu: some View {
        Menu {
            Button("All days") { filter = .all }
            ForEach(days) { day in
                Button(day.dayStart.formatted(.dateTime.weekday(.wide).month(.abbreviated).day())) {
                    filter = .day(day.dayStart)
                }
            }
        } label: {
            Label(filterLabel, systemImage: "calendar")
        }
        .disabled(days.isEmpty)
    }

    private var filterLabel: String {
        switch filter {
        case .all:
            return "All days"
        case .day(let start):
            return start.formatted(.dateTime.month(.abbreviated).day())
        }
    }

    private func dayCard(_ day: GymDay, expanded: Bool) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Button {
                filter = .day(day.dayStart)
            } label: {
                HStack {
                    Text(day.dayStart, format: .dateTime.weekday(.wide).month().day())
                        .font(.title3.bold())
                        .foregroundStyle(.primary)
                    Spacer()
                    if filter == .all {
                        Image(systemName: "chevron.right")
                            .font(.caption.bold())
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .buttonStyle(.plain)
            .disabled(expanded && filter != .all)

            ForEach(ClimbDiscipline.allCases) { discipline in
                let tops = day.tops(in: discipline)
                if !tops.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(discipline.displayName)
                            .font(.caption.bold())
                            .foregroundStyle(.secondary)
                        if expanded {
                            ForEach(tops) { climb in
                                HStack {
                                    Text(climb.gradeLabel)
                                        .font(.headline)
                                    Text(climb.outcome.displayName)
                                        .font(.subheadline)
                                        .foregroundStyle(.secondary)
                                    Spacer()
                                }
                            }
                        } else {
                            Text(tops.map(\.gradeLabel).joined(separator: "  ·  "))
                                .font(.headline)
                        }
                    }
                }
            }

            if day.tops.isEmpty && day.health == nil && !day.climbs.isEmpty {
                Text("Still working — no tops yet")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            if let health = day.health {
                healthBlock(health, expanded: expanded)
            } else if expanded {
                Text("No Watch workout this day")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 16))
    }

    private func healthBlock(_ health: DayHealth, expanded: Bool) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Health")
                .font(.caption.bold())
                .foregroundStyle(.secondary)
            HStack(spacing: 16) {
                metric("\(Int(health.calories.rounded()))", "kcal")
                metric(ElevationFormat.gain(meters: health.gainMeters), "gain")
                if let peak = health.peakBPM {
                    metric("\(peak)", "peak BPM")
                }
                metric(String(format: "%.1f", health.bodyStress), "stress")
            }
            if expanded, health.heartRates.count >= 2 {
                PhoneBPMSparkline(samples: Array(health.heartRates.suffix(90)))
                    .frame(height: 56)
            }
        }
    }

    private func metric(_ value: String, _ label: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value)
                .font(.subheadline.bold())
                .monospacedDigit()
                .minimumScaleFactor(0.7)
                .lineLimit(1)
            Text(label.uppercased())
                .font(.caption2.bold())
                .foregroundStyle(.secondary)
        }
    }

    private func liveNowCard(_ payload: ClimbSessionPayload) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                Text("LIVE")
                    .font(.caption.bold())
                    .foregroundStyle(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Color.stravaOrange, in: Capsule())
                Text(payload.phase == .climbing ? "Climbing" : "Resting")
                    .font(.caption.bold())
                    .foregroundStyle(payload.phase == .climbing ? .green : .secondary)
                Spacer()
                TimelineView(.periodic(from: .now, by: 1)) { _ in
                    Text(payload.isPaused ? "PAUSED" : SessionClock.format(liveElapsed(payload)))
                        .font(.subheadline.bold().monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }

            HStack(alignment: .lastTextBaseline, spacing: 6) {
                Text(payload.currentBPM.map(String.init) ?? "--")
                    .font(.system(size: 44, weight: .bold, design: .rounded))
                    .foregroundStyle(.red)
                    .monospacedDigit()
                Text("BPM")
                    .font(.headline.bold())
                    .foregroundStyle(.red.opacity(0.85))
                Spacer()
            }

            PhoneBPMSparkline(samples: payload.sparkline)
                .frame(height: 56)

            HStack(spacing: 16) {
                metric("\(Int(payload.activeCalories.rounded()))", "kcal")
                metric(ElevationFormat.gain(meters: payload.totalElevationGain), "gain")
                metric(payload.heartRateZone.readout, "zone")
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 16))
    }

    private func liveElapsed(_ payload: ClimbSessionPayload) -> TimeInterval {
        if payload.isPaused { return payload.elapsed }
        let extra = bridge.liveReceivedAt.map { Date().timeIntervalSince($0) } ?? 0
        if payload.elapsed > 0 { return payload.elapsed + max(0, extra) }
        return max(0, Date().timeIntervalSince(payload.startDate))
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
}

private enum DayFilter: Hashable {
    case all
    case day(Date)
}

/// Phone-side BPM sparkline matching the Watch glance.
struct PhoneBPMSparkline: View {
    var samples: [HeartRateSample]
    var lineColor: Color = .red

    var body: some View {
        Canvas { context, size in
            let values = samples.map(\.bpm)
            guard values.count >= 2 else { return }
            let lo = min(70, values.min() ?? 70)
            let hi = max(lo + 20, values.max() ?? 160)
            let span = max(samples.last!.timestamp - samples.first!.timestamp, 0.001)
            var path = Path()
            for (index, sample) in samples.enumerated() {
                let x = CGFloat((sample.timestamp - samples[0].timestamp) / span) * size.width
                let y = size.height - CGFloat((sample.bpm - lo) / (hi - lo)) * size.height
                if index == 0 {
                    path.move(to: CGPoint(x: x, y: y))
                } else {
                    path.addLine(to: CGPoint(x: x, y: y))
                }
            }
            var filled = path
            filled.addLine(to: CGPoint(x: size.width, y: size.height))
            filled.addLine(to: CGPoint(x: 0, y: size.height))
            filled.closeSubpath()
            context.fill(filled, with: .color(lineColor.opacity(0.22)))
            context.stroke(path, with: .color(lineColor), lineWidth: 2.5)
        }
        .accessibilityHidden(true)
    }
}

#Preview {
    ActivityFeedView()
        .modelContainer(
            for: [ClimbSession.self, ClimbLog.self, ClimbingSession.self, CustomGradeScale.self],
            inMemory: true
        )
}

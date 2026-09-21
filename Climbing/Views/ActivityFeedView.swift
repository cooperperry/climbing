import SwiftUI
import SwiftData

/// One workout at a time: newest first, with a picker to jump to another.
struct ActivityFeedView: View {
    @Query(sort: \ClimbSession.startDate, order: .reverse)
    private var workouts: [ClimbSession]
    @Query(sort: \ClimbLog.loggedAt, order: .reverse)
    private var logs: [ClimbLog]
    @State private var bridge = PhoneWatchBridge.shared
    @State private var selectedID: String?

    private var live: ClimbSessionPayload? {
        if let payload = bridge.liveWorkout, payload.isLive { return payload }
        return workouts.first(where: \.isActive)?.payload
    }

    private var sessions: [SessionSummary] {
        SessionSummaryMath.assemble(
            workouts: workouts.filter { $0.endDate != nil }.map { workout in
                let payload = workout.payload
                return SessionHealth(
                    id: workout.id.uuidString,
                    startDate: workout.startDate,
                    endDate: workout.endDate,
                    calories: workout.activeCalories,
                    gainMeters: workout.totalElevationGain,
                    peakBPM: payload.peakBPM,
                    averageBPM: payload.averageBPM,
                    bodyStress: workout.bodyStressIndex,
                    duration: workout.endDate.map { $0.timeIntervalSince(workout.startDate) } ?? payload.elapsed,
                    heartRates: workout.heartRateSeries
                )
            },
            climbs: logs.map {
                SessionClimb(
                    loggedAt: $0.loggedAt,
                    gradeLabel: $0.gradeLabel,
                    outcome: $0.outcome,
                    discipline: $0.resolvedDiscipline
                )
            }
        )
    }

    private var selected: SessionSummary? {
        if let selectedID, let match = sessions.first(where: { $0.id == selectedID }) {
            return match
        }
        return sessions.first
    }

    var body: some View {
        NavigationStack {
            Group {
                if live == nil && sessions.isEmpty {
                    ContentUnavailableView {
                        Label("No sessions yet", systemImage: "figure.climbing")
                    } description: {
                        Text("Start a climb on Watch, or log a top on Routes. Height toward El Cap stacks across sessions.")
                    }
                } else {
                    ScrollView {
                        VStack(spacing: 16) {
                            if let live {
                                liveNowCard(live)
                            }
                            if let selected {
                                sessionCard(selected)
                            }
                        }
                        .padding()
                    }
                }
            }
            .navigationTitle("Sessions")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    sessionMenu
                }
            }
            .onChange(of: sessions.first?.id) { _, newest in
                if selectedID == nil {
                    selectedID = newest
                }
            }
        }
    }

    @ViewBuilder
    private var sessionMenu: some View {
        Menu {
            ForEach(sessions) { session in
                Button {
                    selectedID = session.id
                } label: {
                    if session.id == selected?.id {
                        Label(menuTitle(session), systemImage: "checkmark")
                    } else {
                        Text(menuTitle(session))
                    }
                }
            }
        } label: {
            Label(selected.map(menuTitle) ?? "Sessions", systemImage: "clock")
        }
        .disabled(sessions.isEmpty)
    }

    private func sessionCard(_ session: SessionSummary) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Menu {
                ForEach(sessions) { item in
                    Button {
                        selectedID = item.id
                    } label: {
                        Text(menuTitle(item))
                    }
                }
            } label: {
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(session.startDate, format: .dateTime.weekday(.wide).month().day())
                            .font(.title3.bold())
                            .foregroundStyle(.primary)
                        Text(timeRange(session))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    if sessions.count > 1 {
                        Image(systemName: "chevron.up.chevron.down")
                            .font(.caption.bold())
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .disabled(sessions.count < 2)

            if let health = session.health {
                HStack(spacing: 16) {
                    metric("\(Int(health.calories.rounded()))", "kcal")
                    metric(ElevationFormat.gain(meters: health.gainMeters), "gain")
                    if let peak = health.peakBPM {
                        metric("\(peak)", "peak BPM")
                    }
                    if health.bodyStress > 0 {
                        metric(String(format: "%.1f", health.bodyStress), "stress")
                    }
                }
                if health.heartRates.count >= 2 {
                    PhoneBPMSparkline(samples: Array(health.heartRates.suffix(90)))
                        .frame(height: 56)
                }
            }

            climbsBlock(session)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 16))
    }

    @ViewBuilder
    private func climbsBlock(_ session: SessionSummary) -> some View {
        if session.climbs.isEmpty {
            Text("No sends logged this session")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        } else {
            VStack(alignment: .leading, spacing: 12) {
                ForEach(ClimbDiscipline.allCases) { discipline in
                    let rows = session.climbs(in: discipline)
                    if !rows.isEmpty {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(discipline.displayName)
                                .font(.caption.bold())
                                .foregroundStyle(.secondary)
                            ForEach(rows) { climb in
                                HStack {
                                    Text(climb.gradeLabel)
                                        .font(.headline)
                                    Text(climb.outcome.displayName)
                                        .font(.subheadline)
                                        .foregroundStyle(.secondary)
                                    Spacer()
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    private func menuTitle(_ session: SessionSummary) -> String {
        let time = session.startDate.formatted(date: .omitted, time: .shortened)
        let day: String
        if Calendar.current.isDateInToday(session.startDate) {
            day = "Today"
        } else if Calendar.current.isDateInYesterday(session.startDate) {
            day = "Yesterday"
        } else {
            day = session.startDate.formatted(.dateTime.month(.abbreviated).day())
        }
        return "\(day) \(time)"
    }

    private func timeRange(_ session: SessionSummary) -> String {
        let start = session.startDate.formatted(date: .omitted, time: .shortened)
        guard session.duration >= 60, let endDate = session.endDate, endDate > session.startDate else {
            return start
        }
        let end = endDate.formatted(date: .omitted, time: .shortened)
        return "\(start)–\(end) · \(SessionClock.format(session.duration))"
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

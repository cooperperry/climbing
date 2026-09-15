import SwiftUI
import SwiftData

/// Strava-style feed of SummitPulse sessions, including a live Watch mirror.
struct ActivityFeedView: View {
    @Query(sort: \ClimbSession.startDate, order: .reverse)
    private var sessions: [ClimbSession]
    @State private var bridge = PhoneWatchBridge.shared

    private var live: ClimbSessionPayload? {
        if let payload = bridge.liveWorkout, payload.isLive { return payload }
        return sessions.first(where: \.isActive)?.payload
    }

    private var completed: [ClimbSession] {
        sessions.filter { $0.endDate != nil }
    }

    private var lifetimeGain: Double {
        completed.reduce(0) { $0 + $1.totalElevationGain } + (live?.totalElevationGain ?? 0)
    }

    var body: some View {
        NavigationStack {
            Group {
                if live == nil && sessions.isEmpty {
                    ContentUnavailableView {
                        Label("SummitPulse", systemImage: "mountain.2.fill")
                    } description: {
                        Text("Start a climb on Apple Watch. Heart rate, calories, and gain show up here live.")
                    }
                } else {
                    ScrollView {
                        VStack(spacing: 16) {
                            if let live {
                                liveNowCard(live)
                            } else if let latest = completed.first {
                                sessionHeader(latest.payload, date: latest.startDate)
                                heroGrid(latest.payload)
                            }
                            milestoneCarousel
                            ForEach(completed.prefix(20)) { session in
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

    private func liveNowCard(_ payload: ClimbSessionPayload) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                Text("LIVE")
                    .font(.caption.bold())
                    .foregroundStyle(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Color.stravaOrange, in: Capsule())
                Text(payload.phase.displayName.uppercased())
                    .font(.caption.bold())
                    .foregroundStyle(payload.phase == .climbing ? .green : .secondary)
                Spacer()
                TimelineView(.periodic(from: .now, by: 1)) { _ in
                    Text(payload.isPaused ? "PAUSED" : SessionClock.format(liveElapsed(payload)))
                        .font(.subheadline.bold().monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }

            sessionHeader(payload, date: payload.startDate)

            HStack(alignment: .lastTextBaseline, spacing: 6) {
                Text(payload.currentBPM.map(String.init) ?? "--")
                    .font(.system(size: 56, weight: .bold, design: .rounded))
                    .foregroundStyle(.red)
                    .monospacedDigit()
                    .minimumScaleFactor(0.6)
                    .lineLimit(1)
                Text("BPM")
                    .font(.headline.bold())
                    .foregroundStyle(.red.opacity(0.85))
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    if let avg = payload.averageBPM {
                        Text("avg \(avg)")
                            .font(.subheadline.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                    if let peak = payload.peakBPM {
                        Text("peak \(peak)")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                }
            }

            PhoneBPMSparkline(samples: payload.sparkline)
                .frame(height: 72)

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                heroCard(
                    value: "\(Int(payload.activeCalories.rounded()))",
                    label: "Active kcal"
                )
                heroCard(
                    value: ElevationFormat.gain(meters: payload.totalElevationGain),
                    label: "Vertical gain"
                )
                heroCard(
                    value: ElevationFormat.speed(metersPerMinute: payload.verticalSpeed),
                    label: "Vert speed"
                )
                heroCard(
                    value: String(format: "%.1f", payload.bodyStressIndex),
                    label: "Body stress"
                )
            }
        }
    }

    private func liveElapsed(_ payload: ClimbSessionPayload) -> TimeInterval {
        if payload.isPaused { return payload.elapsed }
        let extra = bridge.liveReceivedAt.map { Date().timeIntervalSince($0) } ?? 0
        if payload.elapsed > 0 { return payload.elapsed + max(0, extra) }
        return max(0, Date().timeIntervalSince(payload.startDate))
    }

    private func sessionHeader(_ payload: ClimbSessionPayload, date: Date) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(payload.sessionTitle)
                .font(.title.bold())
            Text(date, format: .dateTime.weekday().month().day().hour().minute())
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func heroGrid(_ payload: ClimbSessionPayload) -> some View {
        let target = LandmarkMath.sessionTarget(gainMeters: payload.totalElevationGain)
        let progress = LandmarkMath.progress(gainMeters: payload.totalElevationGain, toward: target)
        return LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
            heroCard(
                value: ElevationFormat.gain(meters: payload.totalElevationGain),
                label: target.name,
                badge: "\(Int((progress.lapPercent * 100).rounded()))%"
            )
            heroCard(
                value: "\(Int(payload.activeCalories.rounded()))",
                label: "Active kcal"
            )
            heroCard(
                value: String(format: "%.1f", payload.bodyStressIndex),
                label: "Body stress"
            )
            heroCard(
                value: String(format: "%.1f×", payload.climbRestRatio),
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
        .modelContainer(for: [ClimbSession.self], inMemory: true)
}

import SwiftUI

/// Apple Workout-style paged session. Swipe down once from Now to end.
struct WatchWorkoutView: View {
    @State private var manager = WorkoutManager.shared
    @State private var confirmEnd = false

    var body: some View {
        if manager.isRunning || manager.isPaused {
            TabView {
                WatchMetricsPage(manager: manager)
                WatchControlsPage(
                    manager: manager,
                    confirmEnd: $confirmEnd
                )
                WatchLogPage(manager: manager)
                WatchStrainPage(manager: manager)
            }
            .tabViewStyle(.verticalPage)
            .confirmationDialog("End workout?", isPresented: $confirmEnd, titleVisibility: .visible) {
                Button("End Workout", role: .destructive) {
                    Task { await manager.end() }
                }
                Button("Keep Climbing", role: .cancel) {}
            }
        } else {
            WatchStartPage(
                isStarting: manager.isStarting,
                onStart: { manager.startFromButton() }
            )
            .toolbar(.hidden, for: .navigationBar)
        }
    }
}

/// Idle screen modeled on Apple Workout: activity mark, name, round play.
struct WatchStartPage: View {
    var isStarting: Bool
    var onStart: () -> Void

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            Circle()
                .fill(
                    RadialGradient(
                        colors: [
                            Color.workoutGreen.opacity(0.75),
                            Color.workoutGreen.opacity(0.18),
                            .clear,
                        ],
                        center: .center,
                        startRadius: 4,
                        endRadius: 92
                    )
                )
                .offset(y: -10)
                .allowsHitTesting(false)

            VStack(spacing: 0) {
                Spacer(minLength: 4)
                Image(systemName: "figure.climbing")
                    .font(.system(size: 50, weight: .regular))
                    .foregroundStyle(Color.workoutGreen)
                    .symbolRenderingMode(.hierarchical)
                    .accessibilityHidden(true)
                Text("Climb")
                    .font(.system(.title3, design: .rounded).weight(.semibold))
                    .padding(.top, 6)
                Spacer()
                Button(action: onStart) {
                    ZStack {
                        Circle()
                            .fill(Color.workoutGreen)
                            .frame(width: 62, height: 62)
                        if isStarting {
                            ProgressView()
                                .tint(.black)
                        } else {
                            Image(systemName: "play.fill")
                                .font(.title2.weight(.bold))
                                .foregroundStyle(.black)
                                .offset(x: 2)
                        }
                    }
                }
                .buttonStyle(.plain)
                .disabled(isStarting)
                .accessibilityLabel(isStarting ? "Starting climb" : "Start climb")
                .padding(.bottom, 2)
            }
            .padding(.horizontal, 8)
        }
        .toolbar(.hidden, for: .navigationBar)
        .containerBackground(Color.black, for: .navigation)
    }
}

struct WatchMetricsPage: View {
    var manager: WorkoutManager

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    Text(manager.isPaused ? "PAUSED" : SessionClock.format(manager.elapsed))
                        .font(.caption.bold().monospacedDigit())
                        .foregroundStyle(.yellow)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 0) {
                    Text(manager.phase == .climbing ? "Climbing" : "Resting")
                        .font(.caption2.bold())
                        .foregroundStyle(manager.phase == .climbing ? .green : .secondary)
                    Text(manager.currentZone.readout)
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.orange)
                        .minimumScaleFactor(0.7)
                        .lineLimit(1)
                }
            }

            TimelineView(.periodic(from: .now, by: 1)) { context in
                let cue = manager.cue(at: context.date)
                if cue != .none {
                    Button {
                        if cue.isActionable { manager.skipRest() }
                    } label: {
                        Text(cue.title)
                            .font(.caption.bold())
                            .foregroundStyle(cueColor(cue))
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .buttonStyle(.plain)
                    .disabled(!cue.isActionable)
                }
            }

            HStack(alignment: .lastTextBaseline, spacing: 4) {
                Text(manager.currentBPM.map(String.init) ?? "--")
                    .font(.system(size: 40, weight: .bold, design: .rounded))
                    .foregroundStyle(.red)
                    .monospacedDigit()
                    .minimumScaleFactor(0.6)
                    .lineLimit(1)
                Text("BPM")
                    .font(.caption2.bold())
                    .foregroundStyle(.red.opacity(0.85))
                Spacer()
                if let avg = averageBPM {
                    Text("avg \(avg)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
            }

            BPMSparkline(samples: Array(manager.heartRates.suffix(90)))
                .frame(height: 28)
                .padding(.vertical, 2)

            HStack(alignment: .top, spacing: 8) {
                compactStat("\(Int(manager.activeCalories.rounded()))", "KCAL")
                compactStat(ElevationFormat.gain(meters: manager.verticalGainMeters), "GAIN")
                compactStat(ElevationFormat.speed(metersPerMinute: manager.verticalSpeedMPerMin), "SPEED")
            }
        }
        .padding(.horizontal, 2)
        .navigationTitle("Now")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var averageBPM: Int? {
        let rates = manager.heartRates.map(\.bpm)
        guard !rates.isEmpty else { return nil }
        return Int((rates.reduce(0, +) / Double(rates.count)).rounded())
    }

    private func compactStat(_ value: String, _ label: String) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(value)
                .font(.caption.bold())
                .monospacedDigit()
                .minimumScaleFactor(0.7)
                .lineLimit(1)
            Text(label)
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func cueColor(_ cue: WorkoutCue) -> Color {
        switch cue {
        case .warmedUp, .readyToSend: return .workoutGreen
        case .resting: return .yellow
        case .warmingUp: return .secondary
        case .none: return .secondary
        }
    }
}

struct WatchLogPage: View {
    var manager: WorkoutManager

    private var grades: [String] {
        manager.logDiscipline.usesRopeGrades
            ? GradeScaleTemplate.standardYDS().grades
            : GradeScaleTemplate.standardVScale().grades
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 4) {
                ForEach(ClimbDiscipline.allCases) { item in
                    let selected = manager.logDiscipline == item
                    Button {
                        manager.selectLogDiscipline(item)
                    } label: {
                        Text(item.shortName)
                            .font(.system(size: 13, weight: .semibold, design: .rounded))
                            .minimumScaleFactor(0.7)
                            .lineLimit(2)
                            .multilineTextAlignment(.center)
                            .frame(maxWidth: .infinity, minHeight: 36)
                            .padding(.horizontal, 2)
                            .background(
                                selected ? Color.workoutGreen : Color.white.opacity(0.14),
                                in: RoundedRectangle(cornerRadius: 10, style: .continuous)
                            )
                            .foregroundStyle(selected ? .black : .white)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(item.displayName)
                    .accessibilityAddTraits(selected ? .isSelected : [])
                }
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(grades, id: \.self) { grade in
                        Button(grade) { manager.selectLogGrade(grade) }
                            .font(.caption.bold())
                            .padding(.horizontal, 8)
                            .padding(.vertical, 6)
                            .background(
                                manager.logGrade == grade ? Color.stravaOrange : Color.white.opacity(0.12),
                                in: Capsule()
                            )
                            .foregroundStyle(.white)
                            .buttonStyle(.plain)
                    }
                }
            }

            HStack(spacing: 6) {
                Button("First try") {
                    manager.logSend(
                        grade: manager.logGrade,
                        outcome: .flash,
                        discipline: manager.logDiscipline
                    )
                }
                .tint(.yellow)
                Button("Topped") {
                    manager.logSend(
                        grade: manager.logGrade,
                        outcome: .send,
                        discipline: manager.logDiscipline
                    )
                }
                .tint(.green)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
            .disabled(manager.isLocked)

            if let latest = manager.loggedSends.first {
                Text("\(latest.grade)  \(latest.outcome.displayName)")
                    .font(.caption.bold())
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Send")
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct WatchStrainPage: View {
    var manager: WorkoutManager

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                strainLine(
                    SessionClock.format(manager.climbingTime),
                    "CLIMBING"
                )
                strainLine(
                    SessionClock.format(manager.restingTime),
                    "RESTING"
                )
            }
            HStack {
                strainLine(peakBPM.map { "\($0)" } ?? "--", "PEAK BPM")
                strainLine(
                    String(format: "%.0f", manager.cardiovascularStrain),
                    "CARDIO WORK"
                )
            }
            Spacer(minLength: 4)
            HStack(alignment: .firstTextBaseline) {
                Text("BODY STRESS")
                    .font(.caption2.bold())
                    .foregroundStyle(.secondary)
                Text("0–10")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.secondary)
                Spacer()
                Text(String(format: "%.1f", manager.bodyStressIndex))
                    .font(.title3.bold().monospacedDigit())
            }
            ProgressView(value: manager.bodyStressIndex, total: 10)
                .tint(manager.bodyStressIndex >= 7 ? .red : .orange)
        }
        .padding(.horizontal, 4)
        .navigationTitle("Effort")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var peakBPM: Int? {
        manager.heartRates.map(\.bpm).max().map { Int($0.rounded()) } ?? manager.currentBPM
    }

    private func strainLine(_ value: String, _ label: String) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(value)
                .font(.headline.monospacedDigit())
            Text(label)
                .font(.caption2.bold())
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct WatchControlsPage: View {
    var manager: WorkoutManager
    @Binding var confirmEnd: Bool

    var body: some View {
        VStack(spacing: 10) {
            Button("End Workout", role: .destructive) { confirmEnd = true }
                .buttonStyle(.borderedProminent)
                .tint(.red)
                .disabled(manager.isLocked)

            Button(manager.isPaused ? "Resume" : "Pause") {
                if manager.isPaused { manager.resume() } else { manager.pause() }
            }
            .tint(.yellow)
            .buttonStyle(.borderedProminent)
            .disabled(manager.isLocked)

            Button("Lock") { manager.lock() }
                .disabled(manager.isLocked)
        }
        .font(.headline)
        .navigationTitle("End")
        .navigationBarTitleDisplayMode(.inline)
    }
}

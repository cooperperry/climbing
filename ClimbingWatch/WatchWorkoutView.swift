import SwiftUI

/// Apple Workout-style paged session. Page 1 is the glance: HR, graph, calories, gain.
struct WatchWorkoutView: View {
    @State private var manager = WorkoutManager.shared
    @State private var confirmEnd = false

    var body: some View {
        if manager.isRunning || manager.isPaused || manager.isStarting {
            TabView {
                WatchMetricsPage(manager: manager)
                WatchLandmarkPage(manager: manager)
                WatchStrainPage(manager: manager)
                WatchControlsPage(
                    manager: manager,
                    confirmEnd: $confirmEnd
                )
            }
            .tabViewStyle(.verticalPage)
            .confirmationDialog("End workout?", isPresented: $confirmEnd, titleVisibility: .visible) {
                Button("End Workout", role: .destructive) {
                    Task { await manager.end() }
                }
                Button("Keep Climbing", role: .cancel) {}
            }
        } else {
            VStack(spacing: 10) {
                Text("SummitPulse")
                    .font(.headline)
                Text("BPM, calories, and gain")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Button {
                    manager.startFromButton()
                } label: {
                    Text(manager.isStarting ? "Starting…" : "Start")
                        .frame(maxWidth: .infinity)
                }
                .controlSize(.large)
                .tint(.green)
                .buttonStyle(.borderedProminent)
                .disabled(manager.isStarting)
            }
            .padding(.horizontal, 8)
            .navigationTitle("Climb")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

struct WatchMetricsPage: View {
    var manager: WorkoutManager

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                TimelineView(.periodic(from: .now, by: 1)) { _ in
                    Text(manager.isPaused ? "PAUSED" : SessionClock.format(manager.elapsed))
                        .font(.caption.bold().monospacedDigit())
                        .foregroundStyle(.yellow)
                }
                Spacer()
                Text(manager.phase.displayName.uppercased())
                    .font(.caption2.bold())
                    .foregroundStyle(manager.phase == .climbing ? .green : .secondary)
                Text(manager.currentZone.displayName)
                    .font(.caption2.bold())
                    .foregroundStyle(.orange)
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
}

struct WatchLandmarkPage: View {
    var manager: WorkoutManager

    var body: some View {
        let progress = manager.landmarkProgress
        let remainingFt = Int((progress.remainingMeters / 0.3048).rounded())
        VStack(spacing: 6) {
            Gauge(value: progress.lapPercent) {
                Text(progress.landmark.name)
                    .font(.caption2)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            } currentValueLabel: {
                Text("\(Int((progress.lapPercent * 100).rounded()))%")
                    .font(.headline.monospacedDigit())
            }
            .gaugeStyle(.accessoryCircularCapacity)
            .tint(.green)

            Text("\(remainingFt) ft to go")
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack {
                VStack {
                    Text(ElevationFormat.gain(meters: manager.verticalGainMeters))
                        .font(.caption.bold().monospacedDigit())
                    Text("SESSION")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                VStack {
                    Text(String(format: "%.1f×", progress.completions))
                        .font(.caption.bold().monospacedDigit())
                    Text("LAPS")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
            }
        }
        .navigationTitle("Landmark")
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
                    "CLIMB"
                )
                strainLine(
                    SessionClock.format(manager.restingTime),
                    "REST"
                )
            }
            HStack {
                strainLine(peakBPM.map(String.init) ?? "--", "PEAK")
                strainLine(String(format: "%.0f", manager.cardiovascularStrain), "TRIMP")
            }
            Spacer(minLength: 4)
            HStack {
                Text("STRESS")
                    .font(.caption2.bold())
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
        VStack(spacing: 8) {
            Button(manager.isPaused ? "Resume" : "Pause") {
                if manager.isPaused { manager.resume() } else { manager.pause() }
            }
            .tint(.yellow)
            .buttonStyle(.borderedProminent)
            .disabled(manager.isLocked)

            Button("End Workout", role: .destructive) { confirmEnd = true }
                .disabled(manager.isLocked)

            Button("Lock") { manager.lock() }
                .disabled(manager.isLocked)
        }
        .font(.headline)
        .navigationTitle("Session")
        .navigationBarTitleDisplayMode(.inline)
    }
}

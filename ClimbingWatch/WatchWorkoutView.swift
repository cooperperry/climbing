import SwiftUI

/// Apple Workout-style paged session. One metric family per page.
struct WatchWorkoutView: View {
    @State private var manager = WorkoutManager.shared
    @State private var confirmEnd = false

    var body: some View {
        if manager.isRunning || manager.isPaused {
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
            VStack(spacing: 12) {
                Text("SummitPulse")
                    .font(.headline)
                Button("Start") {
                    Task { await manager.start() }
                }
                .tint(.green)
                .buttonStyle(.borderedProminent)
            }
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
                Spacer()
                TimelineView(.periodic(from: .now, by: 1)) { _ in
                    Text(manager.isPaused ? "PAUSED" : SessionClock.format(manager.elapsed))
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.yellow)
                }
            }
            Text(ElevationFormat.gain(meters: manager.verticalGainMeters))
                .font(.system(size: 34, weight: .bold, design: .rounded))
                .minimumScaleFactor(0.5)
                .lineLimit(1)
            Spacer()
            HStack(spacing: 10) {
                zoneDot
                Text(manager.currentBPM.map(String.init) ?? "--")
                    .font(.title2.bold().monospacedDigit())
                    .foregroundStyle(.red)
                Text("BPM")
                    .font(.caption2.bold())
                    .foregroundStyle(.red.opacity(0.85))
                Spacer()
                Text(manager.currentZone.displayName)
                    .font(.caption.bold())
                    .foregroundStyle(.orange)
            }
        }
        .padding(.horizontal, 4)
        .navigationTitle("Gain")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var zoneDot: some View {
        Circle()
            .fill(zoneColor)
            .frame(width: 12, height: 12)
            .overlay {
                Circle()
                    .stroke(.white.opacity(0.4), lineWidth: 2)
            }
    }

    private var zoneColor: Color {
        switch manager.currentZone {
        case .z1: return .blue
        case .z2: return .green
        case .z3: return .yellow
        case .z4: return .orange
        case .z5: return .red
        }
    }
}

struct WatchLandmarkPage: View {
    var manager: WorkoutManager

    var body: some View {
        let progress = manager.landmarkProgress
        VStack(spacing: 8) {
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
            .frame(maxWidth: .infinity)

            Text(String(format: "%.1f×", progress.completions))
                .font(.caption)
                .foregroundStyle(.secondary)

            VStack(spacing: 0) {
                Text(String(format: "%.0f", manager.verticalSpeedMPerMin))
                    .font(.title2.bold().monospacedDigit())
                Text("M/MIN")
                    .font(.caption2.bold())
                    .foregroundStyle(.secondary)
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
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text("\(Int(manager.activeCalories.rounded()))")
                    .font(.system(size: 32, weight: .bold, design: .rounded))
                    .monospacedDigit()
                Text("KCAL")
                    .font(.caption2.bold())
                    .foregroundStyle(.orange)
            }
            Text("ACTIVE")
                .font(.caption2.bold())
                .foregroundStyle(.secondary)

            Text("\(Int((manager.activeCalories + manager.restingCalories).rounded())) total")
                .font(.caption)
                .foregroundStyle(.secondary)

            Spacer()

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

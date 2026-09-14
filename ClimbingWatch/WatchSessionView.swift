import SwiftUI

/// One-screen Watch logger: glance BPM, crown for grade, two big send buttons.
struct WatchSessionView: View {
    @State private var store = WatchStore.shared
    @State private var workout = WatchWorkoutController.shared
    @State private var crownValue: Double = 0
    @State private var confirmEnd = false

    var body: some View {
        if store.snapshot.isActive {
            activeView
        } else {
            idleView
        }
    }

    private var idleView: some View {
        VStack(spacing: 12) {
            Image(systemName: "figure.climbing")
                .font(.largeTitle)
                .foregroundStyle(.stravaOrange)
            Button("Start") {
                store.startSession()
                syncCrown()
            }
            .tint(.stravaOrange)
            .buttonStyle(.borderedProminent)
        }
        .navigationTitle("Climb")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var activeView: some View {
        VStack(spacing: 6) {
            glanceHeader
            logButtons
            secondaryRow
        }
        .padding(.horizontal, 2)
        .focusable()
        .digitalCrownRotation(
            $crownValue,
            from: 0,
            through: Double(max(store.grades.count - 1, 0)),
            by: 1,
            sensitivity: .low,
            isContinuous: false,
            isHapticFeedbackEnabled: true
        )
        .onChange(of: crownValue) { _, newValue in
            let index = Int(newValue.rounded())
            guard store.grades.indices.contains(index) else { return }
            store.selectedGrade = store.grades[index]
        }
        .onAppear(perform: syncCrown)
        .onChange(of: store.selectedGrade) { _, _ in syncCrown() }
        .sensoryFeedback(.success, trigger: store.logPulse)
        .navigationTitle(store.toast ?? "Climb")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("End", role: .destructive) { confirmEnd = true }
                    .foregroundStyle(.red)
            }
        }
        .confirmationDialog("End this session?", isPresented: $confirmEnd, titleVisibility: .visible) {
            Button("End Session", role: .destructive, action: store.endSession)
            Button("Keep Climbing", role: .cancel) {}
        }
    }

    private var glanceHeader: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(alignment: .lastTextBaseline, spacing: 8) {
                Text(bpmText)
                    .font(.system(size: 40, weight: .bold, design: .rounded))
                    .foregroundStyle(.red)
                    .monospacedDigit()
                    .minimumScaleFactor(0.6)
                    .lineLimit(1)
                Text("BPM")
                    .font(.caption2.bold())
                    .foregroundStyle(.red.opacity(0.85))
                Spacer(minLength: 4)
                restOrTimer
            }
            HStack(alignment: .lastTextBaseline, spacing: 6) {
                Text(store.selectedGrade ?? "—")
                    .font(.title2.bold())
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Text("Crown")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Spacer()
            }
        }
        .accessibilityHint("Turn the Digital Crown to change grade")
    }

    @ViewBuilder
    private var restOrTimer: some View {
        TimelineView(.periodic(from: .now, by: 1)) { timeline in
            if let plan = store.restPlan {
                let phase = RecoveryMath.phase(
                    plan: plan,
                    now: timeline.date,
                    currentBPM: workout.currentBPM ?? store.liveBPM
                )
                Button(action: { store.skipRest() }) {
                    VStack(alignment: .trailing, spacing: 0) {
                        Text(phase.isFinished ? "READY" : "REST")
                            .font(.caption2.bold())
                        if case .resting(let remaining) = phase {
                            Text(SessionClock.format(remaining))
                                .font(.caption.bold())
                                .monospacedDigit()
                        }
                    }
                    .foregroundStyle(phase.isFinished ? .green : .stravaOrange)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(phase.isFinished ? "Ready to climb, tap to dismiss" : "Rest timer, tap to skip")
                .onChange(of: phase.isFinished) { _, _ in
                    store.evaluateRest(now: timeline.date)
                }
                .onAppear { store.evaluateRest(now: timeline.date) }
            } else {
                let start = store.snapshot.sessionStart ?? timeline.date
                Text(SessionClock.format(timeline.date.timeIntervalSince(start)))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
        }
    }

    private var logButtons: some View {
        HStack(spacing: 8) {
            Button {
                store.log(outcome: .flash)
            } label: {
                VStack(spacing: 1) {
                    Image(systemName: ClimbOutcome.flash.symbolName)
                    Text(ClimbOutcome.flash.displayName).font(.headline)
                    Text(ClimbOutcome.flash.logSubtitle)
                        .font(.caption2)
                        .opacity(0.9)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .tint(.yellow)
            .buttonStyle(.borderedProminent)
            .disabled(store.selectedGrade == nil)

            Button {
                store.log(outcome: .send)
            } label: {
                VStack(spacing: 1) {
                    Image(systemName: ClimbOutcome.send.symbolName)
                    Text(ClimbOutcome.send.displayName).font(.headline)
                    Text(ClimbOutcome.send.logSubtitle)
                        .font(.caption2)
                        .opacity(0.9)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .tint(.green)
            .buttonStyle(.borderedProminent)
            .disabled(store.selectedGrade == nil)
        }
        .frame(maxHeight: .infinity)
    }

    private var secondaryRow: some View {
        HStack {
            Button("Didn't send") { store.log(outcome: .attempt) }
                .font(.caption)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .disabled(store.selectedGrade == nil)
            Spacer()
            if store.snapshot.logs.first != nil {
                Button("Undo", action: store.undo)
                    .font(.caption)
            }
            Text("\(store.snapshot.climbs) · \(store.snapshot.score)")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }
    }

    private var bpmText: String {
        if let bpm = workout.currentBPM ?? store.liveBPM {
            return "\(bpm)"
        }
        return "--"
    }

    private func syncCrown() {
        let grades = store.grades
        guard let grade = store.selectedGrade, let index = grades.firstIndex(of: grade) else { return }
        let value = Double(index)
        if abs(crownValue - value) >= 0.5 {
            crownValue = value
        }
    }
}

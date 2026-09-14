import SwiftUI

/// Session logger for a 40mm watch: one number, a grade, two big buttons.
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
        VStack(spacing: 4) {
            hero
            Text(store.selectedGrade ?? "—")
                .font(.system(size: 28, weight: .bold, design: .rounded))
                .minimumScaleFactor(0.6)
                .lineLimit(1)
            logButtons
            Button("Fell") { store.log(outcome: .attempt) }
                .font(.caption.bold())
                .buttonStyle(.bordered)
                .disabled(store.selectedGrade == nil)
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
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                if store.snapshot.logs.first != nil {
                    Button("Undo", action: store.undo)
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button("End", role: .destructive) { confirmEnd = true }
                    .foregroundStyle(.red)
            }
        }
        .confirmationDialog("End this session?", isPresented: $confirmEnd, titleVisibility: .visible) {
            Button("End Session", role: .destructive, action: store.endSession)
            Button("Keep Climbing", role: .cancel) {}
        }
        .accessibilityHint("Turn the Digital Crown to change grade")
    }

    /// One number only: rest countdown, else live BPM, else session time.
    private var hero: some View {
        TimelineView(.periodic(from: .now, by: 1)) { timeline in
            let bpm = workout.currentBPM ?? store.liveBPM
            if let plan = store.restPlan {
                restHero(plan: plan, now: timeline.date, bpm: bpm)
            } else if let bpm {
                labeledNumber("\(bpm)", caption: "BPM", color: .red)
            } else {
                let start = store.snapshot.sessionStart ?? timeline.date
                labeledNumber(
                    SessionClock.format(timeline.date.timeIntervalSince(start)),
                    caption: "TIME",
                    color: .secondary
                )
            }
        }
    }

    private func restHero(plan: RestPlan, now: Date, bpm: Int?) -> some View {
        let phase = RecoveryMath.phase(plan: plan, now: now, currentBPM: bpm)
        return Button(action: { store.skipRest() }) {
            Group {
                if phase.isFinished {
                    labeledNumber("GO", caption: "READY", color: .green)
                } else if case .resting(let remaining) = phase {
                    labeledNumber(SessionClock.format(remaining), caption: "REST", color: .stravaOrange)
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(phase.isFinished ? "Ready, tap to dismiss" : "Rest timer, tap to skip")
        .onChange(of: phase.isFinished) { _, _ in
            store.evaluateRest(now: now)
        }
        .onAppear { store.evaluateRest(now: now) }
    }

    private func labeledNumber(_ value: String, caption: String, color: Color) -> some View {
        VStack(spacing: 0) {
            Text(value)
                .font(.system(size: 36, weight: .bold, design: .rounded))
                .foregroundStyle(color)
                .monospacedDigit()
                .minimumScaleFactor(0.5)
                .lineLimit(1)
            Text(caption)
                .font(.caption2.bold())
                .foregroundStyle(color.opacity(0.85))
        }
        .frame(maxWidth: .infinity)
    }

    private var logButtons: some View {
        HStack(spacing: 8) {
            Button {
                store.log(outcome: .flash)
            } label: {
                Text("Flash")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .tint(.yellow)

            Button {
                store.log(outcome: .send)
            } label: {
                Text("Send")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .tint(.green)
        }
        .font(.headline.bold())
        .buttonStyle(.borderedProminent)
        .disabled(store.selectedGrade == nil)
        .frame(maxHeight: .infinity)
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

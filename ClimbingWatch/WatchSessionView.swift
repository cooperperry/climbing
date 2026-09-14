import SwiftUI

/// Session logging on Watch: live BPM, timer, grades, Flash / Send / Didn't send.
struct WatchSessionView: View {
    @State private var store = WatchStore.shared
    @State private var workout = WatchWorkoutController.shared

    var body: some View {
        if store.snapshot.isActive {
            activeView
        } else {
            idleView
        }
    }

    private var idleView: some View {
        ScrollView {
            VStack(spacing: 10) {
                Image(systemName: "figure.climbing")
                    .font(.largeTitle)
                    .foregroundStyle(.stravaOrange)
                Text("Climbing")
                    .font(.headline)
                Button("Start Session") {
                    store.startSession()
                }
                .tint(.stravaOrange)
            }
            .padding(.top, 8)
        }
        .navigationTitle("Session")
    }

    private var activeView: some View {
        ScrollView {
            VStack(spacing: 10) {
                bpmHeader
                statsLine
                liveChart
                gradePicker
                HStack(spacing: 8) {
                    Button {
                        store.log(outcome: .flash)
                    } label: {
                        Label("Flash", systemImage: "bolt.fill")
                    }
                    .tint(.yellow)
                    .disabled(store.selectedGrade == nil)

                    Button {
                        store.log(outcome: .send)
                    } label: {
                        Label("Send", systemImage: "checkmark.circle.fill")
                    }
                    .tint(.green)
                    .disabled(store.selectedGrade == nil)
                }

                Button {
                    store.log(outcome: .attempt)
                } label: {
                    Label("Didn't send", systemImage: "arrow.uturn.up")
                }
                .disabled(store.selectedGrade == nil)

                Picker("Style", selection: Binding(
                    get: { store.selectedStyle },
                    set: { store.selectedStyle = $0 }
                )) {
                    ForEach(ClimbStyle.allCases) { style in
                        Text(style.displayName).tag(style)
                    }
                }

                if let title = store.snapshot.lastTraceTitle, let trace = store.snapshot.lastTrace, trace.hasHeartRate {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(title).font(.caption.bold())
                        WatchHeartRateChart(trace: trace)
                            .frame(height: 44)
                        if let avg = trace.averageHeartRate {
                            Text("\(avg) avg · \(trace.peakHeartRate.map { "\($0) peak" } ?? "")")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                if !store.snapshot.logs.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Recent").font(.caption.bold())
                        ForEach(store.snapshot.logs.prefix(4)) { entry in
                            HStack {
                                Image(systemName: entry.outcomeValue.symbolName)
                                Text(entry.grade)
                                    .font(.caption.bold())
                                Spacer()
                                Text(entry.outcomeValue.displayName)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }

                if store.snapshot.logs.first != nil {
                    Button("Undo last", role: .destructive, action: store.undo)
                        .font(.caption)
                }

                Button("End Session", role: .destructive, action: store.endSession)
            }
        }
        .navigationTitle("Session")
    }

    private var bpmHeader: some View {
        VStack(spacing: 0) {
            if let bpm = workout.currentBPM ?? store.liveBPM {
                Text("\(bpm)")
                    .font(.system(size: 52, weight: .bold, design: .rounded))
                    .foregroundStyle(.red)
                    .monospacedDigit()
                Text("BPM")
                    .font(.caption2.bold())
                    .foregroundStyle(.red.opacity(0.8))
            } else {
                Text("--")
                    .font(.system(size: 52, weight: .bold, design: .rounded))
                    .foregroundStyle(.secondary)
                Text("BPM")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity)
    }

    private var statsLine: some View {
        TimelineView(.periodic(from: .now, by: 1)) { timeline in
            let start = store.snapshot.sessionStart ?? timeline.date
            let elapsed = timeline.date.timeIntervalSince(start)
            Text("\(SessionClock.format(elapsed)) · \(store.snapshot.climbs) · \(store.snapshot.score) pts")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }
    }

    @ViewBuilder
    private var liveChart: some View {
        let recent = WatchWorkoutController.shared.recentHeartRates(seconds: 90)
        if recent.count >= 2 {
            WatchHeartRateChart(
                trace: EffortMath.trace(
                    heartRates: recent,
                    start: Date(timeIntervalSince1970: recent.first?.timestamp ?? 0),
                    end: Date(timeIntervalSince1970: recent.last?.timestamp ?? 0)
                )
            )
            .frame(height: 36)
        }
    }

    private var gradePicker: some View {
        Picker("Grade", selection: Binding(
            get: { store.selectedGrade },
            set: { store.selectedGrade = $0 }
        )) {
            ForEach(store.grades, id: \.self) { grade in
                Text(grade).tag(Optional(grade))
            }
        }
        .pickerStyle(.wheel)
        .frame(height: 55)
    }
}

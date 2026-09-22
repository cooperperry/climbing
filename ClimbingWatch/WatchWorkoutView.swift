import SwiftUI

/// Apple Workout-style session: swipe down through Now, Send, Effort;
/// swipe left for End.
struct WatchWorkoutView: View {
    @State private var manager = WorkoutManager.shared
    @State private var confirmEnd = false

    var body: some View {
        if manager.isRunning || manager.isPaused {
            TabView {
                TabView {
                    WatchMetricsPage(manager: manager)
                    WatchLogPage(manager: manager)
                    WatchStrainPage(manager: manager)
                }
                .tabViewStyle(.verticalPage)

                WatchControlsPage(
                    manager: manager,
                    confirmEnd: $confirmEnd
                )
            }
            .tabViewStyle(.page)
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
            .onAppear {
                manager.ensureIdle()
                WatchStore.shared.requestGymMap()
            }
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
    @State private var floorName = ""

    private var grades: [String] {
        manager.logDiscipline.usesRopeGrades
            ? GradeScaleTemplate.standardYDS().grades
            : GradeScaleTemplate.standardVScale().grades
    }

    private var floors: [String] {
        Array(Set(manager.gymWalls.map(\.floor))).sorted()
    }

    private var selectedFloor: String {
        floors.contains(floorName) ? floorName : (floors.first ?? "Main")
    }

    private var boulders: [WatchBoulderRow] {
        let rows = manager.gymWalls
            .filter { $0.floor == selectedFloor }
            .flatMap { wall in
                wall.routes.map { WatchBoulderRow(wall: wall, pin: $0) }
            }
        return rows.sorted { lhs, rhs in
            let left = gradeRank(lhs.pin)
            let right = gradeRank(rhs.pin)
            if left != right { return left < right }
            if lhs.pin.color != rhs.pin.color { return lhs.pin.color < rhs.pin.color }
            return lhs.wall.name < rhs.wall.name
        }
    }

    var body: some View {
        Group {
            if manager.gymWalls.flatMap(\.routes).isEmpty {
                fallbackLogger
            } else {
                List {
                    if floors.count > 1 {
                        Picker("Level", selection: $floorName) {
                            ForEach(floors, id: \.self) { floor in
                                Text(floor).tag(floor)
                            }
                        }
                        .pickerStyle(.navigationLink)
                    }
                    ForEach(boulders) { row in
                        NavigationLink {
                            WatchBoulderDetail(wall: row.wall, pin: row.pin, manager: manager)
                        } label: {
                            HStack(spacing: 8) {
                                Circle()
                                    .fill(Color(hold: row.pin.holdColor))
                                    .frame(width: 16, height: 16)
                                VStack(alignment: .leading, spacing: 0) {
                                    Text(row.pin.grade)
                                        .font(.headline)
                                    Text("\(row.pin.holdColor.displayName) · \(row.wall.name == "Untitled" ? "Unnamed wall" : row.wall.name)")
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                }
                            }
                        }
                    }
                }
                .listStyle(.carousel)
            }
        }
        .navigationTitle(floors.count > 1 ? selectedFloor : (manager.gymName ?? "Send"))
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            WatchStore.shared.requestGymMap()
            if floors.contains(floorName) == false {
                floorName = floors.first ?? ""
            }
        }
        .onChange(of: floors) { _, names in
            if names.contains(floorName) == false {
                floorName = names.first ?? ""
            }
        }
    }

    private func gradeRank(_ pin: WatchRoutePin) -> Int {
        let scale = pin.disciplineValue.usesRopeGrades
            ? GradeScaleTemplate.standardYDS()
            : GradeScaleTemplate.standardVScale()
        return scale.index(of: pin.grade) ?? 1_000
    }

    private var fallbackLogger: some View {
        VStack(alignment: .leading, spacing: 6) {
            if manager.gymName == nil {
                Text("Open Climber on your phone")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            } else {
                Text("Add walls on the phone floor plan")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
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
                Button("Flashed") {
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
        }
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

            Button(manager.isPaused ? "Resume" : "Pause") {
                if manager.isPaused { manager.resume() } else { manager.pause() }
            }
            .tint(.yellow)
            .buttonStyle(.borderedProminent)
        }
        .font(.headline)
        .navigationTitle("End")
        .navigationBarTitleDisplayMode(.inline)
    }
}

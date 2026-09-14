import SwiftUI
import SwiftData

/// The app's home screen: a prominent live session timer plus a low-friction
/// logging flow. The climber tallies goes and taps a single **Send** button —
/// the app derives flash vs. redpoint from the go count, so there's nothing to
/// decide mid-session.
struct SessionView: View {
    @Environment(\.modelContext) private var context

    @Query(
        filter: #Predicate<ClimbingSession> { $0.endTime == nil },
        sort: \ClimbingSession.startTime,
        order: .reverse
    )
    private var activeSessions: [ClimbingSession]

    @Query(sort: \CustomGradeScale.createdAt)
    private var scales: [CustomGradeScale]

    @State private var selectedGrade: String?
    @State private var selectedStyle: ClimbStyle = .crimp
    @State private var selectedAngle: ClimbAngle = .vertical
    @State private var currentGo: Int = 1
    @State private var showingInfo = false
    @State private var lastLog: ClimbLog?
    @State private var sendTrigger = 0
    @State private var goTrigger = 0

    private var activeSession: ClimbingSession? { activeSessions.first }

    private var defaultScale: CustomGradeScale? {
        scales.first { $0.isDefault } ?? scales.first
    }

    var body: some View {
        NavigationStack {
            Group {
                if let session = activeSession {
                    activeSessionView(session)
                } else {
                    idleView
                }
            }
            .navigationTitle("Climbing")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        showingInfo = true
                    } label: {
                        Image(systemName: "questionmark.circle")
                    }
                }
                if activeSession != nil {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("End", role: .destructive, action: endSession)
                    }
                }
            }
        }
        .sheet(isPresented: $showingInfo) { DefinitionsView() }
        .sensoryFeedback(.success, trigger: sendTrigger)
        .sensoryFeedback(.impact(weight: .light), trigger: goTrigger)
        .onAppear(perform: prepareSession)
    }

    // MARK: - Idle state

    private var idleView: some View {
        ContentUnavailableView {
            Label("No Active Session", systemImage: "figure.climbing")
        } description: {
            Text("Start a session to track your time on the wall and log climbs.")
        } actions: {
            Button(action: startSession) {
                Text("Start Session")
                    .font(.headline)
                    .padding(.horizontal)
            }
            .buttonStyle(.borderedProminent)
        }
    }

    // MARK: - Active state

    private func activeSessionView(_ session: ClimbingSession) -> some View {
        ScrollView {
            VStack(spacing: 20) {
                timerHeader(session)
                gradePicker
                anglePicker
                stylePicker
                currentClimbCard(session)
                recentLogs(session)
            }
            .padding()
        }
    }

    /// The prominent, always-ticking session timer.
    private func timerHeader(_ session: ClimbingSession) -> some View {
        TimelineView(.periodic(from: .now, by: 1)) { timeline in
            VStack(spacing: 4) {
                Text(SessionClock.format(session.duration(asOf: timeline.date)))
                    .font(.system(size: 64, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .contentTransition(.numericText())
                Text("\(session.logs.count) climbs • \(session.completionCount) sent • \(session.score) pts")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 24)
            .background(.tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 24))
        }
    }

    private var gradePicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Grade").font(.headline)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(defaultScale?.grades ?? [], id: \.self) { grade in
                        chip(title: grade, isSelected: grade == selectedGrade) {
                            selectedGrade = grade
                        }
                    }
                }
                .padding(.horizontal, 1)
            }
        }
    }

    private var anglePicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Angle").font(.headline)
            HStack(spacing: 8) {
                ForEach(ClimbAngle.allCases) { angle in
                    chip(
                        title: angle.displayName,
                        systemImage: angle.symbolName,
                        isSelected: angle == selectedAngle
                    ) {
                        selectedAngle = angle
                    }
                }
            }
        }
    }

    private var stylePicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Style").font(.headline)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(ClimbStyle.quickTap) { style in
                        chip(
                            title: style.displayName,
                            systemImage: style.symbolName,
                            isSelected: style == selectedStyle
                        ) {
                            selectedStyle = style
                        }
                    }
                }
                .padding(.horizontal, 1)
            }
        }
    }

    /// The seamless logging control: tally goes, then tap Send (auto flash/send)
    /// or save as a project.
    private func currentClimbCard(_ session: ClimbingSession) -> some View {
        VStack(spacing: 16) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("CURRENT CLIMB")
                        .font(.caption2.bold())
                        .foregroundStyle(.secondary)
                    Text(selectedGrade ?? "Pick a grade")
                        .font(.title.bold())
                }
                Spacer()
                goStepper
            }

            Button(action: { logSend(in: session) }) {
                VStack(spacing: 2) {
                    Text("Send")
                        .font(.headline)
                    Text(currentGo <= 1 ? "Flash — first try" : "Redpoint — go \(currentGo)")
                        .font(.caption)
                        .opacity(0.9)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
            }
            .buttonStyle(.borderedProminent)
            .tint(.green)
            .disabled(selectedGrade == nil)

            HStack(spacing: 12) {
                Button {
                    addGo()
                } label: {
                    Label("Add Go", systemImage: "plus.circle.fill")
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                }
                .buttonStyle(.bordered)
                .disabled(selectedGrade == nil)

                Button {
                    logProject(in: session)
                } label: {
                    Label("Project", systemImage: "hammer.fill")
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                }
                .buttonStyle(.bordered)
                .tint(.orange)
                .disabled(selectedGrade == nil)
            }

            if let lastLog {
                Button(role: .destructive) {
                    undo(lastLog)
                } label: {
                    Label("Undo last (\(lastLog.gradeLabel) \(lastLog.outcome.displayName))",
                          systemImage: "arrow.uturn.backward")
                        .font(.footnote)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
            }
        }
        .padding()
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 20))
    }

    private var goStepper: some View {
        HStack(spacing: 12) {
            Button {
                if currentGo > 1 { currentGo -= 1 }
            } label: {
                Image(systemName: "minus.circle.fill")
            }
            .disabled(currentGo <= 1)

            VStack(spacing: 0) {
                Text("\(currentGo)")
                    .font(.title2.bold())
                    .monospacedDigit()
                Text("GO").font(.caption2).foregroundStyle(.secondary)
            }
            .frame(minWidth: 36)

            Button {
                addGo()
            } label: {
                Image(systemName: "plus.circle.fill")
            }
        }
        .font(.title2)
        .tint(.stravaOrange)
    }

    @ViewBuilder
    private func recentLogs(_ session: ClimbingSession) -> some View {
        let recent = session.logs.sorted { $0.loggedAt > $1.loggedAt }.prefix(6)
        if !recent.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text("Recent").font(.headline)
                ForEach(Array(recent)) { log in
                    HStack(spacing: 10) {
                        Image(systemName: log.outcome.symbolName)
                            .foregroundStyle(color(for: log.outcome))
                        Text(log.gradeLabel).bold()
                        Text("\(log.style.displayName) • \(log.angle.displayName)")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text("^[\(log.attempts) go](inflect: true)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 4)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: - Reusable chip

    private func chip(
        title: String,
        systemImage: String? = nil,
        isSelected: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 4) {
                if let systemImage {
                    Image(systemName: systemImage)
                }
                Text(title)
            }
            .font(.subheadline.bold())
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(
                isSelected ? AnyShapeStyle(.tint) : AnyShapeStyle(.quaternary),
                in: Capsule()
            )
            .foregroundStyle(isSelected ? Color.white : Color.primary)
        }
        .buttonStyle(.plain)
    }

    private func color(for outcome: ClimbOutcome) -> Color {
        switch outcome {
        case .flash: return .yellow
        case .send: return .green
        case .project: return .orange
        case .attempt: return .blue
        }
    }

    // MARK: - Actions

    private func startSession() {
        let session = ClimbingSession()
        context.insert(session)
        try? context.save()
    }

    private func endSession() {
        guard let session = activeSession else { return }
        session.endTime = .now
        try? context.save()
        currentGo = 1
        lastLog = nil
    }

    private func addGo() {
        currentGo += 1
        goTrigger += 1
    }

    private func logSend(in session: ClimbingSession) {
        log(outcome: ClimbOutcome.topOut(attempts: currentGo), in: session)
    }

    private func logProject(in session: ClimbingSession) {
        log(outcome: .project, in: session)
    }

    private func log(outcome: ClimbOutcome, in session: ClimbingSession) {
        guard let grade = selectedGrade else { return }
        let entry = ClimbLog(
            gradeLabel: grade,
            attempts: currentGo,
            outcome: outcome,
            style: selectedStyle,
            angle: selectedAngle,
            session: session,
            gradeScale: defaultScale
        )
        context.insert(entry)
        try? context.save()
        lastLog = entry
        sendTrigger += 1
        currentGo = 1
    }

    private func undo(_ log: ClimbLog) {
        context.delete(log)
        try? context.save()
        lastLog = nil
    }

    /// Seeds a default V-scale on first launch and preselects a starting grade.
    private func prepareSession() {
        let scale: CustomGradeScale?
        if scales.isEmpty {
            let seeded = CustomGradeScale(template: .standardVScale(), isDefault: true)
            context.insert(seeded)
            try? context.save()
            scale = seeded
        } else {
            scale = defaultScale
        }
        if selectedGrade == nil {
            selectedGrade = scale?.grades.first
        }
    }
}

#Preview {
    SessionView()
        .modelContainer(for: [ClimbingSession.self, ClimbLog.self, CustomGradeScale.self],
                        inMemory: true)
}

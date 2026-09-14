import SwiftUI
import SwiftData

/// The app's home screen: a prominent live session timer plus quick-tap
/// controls to log climbs without breaking flow between burns.
struct SessionView: View {
    @Environment(\.modelContext) private var context

    /// The most recently started session that has not been ended.
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
    @State private var attempts: Int = 1

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
                if activeSession != nil {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("End", role: .destructive, action: endSession)
                    }
                }
            }
        }
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
                stylePicker
                attemptsStepper
                outcomeButtons(session)
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
                Text("\(session.logs.count) climbs • \(session.completionCount) sent")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
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

    private var attemptsStepper: some View {
        Stepper(value: $attempts, in: 1...50) {
            HStack {
                Text("Attempts").font(.headline)
                Spacer()
                Text("\(attempts)")
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
        }
    }

    /// The quick-tap logging row: one button per outcome.
    private func outcomeButtons(_ session: ClimbingSession) -> some View {
        HStack(spacing: 12) {
            ForEach(ClimbOutcome.allCases) { outcome in
                Button {
                    logClimb(outcome: outcome, in: session)
                } label: {
                    VStack(spacing: 6) {
                        Image(systemName: outcome.symbolName).font(.title2)
                        Text(outcome.displayName).font(.caption).bold()
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                }
                .buttonStyle(.borderedProminent)
                .tint(color(for: outcome))
                .disabled(selectedGrade == nil)
            }
        }
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
                        Text(log.style.displayName).foregroundStyle(.secondary)
                        Spacer()
                        Text("^[\(log.attempts) attempt](inflect: true)")
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
    }

    private func logClimb(outcome: ClimbOutcome, in session: ClimbingSession) {
        guard let grade = selectedGrade else { return }
        let log = ClimbLog(
            gradeLabel: grade,
            attempts: attempts,
            outcome: outcome,
            style: selectedStyle,
            session: session,
            gradeScale: defaultScale
        )
        context.insert(log)
        try? context.save()
        attempts = 1
    }

    /// Seeds a default V-scale on first launch and preselects a starting grade.
    ///
    /// The seeded instance is used directly rather than reading back through the
    /// `scales` @Query, which does not reflect the insert synchronously within
    /// this same call.
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

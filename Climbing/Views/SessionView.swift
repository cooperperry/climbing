import SwiftUI
import SwiftData

/// The app's home screen. Logging is a single tap in plain language — Flash,
/// Send, or Didn't send — with instant points feedback, plus a live timer,
/// running score, and Apple Watch health metrics.
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
    @State private var showingInfo = false
    @State private var lastLog: ClimbLog?
    @State private var sendTrigger = 0
    @State private var floatingGain: Int?
    @State private var health = HealthManager()

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
                    Button { showingInfo = true } label: {
                        Image(systemName: "questionmark.circle")
                    }
                }
                if activeSession != nil {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("End", role: .destructive, action: endSession)
                    }
                }
            }
            .overlay(alignment: .top) { floatingGainBadge }
        }
        .sheet(isPresented: $showingInfo) { DefinitionsView() }
        .sensoryFeedback(.success, trigger: sendTrigger)
        .onAppear(perform: prepareSession)
    }

    // MARK: - Idle

    private var idleView: some View {
        ContentUnavailableView {
            Label("No Active Session", systemImage: "figure.climbing")
        } description: {
            Text("Start a session to track your time on the wall and log climbs.")
        } actions: {
            Button(action: startSession) {
                Text("Start Session").font(.headline).padding(.horizontal)
            }
            .buttonStyle(.borderedProminent)
        }
    }

    // MARK: - Active

    private func activeSessionView(_ session: ClimbingSession) -> some View {
        ScrollView {
            VStack(spacing: 20) {
                timerHeader(session)
                HealthCard(summary: health.summary, status: health.status) {
                    Task {
                        await health.requestAuthorization()
                        await health.refresh(from: session.startTime, to: .now)
                    }
                }
                logCard(session)
                recentLogs(session)
            }
            .padding()
        }
        .task(id: session.startTime) {
            while !Task.isCancelled {
                await health.refresh(from: session.startTime, to: .now)
                try? await Task.sleep(for: .seconds(20))
            }
        }
    }

    private func timerHeader(_ session: ClimbingSession) -> some View {
        TimelineView(.periodic(from: .now, by: 1)) { timeline in
            VStack(spacing: 4) {
                Text(SessionClock.format(session.duration(asOf: timeline.date)))
                    .font(.system(size: 60, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .contentTransition(.numericText())
                Text("\(session.logs.count) climbs • \(session.completionCount) sent • \(session.score) pts")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                    .contentTransition(.numericText())
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 20)
            .background(.tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 24))
        }
    }

    // MARK: - Logging

    private func logCard(_ session: ClimbingSession) -> some View {
        VStack(spacing: 16) {
            gradePicker

            HStack(spacing: 12) {
                logButton(
                    title: "Flash", subtitle: "First try",
                    systemImage: "bolt.fill", tint: .yellow
                ) { log(outcome: .flash, attempts: 1, in: session) }

                logButton(
                    title: "Send", subtitle: "After a few tries",
                    systemImage: "checkmark.circle.fill", tint: .green
                ) { log(outcome: .send, attempts: 2, in: session) }
            }

            HStack {
                Button {
                    log(outcome: .attempt, attempts: 1, in: session)
                } label: {
                    Label("Didn't send", systemImage: "arrow.uturn.up")
                }
                .buttonStyle(.bordered)
                .disabled(selectedGrade == nil)

                Spacer()

                styleMenu
            }

            if let lastLog {
                Button(role: .destructive) {
                    undo(lastLog)
                } label: {
                    Label("Undo last (\(lastLog.gradeLabel))", systemImage: "arrow.uturn.backward")
                        .font(.footnote)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
            }
        }
        .padding()
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 20))
    }

    private var gradePicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Grade").font(.headline).frame(maxWidth: .infinity, alignment: .leading)
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

    private func logButton(
        title: String, subtitle: String, systemImage: String, tint: Color,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: systemImage).font(.title2)
                Text(title).font(.headline)
                Text(subtitle).font(.caption2).opacity(0.9)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
        }
        .buttonStyle(.borderedProminent)
        .tint(tint)
        .disabled(selectedGrade == nil)
    }

    private var styleMenu: some View {
        Menu {
            Picker("Style", selection: $selectedStyle) {
                ForEach(ClimbStyle.allCases) { style in
                    Text(style.displayName).tag(style)
                }
            }
        } label: {
            Label(selectedStyle.displayName, systemImage: "tag")
                .font(.subheadline)
        }
    }

    @ViewBuilder
    private var floatingGainBadge: some View {
        if let floatingGain {
            Text("+\(floatingGain)")
                .font(.title.bold())
                .foregroundStyle(.stravaOrange)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(.regularMaterial, in: Capsule())
                .padding(.top, 8)
                .transition(.move(edge: .top).combined(with: .opacity))
        }
    }

    @ViewBuilder
    private func recentLogs(_ session: ClimbingSession) -> some View {
        let recent = session.logs.sorted { $0.loggedAt > $1.loggedAt }.prefix(6)
        if !recent.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text("Recent").font(.headline)
                ForEach(Array(recent)) { entry in
                    HStack(spacing: 10) {
                        Image(systemName: entry.outcome.symbolName)
                            .foregroundStyle(color(for: entry.outcome))
                        Text(entry.gradeLabel).bold()
                        Text(entry.style.displayName)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text(entry.outcome.displayName)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 4)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: - Reusable

    private func chip(title: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.subheadline.bold())
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
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
        lastLog = nil
    }

    private func log(outcome: ClimbOutcome, attempts: Int, in session: ClimbingSession) {
        guard let grade = selectedGrade else { return }
        let entry = ClimbLog(
            gradeLabel: grade,
            attempts: attempts,
            outcome: outcome,
            style: selectedStyle,
            session: session,
            gradeScale: defaultScale
        )
        context.insert(entry)
        try? context.save()
        lastLog = entry
        sendTrigger += 1
        showGain(entry.points)
    }

    private func showGain(_ points: Int) {
        withAnimation(.spring) { floatingGain = points }
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(1))
            withAnimation { floatingGain = nil }
        }
    }

    private func undo(_ entry: ClimbLog) {
        context.delete(entry)
        try? context.save()
        lastLog = nil
    }

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

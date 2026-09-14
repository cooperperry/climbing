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

    @Query private var allSessions: [ClimbingSession]

    @State private var selectedGrade: String?
    @State private var showingInfo = false
    @State private var tagTick = 0
    @State private var sendTrigger = 0
    @State private var floatingGain: Int?
    @State private var summarySession: ClimbingSession?
    @State private var summaryRecords: [PersonalRecord] = []
    @State private var liveTrace: EffortTrace?
    @State private var liveTraceTitle = "Heart rate"
    @State private var bridge = PhoneWatchBridge.shared

    private var health: HealthManager { bridge.health }
    private var liveBPM: Int? { bridge.liveBPM }

    private var activeSession: ClimbingSession? { activeSessions.first }

    private var defaultScale: CustomGradeScale? {
        scales.first { $0.isDefault } ?? scales.first
    }

    private var strip: (title: String, trace: EffortTrace)? {
        if let liveTrace { return (liveTraceTitle, liveTrace) }
        guard let log = activeSession?.logs.filter(\.outcome.isCompletion).max(by: { $0.loggedAt < $1.loggedAt }),
              let trace = log.effortTrace else { return nil }
        return ("\(log.gradeLabel) \(log.outcome.displayName)", trace)
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
        .sheet(item: $summarySession) { session in
            SessionSummaryView(session: session, records: summaryRecords, health: health.summary)
        }
        .sensoryFeedback(.success, trigger: sendTrigger)
        .onAppear {
            prepareSession()
            PhoneWatchBridge.shared.attach(context: context)
            PhoneWatchBridge.shared.selectedGrade = selectedGrade
            if activeSession != nil { beginWatchCapture() }
        }
        .onChange(of: selectedGrade) { _, grade in
            PhoneWatchBridge.shared.selectedGrade = grade
            PhoneWatchBridge.shared.publishSnapshot()
        }
        .onChange(of: activeSessions.count) { _, _ in
            PhoneWatchBridge.shared.publishSnapshot()
        }
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
                restBanner
                HealthCard(
                    summary: health.summary,
                    status: health.status,
                    liveBPM: liveBPM
                ) {
                    Task {
                        await health.requestAuthorization()
                        await health.refresh(from: session.startTime, to: .now)
                        await health.startWatchWorkout()
                    }
                }
                logCard(session)
                if let strip {
                    EffortStripView(trace: strip.trace, title: strip.title)
                }
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

    @ViewBuilder
    private var restBanner: some View {
        if let plan = bridge.restPlan {
            TimelineView(.periodic(from: .now, by: 1)) { timeline in
                let phase = RecoveryMath.phase(
                    plan: plan,
                    now: timeline.date,
                    currentBPM: liveBPM
                )
                HStack(spacing: 12) {
                    Image(systemName: phase.isFinished ? "checkmark.circle.fill" : "hourglass")
                        .font(.title2)
                        .foregroundStyle(phase.isFinished ? .green : .stravaOrange)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(phase.isFinished ? "Ready" : "Rest")
                            .font(.headline)
                        if case .resting(let remaining) = phase {
                            Text(SessionClock.format(remaining))
                                .font(.title3.bold())
                                .monospacedDigit()
                                .foregroundStyle(.stravaOrange)
                            if let target = plan.targetBPM {
                                Text("Until \(target) bpm or timer")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        } else if phase == .recovered {
                            Text("Heart rate recovered")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        } else {
                            Text("Timer up — go when you're ready")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }
                    Spacer()
                    Button("Skip", action: PhoneWatchBridge.shared.skipRest)
                        .font(.subheadline.bold())
                }
                .padding()
                .background(
                    (phase.isFinished ? Color.green : Color.stravaOrange).opacity(0.14),
                    in: RoundedRectangle(cornerRadius: 20)
                )
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
                if let liveBPM {
                    Label("\(liveBPM) bpm", systemImage: "heart.fill")
                        .font(.headline)
                        .foregroundStyle(.red)
                        .monospacedDigit()
                        .contentTransition(.numericText())
                }
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
                    title: ClimbOutcome.flash.displayName,
                    subtitle: ClimbOutcome.flash.logSubtitle,
                    systemImage: ClimbOutcome.flash.symbolName, tint: .yellow
                ) { log(outcome: .flash, attempts: 1, in: session) }

                logButton(
                    title: ClimbOutcome.send.displayName,
                    subtitle: "After a few tries",
                    systemImage: ClimbOutcome.send.symbolName, tint: .green
                ) { log(outcome: .send, attempts: 2, in: session) }
            }

            Button {
                log(outcome: .attempt, attempts: 1, in: session)
            } label: {
                Label(ClimbOutcome.attempt.displayName, systemImage: ClimbOutcome.attempt.symbolName)
            }
            .buttonStyle(.bordered)
            .disabled(selectedGrade == nil)

            if let latest = session.logs.max(by: { $0.loggedAt < $1.loggedAt }) {
                lastClimbTags(latest)
                    .id("\(latest.loggedAt.timeIntervalSince1970)-\(tagTick)")
                Button(role: .destructive) {
                    undo(latest)
                } label: {
                    Label("Undo last (\(latest.gradeLabel))", systemImage: "arrow.uturn.backward")
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

    private func lastClimbTags(_ log: ClimbLog) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text("How did it feel?")
                    .font(.subheadline.bold())
                Text("Optional. A climb can be both — crimps on an overhang.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            tagRow(title: "Holds") {
                ForEach(ClimbStyle.quickTap) { style in
                    chip(title: style.displayName, isSelected: log.style == style) {
                        log.style = log.style == style ? nil : style
                        saveTags()
                    }
                }
            }

            tagRow(title: "Wall") {
                ForEach(ClimbAngle.allCases) { angle in
                    chip(title: angle.displayName, isSelected: log.angle == angle) {
                        log.angle = log.angle == angle ? nil : angle
                        saveTags()
                    }
                }
            }
        }
        .padding(.top, 4)
    }

    private func tagRow<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption.bold())
                .foregroundStyle(.secondary)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    content()
                }
            }
        }
    }

    private func saveTags() {
        tagTick += 1
        try? context.save()
        PhoneWatchBridge.shared.publishSnapshot()
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
                        if let tags = tagSummary(entry) {
                            Text(tags)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
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

    private func tagSummary(_ entry: ClimbLog) -> String? {
        let parts = [entry.style?.displayName, entry.angle?.displayName].compactMap { $0 }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

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
        beginWatchCapture()
    }

    private func endSession() {
        guard let session = activeSession else { return }
        session.endTime = .now
        let previous = SessionRecords.previousBests(excluding: session, in: allSessions)
        summaryRecords = RecordsEngine.newRecords(
            current: session.totals(),
            hardestSendGradeLabel: session.hardestSend?.gradeLabel,
            previous: previous
        )
        try? context.save()
        liveTrace = nil
        summarySession = session
        PhoneWatchBridge.shared.stopWatchSide()
    }

    private func log(outcome: ClimbOutcome, attempts: Int, in session: ClimbingSession) {
        guard let grade = selectedGrade else { return }
        let previousLogAt = session.logs.map(\.loggedAt).max()
        let entry = ClimbLog(
            gradeLabel: grade,
            attempts: attempts,
            outcome: outcome,
            session: session,
            gradeScale: defaultScale
        )
        context.insert(entry)
        try? context.save()
        sendTrigger += 1
        showGain(entry.points)
        PhoneWatchBridge.shared.publishSnapshot()
        PhoneWatchBridge.shared.beginRest(currentBPM: liveBPM)
        if outcome.isCompletion {
            liveTraceTitle = "\(grade) \(outcome.displayName)"
            liveTrace = EffortTrace()
            Task { await captureEffort(for: entry, in: session, previousLogAt: previousLogAt) }
        } else {
            liveTrace = nil
        }
    }

    private func captureEffort(
        for entry: ClimbLog,
        in session: ClimbingSession,
        previousLogAt: Date?
    ) async {
        let bounds = EffortWindow.bounds(
            loggedAt: entry.loggedAt,
            sessionStart: session.startTime,
            previousLogAt: previousLogAt
        )
        async let watchHR = PhoneWatchBridge.shared.heartRates(from: bounds.start, to: bounds.end)
        async let healthHR = health.heartRateTimeline(from: bounds.start, to: bounds.end)
        let watchSamples = await watchHR
        let healthSamples = await healthHR
        var trace = EffortMath.trace(
            heartRates: watchSamples.isEmpty ? healthSamples : watchSamples,
            start: bounds.start,
            end: bounds.end
        )
        #if targetEnvironment(simulator)
        if !trace.hasData {
            trace = .demo
        }
        #endif
        liveTraceTitle = "\(entry.gradeLabel) \(entry.outcome.displayName)"
        liveTrace = trace
        if trace.hasData {
            entry.effortTrace = trace
            try? context.save()
            PhoneWatchBridge.shared.publishSnapshot()
        }
    }

    private func beginWatchCapture() {
        PhoneWatchBridge.shared.startWatchSide()
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
        liveTrace = nil
        PhoneWatchBridge.shared.skipRest()
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

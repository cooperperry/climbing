import SwiftUI
import SwiftData

/// Phone-first route log. No Watch required — pick boulder / top rope / lead,
/// a grade, and whether you topped it.
struct RouteLogView: View {
    @Environment(\.modelContext) private var context

    @Query(
        filter: #Predicate<ClimbingSession> { $0.endTime == nil },
        sort: \ClimbingSession.startTime,
        order: .reverse
    )
    private var activeSessions: [ClimbingSession]

    @Query(sort: \ClimbLog.loggedAt, order: .reverse)
    private var logs: [ClimbLog]

    @Query(sort: \CustomGradeScale.createdAt)
    private var scales: [CustomGradeScale]

    @Query(sort: \ClimbGym.joinedAt, order: .reverse)
    private var gyms: [ClimbGym]

    @State private var discipline: ClimbDiscipline = .boulder
    @State private var selectedGrade: String?
    @State private var sendTrigger = 0

    private var scale: CustomGradeScale? {
        let kind: GradeScaleKind = discipline.usesRopeGrades ? .yds : .boulderVScale
        return scales.first { $0.kind == kind } ?? scales.first { $0.isDefault } ?? scales.first
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    currentGymBanner
                    disciplinePicker
                    gradePicker
                    logActions
                    history
                }
                .padding()
            }
            .navigationTitle("Routes")
            .onAppear(perform: prepare)
            .onChange(of: discipline) { _, _ in
                selectedGrade = scale?.grades.first
            }
            .sensoryFeedback(.success, trigger: sendTrigger)
        }
    }

    private var currentGym: ClimbGym? { gyms.first(where: \.isCurrent) }

    @ViewBuilder
    private var currentGymBanner: some View {
        if let gym = currentGym {
            HStack {
                Image(systemName: "building.2.fill")
                Text("At \(gym.name)")
                    .font(.subheadline.bold())
                Spacer()
            }
            .padding(12)
            .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12))
        } else {
            Text("Join a gym on the Gyms tab. Snap the wall you're on to log sends there.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var disciplinePicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Type")
                .font(.headline)
            HStack(spacing: 8) {
                ForEach(ClimbDiscipline.allCases) { item in
                    Button {
                        discipline = item
                    } label: {
                        VStack(spacing: 4) {
                            Image(systemName: item.symbolName)
                            Text(item.displayName)
                                .font(.caption.bold())
                                .lineLimit(1)
                                .minimumScaleFactor(0.8)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(
                            discipline == item ? Color.stravaOrange : Color(.secondarySystemBackground),
                            in: RoundedRectangle(cornerRadius: 14)
                        )
                        .foregroundStyle(discipline == item ? Color.white : Color.primary)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var gradePicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(discipline.usesRopeGrades ? "YDS grade" : "V-grade")
                .font(.headline)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(scale?.grades ?? [], id: \.self) { grade in
                        Button {
                            selectedGrade = grade
                        } label: {
                            Text(grade)
                                .font(.subheadline.bold())
                                .padding(.horizontal, 14)
                                .padding(.vertical, 10)
                                .background(
                                    selectedGrade == grade ? AnyShapeStyle(.stravaOrange) : AnyShapeStyle(.quaternary),
                                    in: Capsule()
                                )
                                .foregroundStyle(selectedGrade == grade ? Color.white : Color.primary)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private var logActions: some View {
        VStack(spacing: 10) {
            HStack(spacing: 12) {
                actionButton(
                    title: "First try",
                    subtitle: "Flashed it",
                    systemImage: "bolt.fill",
                    tint: .yellow
                ) { log(outcome: .flash, attempts: 1) }

                actionButton(
                    title: "Topped it",
                    subtitle: "After some tries",
                    systemImage: "checkmark.circle.fill",
                    tint: .green
                ) { log(outcome: .send, attempts: 2) }
            }

            Button {
                log(outcome: .project, attempts: 1)
            } label: {
                Label("Still working", systemImage: "hammer.fill")
            }
            .buttonStyle(.bordered)
            .disabled(selectedGrade == nil)
        }
        .padding()
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 20))
    }

    private func actionButton(
        title: String,
        subtitle: String,
        systemImage: String,
        tint: Color,
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

    @ViewBuilder
    private var history: some View {
        let start = Calendar.current.startOfDay(for: .now)
        let today = logs.filter { $0.loggedAt >= start }
        if today.isEmpty {
            Text("Today's tops show here. Open Sessions to see past workouts.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            VStack(alignment: .leading, spacing: 12) {
                Text("Today")
                    .font(.headline)
                ForEach(ClimbDiscipline.allCases) { item in
                    let rows = today.filter { $0.resolvedDiscipline == item }
                    if !rows.isEmpty {
                        Text(item.displayName)
                            .font(.caption.bold())
                            .foregroundStyle(.secondary)
                        ForEach(rows) { entry in
                            HStack(spacing: 10) {
                                Image(systemName: entry.outcome.symbolName)
                                    .foregroundStyle(entry.outcome.isCompletion ? .green : .orange)
                                Text(entry.gradeLabel).bold()
                                Spacer()
                                Text(entry.outcome.displayName)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func log(outcome: ClimbOutcome, attempts: Int) {
        guard let grade = selectedGrade else { return }
        let entry = ClimbLog(
            gradeLabel: grade,
            attempts: attempts,
            outcome: outcome,
            discipline: discipline,
            gym: currentGym,
            session: todaySession(),
            gradeScale: scale
        )
        context.insert(entry)
        try? context.save()
        sendTrigger += 1
    }

    private func todaySession() -> ClimbingSession {
        if let existing = activeSessions.first { return existing }
        let session = ClimbingSession()
        context.insert(session)
        try? context.save()
        return session
    }

    private func prepare() {
        var boulder = scales.first { $0.kind == .boulderVScale }
        if boulder == nil {
            let seeded = CustomGradeScale(template: .standardVScale(), isDefault: true)
            context.insert(seeded)
            boulder = seeded
        }
        var yds = scales.first { $0.kind == .yds }
        if yds == nil {
            let seeded = CustomGradeScale(template: .standardYDS())
            context.insert(seeded)
            yds = seeded
        }
        try? context.save()
        if selectedGrade == nil {
            selectedGrade = (discipline.usesRopeGrades ? yds : boulder)?.grades.first
        }
    }
}

#Preview {
    RouteLogView()
        .modelContainer(for: [ClimbingSession.self, ClimbLog.self, CustomGradeScale.self, ClimbGym.self, GymArea.self, GymRoute.self], inMemory: true)
}

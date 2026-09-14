import SwiftUI

/// A reference sheet that explains the logging terms so climbers never have to
/// guess what flash / send / project / attempt mean, and what styles and angles
/// refer to.
struct DefinitionsView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section("Outcomes") {
                    ForEach(ClimbOutcome.allCases) { outcome in
                        HStack(alignment: .top, spacing: 12) {
                            Image(systemName: outcome.symbolName)
                                .foregroundStyle(.stravaOrange)
                                .frame(width: 24)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(outcome.displayName).font(.headline)
                                Text(outcome.explanation)
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .padding(.vertical, 2)
                    }
                }

                Section("Logging tip") {
                    Label(
                        "Just tally your goes and tap Send — a first-try Send is logged as a Flash automatically.",
                        systemImage: "lightbulb.fill"
                    )
                    .font(.subheadline)
                }

                Section("Styles (holds & moves)") {
                    Text(ClimbStyle.allCases.map(\.displayName).joined(separator: ", "))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Section("Angles (wall terrain)") {
                    Text(ClimbAngle.allCases.map(\.displayName).joined(separator: ", "))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("How logging works")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

#Preview {
    DefinitionsView()
}

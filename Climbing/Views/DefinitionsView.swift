import SwiftUI

/// Plain-language logging terms. Style and angle are optional tags, not required.
struct DefinitionsView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section("What to log") {
                    ForEach([ClimbOutcome.flash, .send, .attempt]) { outcome in
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

                Section("On your Watch") {
                    Text("Turn the Digital Crown to pick the grade, then tap First try, Topped it, or Didn't send. That's the whole log — nothing else is required on the wall.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Section("Holds and wall (optional)") {
                    Text("A boulder can be crimpy and overhanging at the same time — those are two different things. Tag them on the phone after a go if you want send-rate by hold type or wall angle. Skip it if you don't care.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    LabeledContent("Holds") {
                        Text(ClimbStyle.allCases.map(\.displayName).joined(separator: ", "))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.trailing)
                    }
                    LabeledContent("Wall") {
                        Text(ClimbAngle.allCases.map(\.displayName).joined(separator: ", "))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.trailing)
                    }
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

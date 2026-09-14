import SwiftUI

/// Lifetime progress mirrored from iPhone.
struct WatchProgressView: View {
    @State private var store = WatchStore.shared

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("LEVEL \(store.snapshot.levelNumber)")
                        .font(.caption2.bold())
                        .foregroundStyle(.secondary)
                    Text(store.snapshot.levelTitle)
                        .font(.headline)
                    Text("\(store.snapshot.lifetimePoints) pts")
                        .font(.title3.bold())
                        .foregroundStyle(.stravaOrange)
                        .monospacedDigit()
                }

                if let headline = store.snapshot.styleHeadline {
                    Text(headline)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                    stat("\(store.snapshot.lifetimeClimbs)", "Climbs")
                    stat("\(store.snapshot.lifetimeSends)", "Sends")
                    stat("\(store.snapshot.lifetimeFlashes)", "Flashes")
                    stat(store.snapshot.hardestSend ?? "—", "Hardest")
                }
            }
            .padding(.top, 4)
        }
        .navigationTitle("Progress")
    }

    private func stat(_ value: String, _ label: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value).font(.headline.bold()).monospacedDigit()
            Text(label.uppercased()).font(.caption2).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

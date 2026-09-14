import SwiftUI

/// Shows Apple Watch metrics (active calories + heart rate) for the session,
/// with a connect prompt until Health access is granted.
struct HealthCard: View {
    let summary: HealthSummary
    let status: HealthManager.Status
    var liveBPM: Int? = nil
    let onConnect: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("Apple Watch", systemImage: "applewatch")
                    .font(.headline)
                Spacer()
                if status != .authorized && status != .unavailable {
                    Button("Connect", action: onConnect)
                        .font(.subheadline.bold())
                }
            }

            switch status {
            case .authorized where liveBPM != nil || summary.hasData:
                HStack(spacing: 20) {
                    if let liveBPM {
                        metric("\(liveBPM)", unit: "bpm", label: "Now",
                               systemImage: "heart.fill", color: .red)
                    }
                    metric(summary.caloriesText, unit: "kcal", label: "Active",
                           systemImage: "flame.fill", color: .stravaOrange)
                    if let avg = summary.averageHeartRate {
                        metric("\(avg)", unit: "bpm", label: "Avg HR",
                               systemImage: "heart.fill", color: .red)
                    }
                }
            case .authorized:
                hint("Start a session with your Apple Watch to capture calories, heart rate, and a send trace after you send or flash.")
            case .unavailable:
                hint("Health data isn't available on this device.")
            default:
                hint("Connect Apple Health to track calories and heart rate during your session.")
            }
        }
        .padding()
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 20))
    }

    private func metric(
        _ value: String, unit: String, label: String, systemImage: String, color: Color
    ) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Image(systemName: systemImage).foregroundStyle(color)
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(value).font(.title3.bold()).monospacedDigit()
                Text(unit).font(.caption2).foregroundStyle(.secondary)
            }
            Text(label.uppercased()).font(.caption2.bold()).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func hint(_ text: String) -> some View {
        Text(text).font(.caption).foregroundStyle(.secondary)
    }
}

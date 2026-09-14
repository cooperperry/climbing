import SwiftUI

/// A Strava-style recap shown when a session ends: points earned, headline
/// stats, any personal records, and Apple Watch effort.
struct SessionSummaryView: View {
    let session: ClimbingSession
    let records: [PersonalRecord]
    let health: HealthSummary

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    header
                    if !records.isEmpty { recordsCard }
                    statsGrid
                    if health.hasData { healthCard }
                }
                .padding()
            }
            .navigationTitle("Session Complete")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private var header: some View {
        VStack(spacing: 6) {
            Text(session.startTime, format: .dateTime.weekday(.wide).month().day())
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Text("\(session.score)")
                .font(.system(size: 60, weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(.stravaOrange)
            Text("POINTS EARNED")
                .font(.caption.bold())
                .foregroundStyle(.secondary)
            Text(SessionClock.format(session.duration()))
                .font(.headline)
                .monospacedDigit()
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
    }

    private var recordsCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("New Personal Records", systemImage: "rosette")
                .font(.headline)
            ForEach(records) { record in
                HStack(spacing: 12) {
                    Image(systemName: record.symbolName)
                        .foregroundStyle(.stravaOrange)
                        .frame(width: 24)
                    Text(record.title)
                    Spacer()
                    Text(record.detail)
                        .font(.subheadline.bold())
                        .monospacedDigit()
                }
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.stravaOrange.opacity(0.12), in: RoundedRectangle(cornerRadius: 20))
    }

    private var statsGrid: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
            stat("\(session.logs.count)", "Climbs", "figure.climbing")
            stat("\(session.completionCount)", "Sends", "checkmark.circle.fill")
            stat("\(session.flashCount)", "Flashes", "bolt.fill")
            stat(session.hardestSend?.gradeLabel ?? "—", "Hardest Send", "trophy.fill")
        }
    }

    private var healthCard: some View {
        HStack(spacing: 20) {
            stat(health.caloriesText, "kcal Active", "flame.fill")
            if let avg = health.averageHeartRate {
                stat("\(avg)", "Avg HR", "heart.fill")
            }
            if let peak = health.maxHeartRate {
                stat("\(peak)", "Max HR", "bolt.heart.fill")
            }
        }
    }

    private func stat(_ value: String, _ label: String, _ systemImage: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Image(systemName: systemImage).foregroundStyle(.stravaOrange)
            Text(value).font(.title2.bold()).monospacedDigit()
            Text(label.uppercased()).font(.caption2.bold()).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 16))
    }
}

import SwiftUI

/// Heart-rate-over-time strip for a send/flash. BPM is the series — not wrist motion.
struct EffortStripView: View {
    let trace: EffortTrace
    var title: String = "Heart rate"

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label(title, systemImage: "heart.fill")
                    .font(.headline)
                    .foregroundStyle(.red)
                Spacer()
                if let peak = trace.peakHeartRate {
                    Text("Peak \(peak)")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
            }

            chart
                .frame(height: 72)
                .padding(.vertical, 4)

            HStack {
                Label("BPM as you climbed", systemImage: "applewatch")
                Spacer()
                if let hr = trace.averageHeartRate {
                    Text("\(hr) avg")
                        .monospacedDigit()
                }
                if trace.duration > 0 {
                    Text(SessionClock.format(trace.duration))
                        .monospacedDigit()
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)

            if !trace.hasHeartRate {
                Text("Wear your Apple Watch and connect Health, then send or flash to record heart rate through the go.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 20))
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityText)
    }

    @ViewBuilder
    private var chart: some View {
        let pairs = trace.points.compactMap { point -> (TimeInterval, Double)? in
            guard let hr = point.heartRate else { return nil }
            return (point.t, Double(hr))
        }
        if pairs.count >= 2 {
            Canvas { context, size in
                let hrPath = path(in: size, pairs: pairs)
                var filled = hrPath
                filled.addLine(to: CGPoint(x: size.width, y: size.height))
                filled.addLine(to: CGPoint(x: 0, y: size.height))
                filled.closeSubpath()
                context.fill(filled, with: .color(Color.red.opacity(0.28)))
                context.stroke(hrPath, with: .color(.red), lineWidth: 2)
            }
        } else {
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.red.opacity(0.15))
        }
    }

    private func path(in size: CGSize, pairs: [(TimeInterval, Double)]) -> Path {
        guard pairs.count >= 2 else { return Path() }
        let lo = min(80, pairs.map(\.1).min() ?? 80)
        let hi = max(lo + 20, pairs.map(\.1).max() ?? 160)
        let span = max(trace.duration, pairs.last?.0 ?? 1, 0.001)
        var path = Path()
        for (index, pair) in pairs.enumerated() {
            let x = CGFloat(pair.0 / span) * size.width
            let y = size.height - CGFloat((pair.1 - lo) / (hi - lo)) * size.height
            if index == 0 {
                path.move(to: CGPoint(x: x, y: y))
            } else {
                path.addLine(to: CGPoint(x: x, y: y))
            }
        }
        return path
    }

    private var accessibilityText: String {
        var parts = ["Heart rate"]
        if let hr = trace.averageHeartRate { parts.append("\(hr) average") }
        if let peak = trace.peakHeartRate { parts.append("\(peak) peak") }
        return parts.joined(separator: ", ")
    }
}

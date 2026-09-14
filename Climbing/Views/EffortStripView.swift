import SwiftUI

/// Sparkline for a send/flash: wrist-motion bursts (orange fill) with heart
/// rate overlaid (red). This is an effort strip, not a drawing of the route.
struct EffortStripView: View {
    let trace: EffortTrace
    var title: String = "Send trace"

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label(title, systemImage: "waveform.path.ecg")
                    .font(.headline)
                Spacer()
                Text(trace.character.displayName)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            chart
                .frame(height: 72)
                .padding(.vertical, 4)

            HStack {
                if trace.hasMotion {
                    Label("Wrist motion", systemImage: "applewatch")
                } else if trace.hasHeartRate {
                    Label("Heart rate", systemImage: "heart.fill")
                } else {
                    Label("No Watch data yet", systemImage: "applewatch")
                }
                Spacer()
                if let hr = trace.averageHeartRate {
                    Text("\(hr) bpm")
                        .monospacedDigit()
                }
                if trace.duration > 0 {
                    Text(SessionClock.format(trace.duration))
                        .monospacedDigit()
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)

            if !trace.hasData {
                Text("Wear your Apple Watch and connect Health, then send or flash. You'll get wrist-motion bursts with heart rate — not a drawing of the route.")
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
        if trace.points.count >= 2 {
            Canvas { context, size in
                let intensityPath = path(
                    in: size,
                    values: trace.points.map(\.intensity),
                    times: trace.points.map(\.t),
                    duration: max(trace.duration, trace.points.last?.t ?? 1)
                )
                var filled = intensityPath
                filled.addLine(to: CGPoint(x: size.width, y: size.height))
                filled.addLine(to: CGPoint(x: 0, y: size.height))
                filled.closeSubpath()
                context.fill(filled, with: .color(Color.stravaOrange.opacity(0.35)))
                context.stroke(intensityPath, with: .color(.stravaOrange), lineWidth: 2)

                if trace.hasHeartRate {
                    let rates = trace.points.map { Double($0.heartRate ?? 0) }
                    // Skip zeros from missing samples so the line doesn't dive to the axis.
                    let hrPath = path(
                        in: size,
                        values: rates,
                        times: trace.points.map(\.t),
                        duration: max(trace.duration, trace.points.last?.t ?? 1),
                        ignoreZero: true
                    )
                    context.stroke(hrPath, with: .color(.red), lineWidth: 2)
                }
            }
        } else {
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.stravaOrange.opacity(0.2))
        }
    }

    private func path(
        in size: CGSize,
        values: [Double],
        times: [TimeInterval],
        duration: TimeInterval,
        ignoreZero: Bool = false
    ) -> Path {
        let usable = zip(times, values).filter { !ignoreZero || $0.1 > 0 }
        guard usable.count >= 2 else { return Path() }
        let peak = max(usable.map(\.1).max() ?? 1, 0.0001)
        let span = max(duration, 0.001)
        var path = Path()
        for (index, pair) in usable.enumerated() {
            let x = CGFloat(pair.0 / span) * size.width
            let y = size.height - CGFloat(pair.1 / peak) * size.height
            if index == 0 {
                path.move(to: CGPoint(x: x, y: y))
            } else {
                path.addLine(to: CGPoint(x: x, y: y))
            }
        }
        return path
    }

    private var accessibilityText: String {
        var parts = [trace.character.displayName, SessionClock.format(trace.duration)]
        if let hr = trace.averageHeartRate {
            parts.append("\(hr) beats per minute")
        }
        return parts.joined(separator: ", ")
    }
}

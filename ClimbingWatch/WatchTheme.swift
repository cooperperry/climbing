import SwiftUI

extension ShapeStyle where Self == Color {
    static var stravaOrange: Color {
        Color(red: 0.988, green: 0.298, blue: 0.008)
    }
}

/// Compact BPM sparkline from heart-rate samples.
struct BPMSparkline: View {
    var samples: [HeartRateSample]
    var lineColor: Color = .red

    var body: some View {
        Canvas { context, size in
            let values = samples.map(\.bpm)
            guard values.count >= 2 else { return }
            let lo = min(70, values.min() ?? 70)
            let hi = max(lo + 20, values.max() ?? 160)
            let span = max(samples.last!.timestamp - samples.first!.timestamp, 0.001)
            var path = Path()
            for (index, sample) in samples.enumerated() {
                let x = CGFloat((sample.timestamp - samples[0].timestamp) / span) * size.width
                let y = size.height - CGFloat((sample.bpm - lo) / (hi - lo)) * size.height
                if index == 0 {
                    path.move(to: CGPoint(x: x, y: y))
                } else {
                    path.addLine(to: CGPoint(x: x, y: y))
                }
            }
            var filled = path
            filled.addLine(to: CGPoint(x: size.width, y: size.height))
            filled.addLine(to: CGPoint(x: 0, y: size.height))
            filled.closeSubpath()
            context.fill(filled, with: .color(lineColor.opacity(0.28)))
            context.stroke(path, with: .color(lineColor), lineWidth: 2)
        }
        .accessibilityHidden(true)
    }
}

struct WatchHeartRateChart: View {
    let trace: EffortTrace

    var body: some View {
        let pairs = trace.points.compactMap { point -> (TimeInterval, Double)? in
            guard let hr = point.heartRate else { return nil }
            return (point.t, Double(hr))
        }
        Canvas { context, size in
            guard pairs.count >= 2 else { return }
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
            var filled = path
            filled.addLine(to: CGPoint(x: size.width, y: size.height))
            filled.addLine(to: CGPoint(x: 0, y: size.height))
            filled.closeSubpath()
            context.fill(filled, with: .color(Color.red.opacity(0.3)))
            context.stroke(path, with: .color(.red), lineWidth: 2)
        }
    }
}

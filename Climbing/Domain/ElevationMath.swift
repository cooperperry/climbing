import Foundation

/// Relative-altitude smoothing: ignore sub-threshold jitter, accumulate only
/// upward movement for vertical gain.
public struct ElevationFilter: Equatable, Sendable {
    public static let noiseMeters = 0.3

    public private(set) var lastAltitude: Double?
    public private(set) var gainMeters: Double
    public private(set) var maxAltitude: Double

    public init(lastAltitude: Double? = nil, gainMeters: Double = 0, maxAltitude: Double = 0) {
        self.lastAltitude = lastAltitude
        self.gainMeters = max(0, gainMeters)
        self.maxAltitude = maxAltitude
    }

    /// Apply a new relative-altitude reading (meters). Returns the accepted
    /// altitude when the sample cleared the noise floor; otherwise `nil`.
    @discardableResult
    public mutating func ingest(_ relativeMeters: Double) -> Double? {
        guard let last = lastAltitude else {
            lastAltitude = relativeMeters
            maxAltitude = relativeMeters
            return relativeMeters
        }
        let delta = relativeMeters - last
        guard abs(delta) >= Self.noiseMeters else { return nil }
        lastAltitude = relativeMeters
        if delta > 0 {
            gainMeters += delta
        }
        maxAltitude = max(maxAltitude, relativeMeters)
        return relativeMeters
    }
}

/// Rolling vertical speed from a gain time series.
public enum VerticalSpeed {
    /// Meters of gain per minute over `window` (default 60s).
    public static func metersPerMinute(
        samples: [(t: TimeInterval, gain: Double)],
        now: TimeInterval,
        window: TimeInterval = 60
    ) -> Double {
        guard window > 0 else { return 0 }
        let cutoff = now - window
        let inWindow = samples.filter { $0.t >= cutoff && $0.t <= now }
        guard let first = inWindow.first, let last = inWindow.last, last.t > first.t else {
            return 0
        }
        let elapsedMinutes = (last.t - first.t) / 60
        guard elapsedMinutes > 0 else { return 0 }
        return max(0, (last.gain - first.gain) / elapsedMinutes)
    }
}

public enum ElevationFormat {
    /// Session-style readout, e.g. `+1,240 FT`.
    public static func gain(meters: Double, useFeet: Bool = true) -> String {
        let value = useFeet ? meters / 0.3048 : meters
        let n = Int(value.rounded())
        let formatted = Self.grouped.string(from: NSNumber(value: n)) ?? "\(n)"
        return "+\(formatted) \(useFeet ? "FT" : "M")"
    }

    /// Rolling vertical speed, e.g. `10 FT/M`.
    public static func speed(metersPerMinute: Double, useFeet: Bool = true) -> String {
        let value = useFeet ? metersPerMinute / 0.3048 : metersPerMinute
        let n = Int(value.rounded())
        return "\(n) \(useFeet ? "FT/M" : "M/MIN")"
    }

    private static let grouped: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 0
        return formatter
    }()
}

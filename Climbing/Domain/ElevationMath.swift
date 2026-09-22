import Foundation

/// Relative-altitude smoothing: ignore sub-threshold jitter, accumulate only
/// upward movement for vertical gain.
public struct ElevationFilter: Equatable, Sendable {
    /// Indoor HVAC easily moves 0.3 m of pressure; require a clearer step.
    public static let noiseMeters = 0.5

    public private(set) var lastAltitude: Double?
    public private(set) var gainMeters: Double
    public private(set) var maxAltitude: Double
    /// Start of the current climbing bout. Cleared when you stop moving or HR drops.
    var boutStart: TimeInterval?
    var boutBaseline: Double?
    var boutCommitted: Double

    public init(
        lastAltitude: Double? = nil,
        gainMeters: Double = 0,
        maxAltitude: Double = 0,
        boutStart: TimeInterval? = nil,
        boutBaseline: Double? = nil,
        boutCommitted: Double = 0
    ) {
        self.lastAltitude = lastAltitude
        self.gainMeters = max(0, gainMeters)
        self.maxAltitude = maxAltitude
        self.boutStart = boutStart
        self.boutBaseline = boutBaseline
        self.boutCommitted = boutCommitted
    }

    /// Apply a new relative-altitude reading (meters).
    ///
    /// When `countingGain` is false (wrist still / resting), the filter follows
    /// pressure drift so a later real climb does not dump the idle change in as
    /// ascent. Gain only accumulates while moving.
    @discardableResult
    public mutating func ingest(_ relativeMeters: Double, countingGain: Bool = true) -> Double? {
        guard let last = lastAltitude else {
            lastAltitude = relativeMeters
            maxAltitude = relativeMeters
            return relativeMeters
        }
        if !countingGain {
            lastAltitude = relativeMeters
            return nil
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

/// Barometer gain counts only during a real climbing bout: heart rate in
/// zone 2 or higher, and wrist motion well above a fidget.
public enum ClimbGainGate {
    /// Sitting and chalking land near 0.08. Pulling on holds is louder.
    public static let motionThreshold = 0.20
    /// 60% of max HR is the bottom of zone 2. Below that, ignore the barometer.
    public static let minimumMaxHRFraction = 0.60

    public static func shouldCount(motionVariance: Double, bpm: Int?, maxHR: Int) -> Bool {
        guard motionVariance >= motionThreshold else { return false }
        guard let bpm, bpm > 0, maxHR > 0 else { return false }
        return Double(bpm) / Double(maxHR) >= minimumMaxHRFraction
    }
}

extension ElevationFilter {
    /// Ignore rises shorter than this, or that fall back before the bout is real.
    public static let minimumClimbMeters = 1.0
    public static let confirmSeconds: TimeInterval = 5

    /// Follow pressure while resting. Commit height only after `confirmSeconds`
    /// of continuous climbing with at least `minimumClimbMeters` of rise.
    /// A blip that ends early is dropped, so the total runs short instead of high.
    public mutating func ingestClimb(_ relativeMeters: Double, countingGain: Bool, now: TimeInterval) {
        guard countingGain else {
            resetBout()
            lastAltitude = relativeMeters
            return
        }
        if boutStart == nil || boutBaseline == nil {
            boutStart = now
            boutBaseline = relativeMeters
            boutCommitted = 0
            lastAltitude = relativeMeters
            return
        }
        let baseline = boutBaseline ?? relativeMeters
        let rise = relativeMeters - baseline
        let held = now - (boutStart ?? now)
        if held >= Self.confirmSeconds, rise >= Self.minimumClimbMeters {
            let add = rise - boutCommitted
            if add > 0.05 {
                gainMeters += add
                boutCommitted = rise
                maxAltitude = max(maxAltitude, relativeMeters)
            }
        }
        lastAltitude = relativeMeters
    }

    private mutating func resetBout() {
        boutStart = nil
        boutBaseline = nil
        boutCommitted = 0
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

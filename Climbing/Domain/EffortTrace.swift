import Foundation

/// Wrist-motion sample from Apple Watch. Accelerations are in g; `timestamp`
/// is seconds since 1970. Foundation-only so Watch and iPhone share the same
/// encoding without importing HealthKit or Core Motion.
public struct MotionFrame: Equatable, Sendable, Codable {
    public var timestamp: TimeInterval
    public var userX: Double
    public var userY: Double
    public var userZ: Double
    public var gravityX: Double
    public var gravityY: Double
    public var gravityZ: Double

    public init(
        timestamp: TimeInterval,
        userX: Double, userY: Double, userZ: Double,
        gravityX: Double, gravityY: Double, gravityZ: Double
    ) {
        self.timestamp = timestamp
        self.userX = userX
        self.userY = userY
        self.userZ = userZ
        self.gravityX = gravityX
        self.gravityY = gravityY
        self.gravityZ = gravityZ
    }
}

/// A heart-rate reading aligned onto a send-trace window.
public struct HeartRateSample: Equatable, Sendable, Codable {
    public var timestamp: TimeInterval
    public var bpm: Double

    public init(timestamp: TimeInterval, bpm: Double) {
        self.timestamp = timestamp
        self.bpm = bpm
    }
}

/// One column of a send trace: wrist intensity, how vertical that burst was,
/// and the nearest heart rate.
public struct EffortPoint: Equatable, Sendable, Codable {
    /// Seconds from the start of the window.
    public var t: TimeInterval
    /// Magnitude of user acceleration, in g.
    public var intensity: Double
    /// 0 = acceleration perpendicular to gravity (traverse), 1 = along gravity
    /// (vertical). Resting samples sit at 0.5.
    public var verticalness: Double
    public var heartRate: Int?

    public init(t: TimeInterval, intensity: Double, verticalness: Double, heartRate: Int?) {
        self.t = t
        self.intensity = intensity
        self.verticalness = verticalness
        self.heartRate = heartRate
    }
}

/// Dominant character of wrist motion during an attempt. Honest about what a
/// Watch can know: not a hold-by-hold beta, just vertical vs traverse emphasis.
public enum EffortCharacter: String, Equatable, Sendable, Codable {
    case vertical
    case traverse
    case mixed
    case unknown

    public var displayName: String {
        switch self {
        case .vertical: return "More vertical"
        case .traverse: return "More traverse"
        case .mixed: return "Mixed"
        case .unknown: return "Effort"
        }
    }
}

/// A send/flash recap strip: motion bursts, optional HR overlay, duration.
public struct EffortTrace: Equatable, Sendable, Codable {
    public var duration: TimeInterval
    public var points: [EffortPoint]
    public var character: EffortCharacter
    public var peakIntensity: Double
    public var averageHeartRate: Int?

    public init(
        duration: TimeInterval = 0,
        points: [EffortPoint] = [],
        character: EffortCharacter = .unknown,
        peakIntensity: Double = 0,
        averageHeartRate: Int? = nil
    ) {
        self.duration = duration
        self.points = points
        self.character = character
        self.peakIntensity = peakIntensity
        self.averageHeartRate = averageHeartRate
    }

    /// User-acceleration magnitude treated as "moving" rather than noise.
    public static let motionFloor: Double = 0.08

    public var hasMotion: Bool {
        points.contains { $0.intensity >= Self.motionFloor }
    }

    public var hasHeartRate: Bool {
        points.contains { $0.heartRate != nil }
    }

    public var hasData: Bool {
        !points.isEmpty && (hasMotion || hasHeartRate)
    }
}

/// The attempt window captured when a send or flash is logged: from the later
/// of session start, the previous log, or 45 seconds back, up to `loggedAt`.
public enum EffortWindow {
    public static let maximum: TimeInterval = 45

    public static func bounds(
        loggedAt: Date,
        sessionStart: Date,
        previousLogAt: Date?
    ) -> (start: Date, end: Date) {
        let floor = loggedAt.addingTimeInterval(-maximum)
        var start = max(sessionStart, floor)
        if let previousLogAt {
            start = max(start, previousLogAt)
        }
        if start > loggedAt { start = loggedAt }
        return (start, loggedAt)
    }
}

/// Keys for WatchConnectivity messages. Shared so the Watch and iPhone stay
/// in lockstep without importing WatchConnectivity in Domain.
public enum WatchSync {
    public static let kind = "kind"
    public static let start = "start"
    public static let stop = "stop"
    public static let frames = "frames"
    public static let from = "from"
    public static let to = "to"
}

/// Pure helpers for turning raw Watch IMU + HR samples into an `EffortTrace`.
public enum EffortMath {
    public static func intensity(userX: Double, userY: Double, userZ: Double) -> Double {
        (userX * userX + userY * userY + userZ * userZ).squareRoot()
    }

    /// Fraction of user acceleration along gravity. Parallel → 1 (vertical
    /// burst), perpendicular → 0 (traverse). Near-zero motion returns 0.5.
    public static func verticalness(
        userX: Double, userY: Double, userZ: Double,
        gravityX: Double, gravityY: Double, gravityZ: Double
    ) -> Double {
        let mag = intensity(userX: userX, userY: userY, userZ: userZ)
        let gMag = intensity(userX: gravityX, userY: gravityY, userZ: gravityZ)
        guard mag > 0.001, gMag > 0.001 else { return 0.5 }
        let along = abs(userX * gravityX + userY * gravityY + userZ * gravityZ) / gMag
        return min(1, along / mag)
    }

    public static func character(_ verticalness: [Double]) -> EffortCharacter {
        guard !verticalness.isEmpty else { return .unknown }
        let mean = verticalness.reduce(0, +) / Double(verticalness.count)
        if mean >= 0.6 { return .vertical }
        if mean <= 0.4 { return .traverse }
        return .mixed
    }

    /// Keeps the first sample in each `interval` bucket so a 45s window stays
    /// small enough to send over WatchConnectivity.
    public static func downsample(_ frames: [MotionFrame], interval: TimeInterval = 0.2) -> [MotionFrame] {
        guard interval > 0 else { return frames }
        let sorted = frames.sorted { $0.timestamp < $1.timestamp }
        guard let first = sorted.first else { return frames }
        var result: [MotionFrame] = []
        var next = first.timestamp
        for frame in sorted {
            if frame.timestamp + 0.0001 >= next {
                result.append(frame)
                next = frame.timestamp + interval
            }
        }
        return result
    }

    public static func nearestHeartRate(
        _ samples: [HeartRateSample],
        at timestamp: TimeInterval,
        maxGap: TimeInterval = 8
    ) -> Int? {
        var best: HeartRateSample?
        var bestDist = TimeInterval.greatestFiniteMagnitude
        for sample in samples {
            let dist = abs(sample.timestamp - timestamp)
            if dist < bestDist {
                bestDist = dist
                best = sample
            }
        }
        guard let best, bestDist <= maxGap else { return nil }
        return Int(best.bpm.rounded())
    }

    public static func trace(
        motion: [MotionFrame],
        heartRates: [HeartRateSample],
        start: Date,
        end: Date
    ) -> EffortTrace {
        let duration = max(0, end.timeIntervalSince(start))
        let startTs = start.timeIntervalSince1970
        let endTs = end.timeIntervalSince1970
        let hr = heartRates
            .filter { $0.timestamp >= startTs - 8 && $0.timestamp <= endTs + 8 }
            .sorted { $0.timestamp < $1.timestamp }

        let sampled = downsample(
            motion.filter { $0.timestamp >= startTs && $0.timestamp <= endTs }
        )

        let points: [EffortPoint]
        if sampled.isEmpty {
            points = hr.filter { $0.timestamp >= startTs && $0.timestamp <= endTs }.map { sample in
                EffortPoint(
                    t: max(0, sample.timestamp - startTs),
                    intensity: 0,
                    verticalness: 0.5,
                    heartRate: Int(sample.bpm.rounded())
                )
            }
        } else {
            points = sampled.map { frame in
                EffortPoint(
                    t: max(0, frame.timestamp - startTs),
                    intensity: intensity(userX: frame.userX, userY: frame.userY, userZ: frame.userZ),
                    verticalness: verticalness(
                        userX: frame.userX, userY: frame.userY, userZ: frame.userZ,
                        gravityX: frame.gravityX, gravityY: frame.gravityY, gravityZ: frame.gravityZ
                    ),
                    heartRate: nearestHeartRate(hr, at: frame.timestamp)
                )
            }
        }

        let moving = points.filter { $0.intensity >= EffortTrace.motionFloor }.map(\.verticalness)
        let rates = points.compactMap(\.heartRate)
        let peak = points.map(\.intensity).max() ?? 0
        let avgHR = rates.isEmpty
            ? nil
            : Int((Double(rates.reduce(0, +)) / Double(rates.count)).rounded())

        return EffortTrace(
            duration: duration,
            points: points,
            character: character(moving),
            peakIntensity: peak,
            averageHeartRate: avgHR
        )
    }
}

import Foundation

/// One logged climb, stripped to what style send-rate math needs.
public struct StyleLog: Equatable, Sendable {
    public var style: ClimbStyle
    public var outcome: ClimbOutcome
    public var loggedAt: Date

    public init(style: ClimbStyle, outcome: ClimbOutcome, loggedAt: Date) {
        self.style = style
        self.outcome = outcome
        self.loggedAt = loggedAt
    }
}

/// Send rate for one movement style over a time window.
public struct StyleSpot: Equatable, Sendable, Identifiable {
    public var style: ClimbStyle
    public var goes: Int
    public var sends: Int
    public var sendRate: Double

    public init(style: ClimbStyle, goes: Int, sends: Int, sendRate: Double) {
        self.style = style
        self.goes = goes
        self.sends = sends
        self.sendRate = sendRate
    }

    public var id: String { style.rawValue }

    /// Rounded percent, e.g. `40%`.
    public var percentText: String {
        "\(Int((sendRate * 100).rounded()))%"
    }
}

/// Weakest / strongest styles over a recent window, plus a glance headline.
public struct StyleInsight: Equatable, Sendable {
    public var windowDays: Int
    public var spots: [StyleSpot]
    public var weakest: StyleSpot?
    public var strongest: StyleSpot?
    public var headline: String?

    public init(
        windowDays: Int,
        spots: [StyleSpot],
        weakest: StyleSpot?,
        strongest: StyleSpot?,
        headline: String?
    ) {
        self.windowDays = windowDays
        self.spots = spots
        self.weakest = weakest
        self.strongest = strongest
        self.headline = headline
    }

    public var hasEnoughData: Bool { !spots.isEmpty }
}

/// Send-rate by style. Surfaces a weak spot only when a style has enough goes.
public enum StyleWeakSpotMath {
    public static let defaultWindowDays = 14
    public static let minimumGoes = 3
    /// Headline uses "X vs Y" when the gap is at least this large.
    public static let contrastGap = 0.15

    public static func insight(
        logs: [StyleLog],
        now: Date,
        windowDays: Int = defaultWindowDays,
        minimumGoes: Int = minimumGoes
    ) -> StyleInsight {
        let cutoff = now.addingTimeInterval(-Double(windowDays) * 24 * 60 * 60)
        let recent = logs.filter { $0.loggedAt >= cutoff }

        var tallies: [ClimbStyle: (goes: Int, sends: Int)] = [:]
        for log in recent {
            let current = tallies[log.style] ?? (0, 0)
            let send = log.outcome.isCompletion ? 1 : 0
            tallies[log.style] = (current.goes + 1, current.sends + send)
        }

        let spots: [StyleSpot] = tallies.compactMap { style, tally in
            guard tally.goes >= minimumGoes else { return nil }
            return StyleSpot(
                style: style,
                goes: tally.goes,
                sends: tally.sends,
                sendRate: Double(tally.sends) / Double(tally.goes)
            )
        }
        .sorted { lhs, rhs in
            if lhs.sendRate != rhs.sendRate { return lhs.sendRate < rhs.sendRate }
            if lhs.goes != rhs.goes { return lhs.goes > rhs.goes }
            return lhs.style.rawValue < rhs.style.rawValue
        }

        let weakest = spots.first
        let strongest = spots.max { lhs, rhs in
            if lhs.sendRate != rhs.sendRate { return lhs.sendRate < rhs.sendRate }
            return lhs.goes < rhs.goes
        }

        return StyleInsight(
            windowDays: windowDays,
            spots: spots,
            weakest: weakest,
            strongest: strongest,
            headline: headline(weakest: weakest, strongest: strongest)
        )
    }

    private static func headline(weakest: StyleSpot?, strongest: StyleSpot?) -> String? {
        guard let weakest else { return nil }
        if let strongest, strongest.style != weakest.style {
            let gap = strongest.sendRate - weakest.sendRate
            if gap >= contrastGap {
                return "\(weakest.style.displayName) \(weakest.percentText) vs \(strongest.style.displayName) \(strongest.percentText)"
            }
        }
        return "\(weakest.style.displayName) \(weakest.percentText) send rate"
    }
}

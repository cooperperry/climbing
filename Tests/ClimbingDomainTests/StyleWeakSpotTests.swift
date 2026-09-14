import XCTest
@testable import ClimbingDomain

final class StyleWeakSpotTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_700_000_000)

    func testEmptyLogsHaveNoInsight() {
        let insight = StyleWeakSpotMath.insight(logs: [], now: now)
        XCTAssertFalse(insight.hasEnoughData)
        XCTAssertNil(insight.headline)
        XCTAssertNil(insight.weakest)
    }

    func testIgnoresStylesBelowMinimumGoes() {
        let logs = [
            StyleLog(style: .sloper, outcome: .attempt, loggedAt: now),
            StyleLog(style: .sloper, outcome: .send, loggedAt: now),
            StyleLog(style: .crimp, outcome: .flash, loggedAt: now),
            StyleLog(style: .crimp, outcome: .flash, loggedAt: now),
            StyleLog(style: .crimp, outcome: .flash, loggedAt: now),
        ]
        let insight = StyleWeakSpotMath.insight(logs: logs, now: now)
        XCTAssertEqual(insight.spots.map(\.style), [.crimp])
        XCTAssertEqual(insight.weakest?.style, .crimp)
        XCTAssertEqual(insight.weakest?.percentText, "100%")
    }

    func testFiltersLogsOutsideWindow() {
        let old = now.addingTimeInterval(-15 * 24 * 60 * 60)
        var logs: [StyleLog] = (0..<5).map { _ in
            StyleLog(style: .sloper, outcome: .attempt, loggedAt: old)
        }
        logs.append(contentsOf: (0..<3).map { _ in
            StyleLog(style: .crimp, outcome: .flash, loggedAt: now)
        })
        let insight = StyleWeakSpotMath.insight(logs: logs, now: now)
        XCTAssertEqual(insight.spots.map(\.style), [.crimp])
    }

    func testSendRateCountsFlashAndSendOnly() {
        let logs: [StyleLog] = [
            .init(style: .sloper, outcome: .send, loggedAt: now),
            .init(style: .sloper, outcome: .flash, loggedAt: now),
            .init(style: .sloper, outcome: .attempt, loggedAt: now),
            .init(style: .sloper, outcome: .project, loggedAt: now),
            .init(style: .sloper, outcome: .attempt, loggedAt: now),
        ]
        let insight = StyleWeakSpotMath.insight(logs: logs, now: now)
        XCTAssertEqual(insight.weakest?.goes, 5)
        XCTAssertEqual(insight.weakest?.sends, 2)
        XCTAssertEqual(insight.weakest?.sendRate ?? 0, 0.4, accuracy: 0.0001)
        XCTAssertEqual(insight.weakest?.percentText, "40%")
    }

    func testHeadlineContrastsWeakestAgainstStrongest() {
        var logs: [StyleLog] = (0..<5).map { _ in
            StyleLog(style: .sloper, outcome: .attempt, loggedAt: now)
        }
        logs.append(StyleLog(style: .sloper, outcome: .send, loggedAt: now))
        logs.append(contentsOf: (0..<4).map { _ in
            StyleLog(style: .crimp, outcome: .flash, loggedAt: now)
        })
        logs.append(StyleLog(style: .crimp, outcome: .attempt, loggedAt: now))

        let insight = StyleWeakSpotMath.insight(logs: logs, now: now)
        XCTAssertEqual(insight.weakest?.style, .sloper)
        XCTAssertEqual(insight.strongest?.style, .crimp)
        XCTAssertEqual(insight.headline, "Slopey 17% vs Crimpy 80%")
        XCTAssertEqual(insight.spots.first?.style, .sloper)
    }

    func testHeadlineWithoutContrastUsesWeakestRate() {
        let logs: [StyleLog] = (0..<3).map { _ in
            StyleLog(style: .pinch, outcome: .send, loggedAt: now)
        }
        let insight = StyleWeakSpotMath.insight(logs: logs, now: now)
        XCTAssertEqual(insight.headline, "Pinchy 100% send rate")
    }

    func testIncludesLogsOnTheCutoffBoundary() {
        let cutoff = now.addingTimeInterval(-14 * 24 * 60 * 60)
        let logs: [StyleLog] = (0..<3).map { _ in
            StyleLog(style: .dyno, outcome: .send, loggedAt: cutoff)
        }
        let insight = StyleWeakSpotMath.insight(logs: logs, now: now)
        XCTAssertEqual(insight.weakest?.style, .dyno)
    }
}

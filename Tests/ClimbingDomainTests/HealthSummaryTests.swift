import XCTest
@testable import ClimbingDomain

final class HealthSummaryTests: XCTestCase {
    func testEmptySummaryHasNoData() {
        XCTAssertFalse(HealthSummary.empty.hasData)
        XCTAssertEqual(HealthSummary.empty.activeCalories, 0)
        XCTAssertNil(HealthSummary.empty.averageHeartRate)
    }

    func testHasDataWhenCaloriesOrHeartRatePresent() {
        XCTAssertTrue(HealthSummary(activeCalories: 120).hasData)
        XCTAssertTrue(HealthSummary(averageHeartRate: 130).hasData)
        XCTAssertFalse(HealthSummary(activeCalories: 0).hasData)
    }

    func testCaloriesTextRoundsToWholeNumber() {
        XCTAssertEqual(HealthSummary(activeCalories: 245.6).caloriesText, "246")
        XCTAssertEqual(HealthSummary(activeCalories: 0).caloriesText, "0")
    }

    func testAverageBPM() {
        XCTAssertEqual(HealthMath.averageBPM([120, 130, 140]), 130)
        XCTAssertEqual(HealthMath.averageBPM([100, 101]), 101)  // 100.5 rounds up
        XCTAssertNil(HealthMath.averageBPM([]))
    }

    func testMaxBPM() {
        XCTAssertEqual(HealthMath.maxBPM([120, 155, 140]), 155)
        XCTAssertNil(HealthMath.maxBPM([]))
    }

    func testSummaryClampsNegativeCaloriesAndAggregatesHeartRate() {
        let summary = HealthMath.summary(activeCalories: -5, heartRates: [110, 150])
        XCTAssertEqual(summary.activeCalories, 0)
        XCTAssertEqual(summary.averageHeartRate, 130)
        XCTAssertEqual(summary.maxHeartRate, 150)
    }

    func testSummaryWithoutHeartRate() {
        let summary = HealthMath.summary(activeCalories: 300, heartRates: [])
        XCTAssertEqual(summary.activeCalories, 300)
        XCTAssertNil(summary.averageHeartRate)
        XCTAssertTrue(summary.hasData)
    }
}

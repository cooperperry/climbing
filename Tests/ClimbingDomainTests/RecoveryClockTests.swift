import XCTest
@testable import ClimbingDomain

final class RecoveryClockTests: XCTestCase {
    private let t0 = Date(timeIntervalSince1970: 1_000)

    func testFallbackDurationWhenNoHeartRate() {
        let plan = RecoveryMath.plan(at: t0, heartRates: [], currentBPM: nil)
        XCTAssertEqual(plan.duration, RecoveryMath.fallbackDuration)
        XCTAssertNil(plan.peakBPM)
        XCTAssertNil(plan.targetBPM)
    }

    func testUsesCurrentBPMWhenSamplesEmpty() {
        let plan = RecoveryMath.plan(at: t0, heartRates: [], currentBPM: 160)
        XCTAssertEqual(plan.peakBPM, 160)
        XCTAssertEqual(plan.targetBPM, RecoveryMath.targetBPM(peak: 160))
        XCTAssertEqual(plan.duration, RecoveryMath.duration(peakBPM: 160), accuracy: 0.001)
    }

    func testPeakIgnoresSamplesOutsideWindow() {
        let samples = [
            HeartRateSample(timestamp: t0.timeIntervalSince1970 - 120, bpm: 190),
            HeartRateSample(timestamp: t0.timeIntervalSince1970 - 10, bpm: 148),
            HeartRateSample(timestamp: t0.timeIntervalSince1970 - 2, bpm: 162),
        ]
        XCTAssertEqual(RecoveryMath.peakBPM(heartRates: samples, around: t0), 162)
    }

    func testTargetIsSeventyEightPercentOfPeak() {
        XCTAssertEqual(RecoveryMath.targetBPM(peak: 160), 125)
        XCTAssertEqual(RecoveryMath.targetBPM(peak: 100), 90)
        XCTAssertEqual(RecoveryMath.targetBPM(peak: 80), 90)
    }

    func testDurationScalesWithPeakAndClamps() {
        XCTAssertEqual(RecoveryMath.duration(peakBPM: nil), 150)
        XCTAssertEqual(RecoveryMath.duration(peakBPM: 100), 90, accuracy: 0.001)
        XCTAssertEqual(RecoveryMath.duration(peakBPM: 180), 210, accuracy: 0.001)
        XCTAssertEqual(RecoveryMath.duration(peakBPM: 80), RecoveryMath.minimumDuration)
        XCTAssertEqual(RecoveryMath.duration(peakBPM: 220), RecoveryMath.maximumDuration)
    }

    func testRemainingCountsDownAndClampsAtZero() {
        let plan = RestPlan(startedAt: t0.timeIntervalSince1970, duration: 120)
        XCTAssertEqual(RecoveryMath.remaining(plan: plan, now: t0), 120)
        XCTAssertEqual(
            RecoveryMath.remaining(plan: plan, now: t0.addingTimeInterval(45)),
            75,
            accuracy: 0.001
        )
        XCTAssertEqual(
            RecoveryMath.remaining(plan: plan, now: t0.addingTimeInterval(200)),
            0
        )
    }

    func testNotReadyFromHeartRateBeforeMinimumElapsed() {
        let plan = RecoveryMath.plan(
            at: t0,
            heartRates: [HeartRateSample(timestamp: t0.timeIntervalSince1970, bpm: 160)],
            currentBPM: 160
        )
        let early = t0.addingTimeInterval(10)
        let phase = RecoveryMath.phase(plan: plan, now: early, currentBPM: 90)
        guard case .resting = phase else {
            return XCTFail("expected resting, got \(phase)")
        }
    }

    func testRecoversEarlyWhenHeartRateDrops() {
        let plan = RecoveryMath.plan(
            at: t0,
            heartRates: [HeartRateSample(timestamp: t0.timeIntervalSince1970, bpm: 160)],
            currentBPM: 160
        )
        let later = t0.addingTimeInterval(30)
        XCTAssertEqual(
            RecoveryMath.phase(plan: plan, now: later, currentBPM: 110),
            .recovered
        )
    }

    func testReadyWhenTimeoutElapsesEvenIfHeartRateHigh() {
        let plan = RecoveryMath.plan(
            at: t0,
            heartRates: [HeartRateSample(timestamp: t0.timeIntervalSince1970, bpm: 160)],
            currentBPM: 160
        )
        let later = t0.addingTimeInterval(plan.duration)
        XCTAssertEqual(
            RecoveryMath.phase(plan: plan, now: later, currentBPM: 150),
            .ready
        )
        XCTAssertTrue(RecoveryMath.phase(plan: plan, now: later, currentBPM: 150).isFinished)
    }

    func testStillRestingWhenHeartRateStaysHigh() {
        let plan = RecoveryMath.plan(
            at: t0,
            heartRates: [HeartRateSample(timestamp: t0.timeIntervalSince1970, bpm: 160)],
            currentBPM: 160
        )
        let later = t0.addingTimeInterval(40)
        let phase = RecoveryMath.phase(plan: plan, now: later, currentBPM: 150)
        guard case .resting(let remaining) = phase else {
            return XCTFail("expected resting, got \(phase)")
        }
        XCTAssertGreaterThan(remaining, 0)
        XCTAssertFalse(phase.isFinished)
    }
}

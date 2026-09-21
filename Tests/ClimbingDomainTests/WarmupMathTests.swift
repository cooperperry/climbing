import XCTest
@testable import ClimbingDomain

final class WarmupMathTests: XCTestCase {
    func testStillWarmingWhenOnlyTimeHasPassed() {
        XCTAssertFalse(WarmupMath.isComplete(elapsed: 10 * 60, climbingTime: 0, gainMeters: 0))
    }

    func testStillWarmingWhenOnlyAQuickGoHappened() {
        XCTAssertFalse(WarmupMath.isComplete(elapsed: 60, climbingTime: 40, gainMeters: 12))
    }

    func testCompleteAfterTimeAndClimbing() {
        XCTAssertTrue(WarmupMath.isComplete(elapsed: 8 * 60, climbingTime: 3 * 60, gainMeters: 0))
    }

    func testCompleteAfterTimeAndVerticalGain() {
        XCTAssertTrue(WarmupMath.isComplete(elapsed: 8 * 60, climbingTime: 30, gainMeters: 8))
    }

    func testLifetimeGainAddsSessionOnTopOfPersisted() {
        XCTAssertEqual(LifetimeGainMath.total(persisted: 400, session: 12), 412)
        XCTAssertEqual(LifetimeGainMath.total(persisted: -1, session: 5), 5)
    }

    func testLifetimeTargetReachesElCapAcrossSessions() {
        let lifetime = LifetimeGainMath.total(persisted: 400, session: 20)
        XCTAssertEqual(LandmarkMath.sessionTarget(gainMeters: lifetime).name, Landmark.elCapitan.name)
        let progress = LandmarkMath.progress(gainMeters: lifetime, toward: .elCapitan)
        XCTAssertGreaterThan(progress.completions, 0.4)
        XCTAssertLessThan(progress.completions, 1)
    }

    func testCuePrefersRestOverWarmup() {
        let plan = RestPlan(startedAt: 0, duration: 120)
        let now = Date(timeIntervalSince1970: 30)
        XCTAssertEqual(
            WorkoutCueMath.cue(
                warmupComplete: false,
                showWarmedUpUntil: nil,
                restPlan: plan,
                currentBPM: nil,
                now: now
            ),
            .resting(remaining: 90)
        )
    }

    func testCueIsReadyWhenRestFinishes() {
        let plan = RestPlan(startedAt: 0, duration: 60)
        let now = Date(timeIntervalSince1970: 60)
        XCTAssertEqual(
            WorkoutCueMath.cue(
                warmupComplete: true,
                showWarmedUpUntil: nil,
                restPlan: plan,
                currentBPM: nil,
                now: now
            ),
            .readyToSend
        )
    }

    func testWarmedUpBannerThenClears() {
        let until = Date(timeIntervalSince1970: 20)
        XCTAssertEqual(
            WorkoutCueMath.cue(
                warmupComplete: true,
                showWarmedUpUntil: until,
                restPlan: nil,
                currentBPM: nil,
                now: Date(timeIntervalSince1970: 10)
            ),
            .warmedUp
        )
        XCTAssertEqual(
            WorkoutCueMath.cue(
                warmupComplete: true,
                showWarmedUpUntil: until,
                restPlan: nil,
                currentBPM: nil,
                now: Date(timeIntervalSince1970: 21)
            ),
            .none
        )
    }
}

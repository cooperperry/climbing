import XCTest
@testable import ClimbingDomain

final class EffortTraceTests: XCTestCase {
    func testIntensityIsVectorMagnitude() {
        XCTAssertEqual(EffortMath.intensity(userX: 3, userY: 4, userZ: 0), 5, accuracy: 0.0001)
        XCTAssertEqual(EffortMath.intensity(userX: 0, userY: 0, userZ: 0), 0, accuracy: 0.0001)
    }

    func testVerticalnessIsOneWhenAccelerationFollowsGravity() {
        let value = EffortMath.verticalness(
            userX: 0, userY: 0, userZ: 0.4,
            gravityX: 0, gravityY: 0, gravityZ: 1
        )
        XCTAssertEqual(value, 1, accuracy: 0.0001)
    }

    func testVerticalnessIsZeroWhenAccelerationIsPerpendicularToGravity() {
        let value = EffortMath.verticalness(
            userX: 0.3, userY: 0, userZ: 0,
            gravityX: 0, gravityY: 0, gravityZ: 1
        )
        XCTAssertEqual(value, 0, accuracy: 0.0001)
    }

    func testVerticalnessIsNeutralWhenStill() {
        XCTAssertEqual(
            EffortMath.verticalness(
                userX: 0, userY: 0, userZ: 0,
                gravityX: 0, gravityY: 0, gravityZ: 1
            ),
            0.5,
            accuracy: 0.0001
        )
    }

    func testCharacterThresholds() {
        XCTAssertEqual(EffortMath.character([0.7, 0.8, 0.9]), .vertical)
        XCTAssertEqual(EffortMath.character([0.1, 0.2, 0.3]), .traverse)
        XCTAssertEqual(EffortMath.character([0.5, 0.55, 0.45]), .mixed)
        XCTAssertEqual(EffortMath.character([]), .unknown)
    }

    func testDownsampleKeepsOneHeartRatePerInterval() {
        let samples = (0..<10).map { i in
            HeartRateSample(timestamp: Double(i) * 0.5, bpm: 120)
        }
        let sampled = EffortMath.downsample(samples, interval: 1)
        XCTAssertEqual(sampled.count, 5)
        zip(sampled.map(\.timestamp), [0.0, 1.0, 2.0, 3.0, 4.0]).forEach { actual, expected in
            XCTAssertEqual(actual, expected, accuracy: 0.0001)
        }
    }

    func testWindowCapsAt45SecondsAndNotBeforeSession() {
        let logged = Date(timeIntervalSince1970: 200)
        let sessionStart = Date(timeIntervalSince1970: 180)
        let bounds = EffortWindow.bounds(
            loggedAt: logged, sessionStart: sessionStart, previousLogAt: nil
        )
        XCTAssertEqual(bounds.start.timeIntervalSince1970, 180)
        XCTAssertEqual(bounds.end.timeIntervalSince1970, 200)
    }

    func testWindowUsesPreviousLogWhenMoreRecentThanCap() {
        let logged = Date(timeIntervalSince1970: 200)
        let sessionStart = Date(timeIntervalSince1970: 0)
        let previous = Date(timeIntervalSince1970: 170)
        let bounds = EffortWindow.bounds(
            loggedAt: logged, sessionStart: sessionStart, previousLogAt: previous
        )
        XCTAssertEqual(bounds.start.timeIntervalSince1970, 170)
    }

    func testWindowFallsBackTo45SecondCap() {
        let logged = Date(timeIntervalSince1970: 200)
        let sessionStart = Date(timeIntervalSince1970: 0)
        let bounds = EffortWindow.bounds(
            loggedAt: logged, sessionStart: sessionStart, previousLogAt: nil
        )
        XCTAssertEqual(bounds.start.timeIntervalSince1970, 155)
    }

    func testTraceIsHeartRateOverTime() {
        let start = Date(timeIntervalSince1970: 0)
        let end = Date(timeIntervalSince1970: 10)
        let hrs = [
            HeartRateSample(timestamp: 1, bpm: 110),
            HeartRateSample(timestamp: 5, bpm: 130),
            HeartRateSample(timestamp: 9, bpm: 148),
        ]
        let motion = [
            MotionFrame(
                timestamp: 1, userX: 0, userY: 0, userZ: 1,
                gravityX: 0, gravityY: 0, gravityZ: 1
            )
        ]
        let trace = EffortMath.trace(motion: motion, heartRates: hrs, start: start, end: end)
        XCTAssertFalse(trace.hasMotion)
        XCTAssertTrue(trace.hasHeartRate)
        XCTAssertEqual(trace.character, .unknown)
        XCTAssertEqual(trace.points.map(\.heartRate), [110, 130, 148])
        XCTAssertEqual(trace.averageHeartRate, 129)
        XCTAssertEqual(trace.peakHeartRate, 148)
    }

    func testEmptyTraceHasNoData() {
        let start = Date(timeIntervalSince1970: 0)
        let trace = EffortMath.trace(heartRates: [], start: start, end: start)
        XCTAssertFalse(trace.hasData)
        XCTAssertEqual(trace.character, .unknown)
    }

    func testDemoTraceIsVisibleWithoutSensors() {
        XCTAssertTrue(EffortTrace.demo.hasData)
        XCTAssertTrue(EffortTrace.demo.hasHeartRate)
        XCTAssertEqual(EffortTrace.demo.peakHeartRate, 153)
    }
}

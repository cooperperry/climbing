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

    func testDownsampleKeepsOneFramePerInterval() {
        let frames = (0..<10).map { i in
            MotionFrame(
                timestamp: Double(i) * 0.1,
                userX: Double(i), userY: 0, userZ: 0,
                gravityX: 0, gravityY: 0, gravityZ: 1
            )
        }
        let sampled = EffortMath.downsample(frames, interval: 0.2)
        XCTAssertEqual(sampled.count, 5)
        zip(sampled.map(\.timestamp), [0.0, 0.2, 0.4, 0.6, 0.8]).forEach { actual, expected in
            XCTAssertEqual(actual, expected, accuracy: 0.0001)
        }
    }

    func testNearestHeartRateRespectsMaxGap() {
        let samples = [
            HeartRateSample(timestamp: 10, bpm: 120),
            HeartRateSample(timestamp: 20, bpm: 150),
        ]
        XCTAssertEqual(EffortMath.nearestHeartRate(samples, at: 21, maxGap: 8), 150)
        XCTAssertNil(EffortMath.nearestHeartRate(samples, at: 40, maxGap: 8))
        XCTAssertNil(EffortMath.nearestHeartRate([], at: 10))
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

    func testTraceOverlaysHeartRateOnMotion() {
        let start = Date(timeIntervalSince1970: 0)
        let end = Date(timeIntervalSince1970: 2)
        let motion = [
            MotionFrame(
                timestamp: 0.4, userX: 0, userY: 0, userZ: 0.5,
                gravityX: 0, gravityY: 0, gravityZ: 1
            ),
            MotionFrame(
                timestamp: 1.2, userX: 0.4, userY: 0, userZ: 0,
                gravityX: 0, gravityY: 0, gravityZ: 1
            ),
        ]
        let hrs = [HeartRateSample(timestamp: 1.0, bpm: 142.4)]
        let trace = EffortMath.trace(motion: motion, heartRates: hrs, start: start, end: end)

        XCTAssertTrue(trace.hasMotion)
        XCTAssertTrue(trace.hasHeartRate)
        XCTAssertEqual(trace.duration, 2)
        XCTAssertEqual(trace.character, .mixed)
        XCTAssertEqual(trace.averageHeartRate, 142)
        XCTAssertEqual(trace.points.count, 2)
        XCTAssertEqual(trace.points[0].heartRate, 142)
    }

    func testTraceIsHeartRateOnlyWhenMotionIsMissing() {
        let start = Date(timeIntervalSince1970: 0)
        let end = Date(timeIntervalSince1970: 10)
        let hrs = [
            HeartRateSample(timestamp: 1, bpm: 110),
            HeartRateSample(timestamp: 5, bpm: 130),
        ]
        let trace = EffortMath.trace(motion: [], heartRates: hrs, start: start, end: end)
        XCTAssertFalse(trace.hasMotion)
        XCTAssertTrue(trace.hasHeartRate)
        XCTAssertEqual(trace.character, .unknown)
        XCTAssertEqual(trace.points.map(\.heartRate), [110, 130])
    }

    func testEmptyTraceHasNoData() {
        let start = Date(timeIntervalSince1970: 0)
        let trace = EffortMath.trace(motion: [], heartRates: [], start: start, end: start)
        XCTAssertFalse(trace.hasData)
        XCTAssertEqual(trace.character, .unknown)
    }
}

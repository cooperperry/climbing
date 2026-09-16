import XCTest
@testable import ClimbingDomain

final class LandmarkTests: XCTestCase {
    func testCanonicalHeightsInFeet() {
        XCTAssertEqual(Landmark.empireState.heightFeet, 1_250, accuracy: 0.01)
        XCTAssertEqual(Landmark.elCapitan.heightFeet, 3_000, accuracy: 0.01)
        XCTAssertEqual(Landmark.halfDome.heightFeet, 4_800, accuracy: 0.01)
        XCTAssertEqual(Landmark.everest.heightFeet, 29_031, accuracy: 0.5)
    }

    func testPercentAndCompletions() {
        XCTAssertEqual(Landmark.elCapitan.percentComplete(gainMeters: 0), 0)
        XCTAssertEqual(Landmark.elCapitan.percentComplete(gainMeters: 457.2), 0.5, accuracy: 0.0001)
        XCTAssertEqual(Landmark.elCapitan.percentComplete(gainMeters: 9_000), 1)
        XCTAssertEqual(Landmark.elCapitan.completions(gainMeters: 914.4 * 3.2), 3.2, accuracy: 0.0001)
    }

    func testSessionTargetStepsThroughLandmarks() {
        XCTAssertEqual(LandmarkMath.sessionTarget(gainMeters: 0).name, Landmark.empireState.name)
        XCTAssertEqual(LandmarkMath.sessionTarget(gainMeters: 400).name, Landmark.elCapitan.name)
        XCTAssertEqual(LandmarkMath.sessionTarget(gainMeters: 1_000).name, Landmark.halfDome.name)
        XCTAssertEqual(LandmarkMath.sessionTarget(gainMeters: 20_000).name, Landmark.everest.name)
    }

    func testLapProgressOnExactCompletion() {
        let progress = LandmarkMath.progress(gainMeters: 381, toward: .empireState)
        XCTAssertEqual(progress.completions, 1, accuracy: 0.0001)
        XCTAssertEqual(progress.lapPercent, 1, accuracy: 0.0001)
        XCTAssertEqual(progress.remainingMeters, 0, accuracy: 0.0001)
    }
}

final class ElevationMathTests: XCTestCase {
    func testFirstSampleSeedsWithoutGain() {
        var filter = ElevationFilter()
        XCTAssertEqual(filter.ingest(1.0), 1.0)
        XCTAssertEqual(filter.gainMeters, 0)
        XCTAssertEqual(filter.maxAltitude, 1.0)
    }

    func testNoiseFloorIgnoresTinyJitter() {
        var filter = ElevationFilter()
        filter.ingest(0)
        XCTAssertNil(filter.ingest(0.4))
        XCTAssertEqual(filter.gainMeters, 0)
        XCTAssertEqual(filter.ingest(0.6), 0.6)
        XCTAssertEqual(filter.gainMeters, 0.6, accuracy: 0.0001)
    }

    func testIdlePressureDriftDoesNotCountAsGain() {
        var filter = ElevationFilter()
        filter.ingest(0)
        XCTAssertNil(filter.ingest(1.2, countingGain: false))
        XCTAssertEqual(filter.gainMeters, 0)
        XCTAssertEqual(filter.ingest(2.0, countingGain: true), 2.0)
        XCTAssertEqual(filter.gainMeters, 0.8, accuracy: 0.0001)
    }

    func testDescentDoesNotReduceGain() {
        var filter = ElevationFilter()
        filter.ingest(0)
        filter.ingest(2.0)
        filter.ingest(0.5)
        XCTAssertEqual(filter.gainMeters, 2.0, accuracy: 0.0001)
        XCTAssertEqual(filter.maxAltitude, 2.0, accuracy: 0.0001)
    }

    func testVerticalSpeedOverOneMinute() {
        let samples: [(TimeInterval, Double)] = [
            (0, 0),
            (60, 12),
        ]
        XCTAssertEqual(
            VerticalSpeed.metersPerMinute(samples: samples.map { (t: $0.0, gain: $0.1) }, now: 60),
            12,
            accuracy: 0.0001
        )
    }

    func testGainFormatUsesFeetByDefault() {
        let text = ElevationFormat.gain(meters: 377.952)
        XCTAssertTrue(text.hasPrefix("+"))
        XCTAssertTrue(text.contains("FT"))
        XCTAssertTrue(text.contains("1"))
    }

    func testSpeedFormatUsesFeetPerMinute() {
        XCTAssertEqual(ElevationFormat.speed(metersPerMinute: 3.048), "10 FT/M")
        XCTAssertEqual(ElevationFormat.speed(metersPerMinute: 10, useFeet: false), "10 M/MIN")
    }
}

final class ClimbSessionPayloadTests: XCTestCase {
    func testLiveAveragePeakAndSparkline() {
        let samples = (0..<100).map { HeartRateSample(timestamp: Double($0), bpm: Double(80 + $0)) }
        let payload = ClimbSessionPayload(
            startDate: Date(),
            heartRateSeries: samples,
            currentBPM: 179
        )
        XCTAssertTrue(payload.isLive)
        XCTAssertEqual(payload.sparkline.count, 90)
        XCTAssertEqual(payload.sparkline.first?.bpm, 90)
        XCTAssertEqual(payload.peakBPM, 179)
        XCTAssertEqual(payload.averageBPM, 130)
    }
}

final class StrainMathTests: XCTestCase {
    func testZoneBoundaries() {
        XCTAssertEqual(HeartRateZone.zone(bpm: 100, maxHR: 200), .z1)
        XCTAssertEqual(HeartRateZone.zone(bpm: 130, maxHR: 200), .z2)
        XCTAssertEqual(HeartRateZone.zone(bpm: 150, maxHR: 200), .z3)
        XCTAssertEqual(HeartRateZone.zone(bpm: 170, maxHR: 200), .z4)
        XCTAssertEqual(HeartRateZone.zone(bpm: 190, maxHR: 200), .z5)
    }

    func testZoneReadoutIsPlainLanguage() {
        XCTAssertEqual(HeartRateZone.z1.readout, "Zone 1 · Easy")
        XCTAssertEqual(HeartRateZone.z3.readout, "Zone 3 · Hard")
        XCTAssertEqual(HeartRateZone.z5.readout, "Zone 5 · Max")
    }

    func testEdwardsTRIMP() {
        let trimp = StrainMath.trimp(zoneSeconds: [.z1: 60, .z5: 60])
        XCTAssertEqual(trimp, 1 + 5, accuracy: 0.0001)
    }

    func testPhaseDetection() {
        XCTAssertEqual(StrainMath.phase(verticalSpeedMPerMin: 2, motionVariance: 0), .climbing)
        XCTAssertEqual(StrainMath.phase(verticalSpeedMPerMin: 0, motionVariance: 0.2), .climbing)
        XCTAssertEqual(StrainMath.phase(verticalSpeedMPerMin: 0.2, motionVariance: 0.01), .resting)
    }

    func testBodyStressClampsToTen() {
        let high = StrainMath.bodyStressIndex(
            trimp: 500,
            elapsed: 60,
            motionVariance: 1,
            hrvSDNN: 0
        )
        XCTAssertEqual(high, 10, accuracy: 0.0001)
        let low = StrainMath.bodyStressIndex(
            trimp: 0,
            elapsed: 600,
            motionVariance: 0,
            hrvSDNN: 80
        )
        XCTAssertEqual(low, 0, accuracy: 0.0001)
    }

    func testCaloriesFromMET() {
        // 9.5 MET * 70 kg * 1 hour
        XCTAssertEqual(StrainMath.calories(met: 9.5, weightKg: 70, seconds: 3_600), 665, accuracy: 0.001)
    }

    func testMaxHRFromAge() {
        XCTAssertEqual(StrainMath.maxHR(ageYears: 40), 180)
        XCTAssertEqual(StrainMath.maxHR(ageYears: nil), StrainMath.defaultMaxHR)
    }
}

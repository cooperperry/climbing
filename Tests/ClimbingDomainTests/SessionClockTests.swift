import XCTest
@testable import ClimbingDomain

final class SessionClockTests: XCTestCase {
    func testElapsedBetweenDates() {
        let start = Date(timeIntervalSince1970: 1_000)
        let end = Date(timeIntervalSince1970: 1_125)
        XCTAssertEqual(SessionClock.elapsed(from: start, to: end), 125, accuracy: 0.0001)
    }

    func testElapsedClampsNegativeToZero() {
        let start = Date(timeIntervalSince1970: 2_000)
        let end = Date(timeIntervalSince1970: 1_900)
        XCTAssertEqual(SessionClock.elapsed(from: start, to: end), 0, accuracy: 0.0001)
    }

    func testFormatUnderOneMinute() {
        XCTAssertEqual(SessionClock.format(0), "0:00")
        XCTAssertEqual(SessionClock.format(5), "0:05")
        XCTAssertEqual(SessionClock.format(59), "0:59")
    }

    func testFormatMinutes() {
        XCTAssertEqual(SessionClock.format(60), "1:00")
        XCTAssertEqual(SessionClock.format(65), "1:05")
        XCTAssertEqual(SessionClock.format(599), "9:59")
    }

    func testFormatHours() {
        XCTAssertEqual(SessionClock.format(3_600), "1:00:00")
        XCTAssertEqual(SessionClock.format(3_661), "1:01:01")
        XCTAssertEqual(SessionClock.format(7_384), "2:03:04")
    }

    func testFormatTruncatesFractionalSeconds() {
        XCTAssertEqual(SessionClock.format(65.9), "1:05")
    }

    func testFormatClampsNegative() {
        XCTAssertEqual(SessionClock.format(-10), "0:00")
    }
}

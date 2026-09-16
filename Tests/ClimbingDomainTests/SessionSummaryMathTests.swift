import XCTest
@testable import ClimbingDomain

final class SessionSummaryMathTests: XCTestCase {
    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }()

    private func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int, _ minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute))!
    }

    func testTwoWorkoutsOnTheSameDayStaySeparate() {
        let morning = SessionHealth(
            id: "am",
            startDate: date(2026, 9, 15, 9),
            endDate: date(2026, 9, 15, 10, 30),
            calories: 100,
            gainMeters: 2
        )
        let evening = SessionHealth(
            id: "pm",
            startDate: date(2026, 9, 15, 18),
            endDate: date(2026, 9, 15, 19, 15),
            calories: 80,
            gainMeters: 3
        )
        let sessions = SessionSummaryMath.assemble(workouts: [morning, evening], climbs: [])
        XCTAssertEqual(sessions.map(\.id), ["pm", "am"])
        XCTAssertEqual(sessions[0].health?.calories, 80)
        XCTAssertEqual(sessions[1].health?.calories, 100)
    }

    func testClimbAttachesToTheContainingWorkout() {
        let workout = SessionHealth(
            id: "w",
            startDate: date(2026, 9, 15, 9),
            endDate: date(2026, 9, 15, 11)
        )
        let during = SessionClimb(
            loggedAt: date(2026, 9, 15, 10),
            gradeLabel: "V4",
            outcome: .send,
            discipline: .boulder
        )
        let after = SessionClimb(
            loggedAt: date(2026, 9, 15, 14),
            gradeLabel: "V5",
            outcome: .flash,
            discipline: .boulder
        )
        let sessions = SessionSummaryMath.assemble(workouts: [workout], climbs: [during, after])
        XCTAssertEqual(sessions.count, 2)
        XCTAssertEqual(sessions.first { $0.id == "w" }?.tops.map(\.gradeLabel), ["V4"])
        XCTAssertEqual(sessions.first { $0.id != "w" }?.tops.map(\.gradeLabel), ["V5"])
    }

    func testNewestSessionIsFirst() {
        let monday = SessionHealth(
            id: "mon",
            startDate: date(2026, 9, 14, 12),
            endDate: date(2026, 9, 14, 13)
        )
        let tuesday = SessionHealth(
            id: "tue",
            startDate: date(2026, 9, 15, 12),
            endDate: date(2026, 9, 15, 13)
        )
        let sessions = SessionSummaryMath.assemble(workouts: [monday, tuesday], climbs: [])
        XCTAssertEqual(sessions.map(\.id), ["tue", "mon"])
    }

    func testClosePhoneClimbsShareASession() {
        let first = SessionClimb(
            loggedAt: date(2026, 9, 15, 18),
            gradeLabel: "V2",
            outcome: .send,
            discipline: .boulder
        )
        let second = SessionClimb(
            loggedAt: date(2026, 9, 15, 18, 40),
            gradeLabel: "V3",
            outcome: .send,
            discipline: .boulder
        )
        let sessions = SessionSummaryMath.assemble(workouts: [], climbs: [first, second])
        XCTAssertEqual(sessions.count, 1)
        XCTAssertEqual(sessions[0].tops.map(\.gradeLabel), ["V3", "V2"])
        XCTAssertNil(sessions[0].health)
    }

    func testFarPhoneClimbsSplitIntoSessions() {
        let first = SessionClimb(
            loggedAt: date(2026, 9, 15, 10),
            gradeLabel: "V2",
            outcome: .send,
            discipline: .boulder
        )
        let second = SessionClimb(
            loggedAt: date(2026, 9, 15, 14),
            gradeLabel: "V3",
            outcome: .send,
            discipline: .boulder
        )
        let sessions = SessionSummaryMath.assemble(workouts: [], climbs: [second, first])
        XCTAssertEqual(sessions.count, 2)
        XCTAssertEqual(sessions[0].tops.map(\.gradeLabel), ["V3"])
        XCTAssertEqual(sessions[1].tops.map(\.gradeLabel), ["V2"])
    }

    func testProjectsStayOnTheSession() {
        let workout = SessionHealth(
            id: "w",
            startDate: date(2026, 9, 15, 9),
            endDate: date(2026, 9, 15, 11)
        )
        let climb = SessionClimb(
            loggedAt: date(2026, 9, 15, 10),
            gradeLabel: "V8",
            outcome: .project,
            discipline: .boulder
        )
        let session = SessionSummaryMath.assemble(workouts: [workout], climbs: [climb])[0]
        XCTAssertTrue(session.tops.isEmpty)
        XCTAssertEqual(session.climbs.map(\.gradeLabel), ["V8"])
    }

    func testWorkoutWithNoClimbsStillAppears() {
        let workout = SessionHealth(
            id: "solo",
            startDate: date(2026, 9, 15, 9),
            endDate: date(2026, 9, 15, 10),
            calories: 220
        )
        let sessions = SessionSummaryMath.assemble(workouts: [workout], climbs: [])
        XCTAssertEqual(sessions.count, 1)
        XCTAssertEqual(sessions[0].health?.calories, 220)
        XCTAssertTrue(sessions[0].climbs.isEmpty)
    }
}

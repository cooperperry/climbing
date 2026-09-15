import XCTest
@testable import ClimbingDomain

final class GymDayMathTests: XCTestCase {
    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }()

    private func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int = 12) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour))!
    }

    func testSameCalendarDayGroupsClimbsAndHealth() {
        let morning = DayClimb(
            loggedAt: date(2026, 9, 15, 9),
            gradeLabel: "V4",
            outcome: .send,
            discipline: .boulder
        )
        let afternoon = DayClimb(
            loggedAt: date(2026, 9, 15, 18),
            gradeLabel: "5.10a",
            outcome: .flash,
            discipline: .lead
        )
        let health = DayHealth(startDate: date(2026, 9, 15, 9), calories: 220, gainMeters: 4)
        let days = GymDayMath.group(
            climbs: [morning, afternoon],
            workouts: [health],
            calendar: calendar
        )
        XCTAssertEqual(days.count, 1)
        XCTAssertEqual(days[0].tops(in: .boulder).map(\.gradeLabel), ["V4"])
        XCTAssertEqual(days[0].tops(in: .lead).map(\.gradeLabel), ["5.10a"])
        XCTAssertEqual(days[0].health?.calories, 220)
    }

    func testDifferentDaysStayApart() {
        let monday = DayClimb(
            loggedAt: date(2026, 9, 14, 12),
            gradeLabel: "V2",
            outcome: .send,
            discipline: .boulder
        )
        let tuesday = DayClimb(
            loggedAt: date(2026, 9, 15, 12),
            gradeLabel: "V3",
            outcome: .send,
            discipline: .boulder
        )
        let days = GymDayMath.group(climbs: [tuesday, monday], workouts: [], calendar: calendar)
        XCTAssertEqual(days.map(\.dayStart), [
            GymDayMath.startOfDay(date(2026, 9, 15), calendar: calendar),
            GymDayMath.startOfDay(date(2026, 9, 14), calendar: calendar),
        ])
    }

    func testProjectsAreNotListedAsTops() {
        let climb = DayClimb(
            loggedAt: date(2026, 9, 15),
            gradeLabel: "V8",
            outcome: .project,
            discipline: .boulder
        )
        let day = GymDayMath.group(climbs: [climb], workouts: [], calendar: calendar)[0]
        XCTAssertTrue(day.tops.isEmpty)
        XCTAssertEqual(day.climbs.count, 1)
    }

    func testMergesTwoWorkoutsOnTheSameDay() {
        let a = DayHealth(startDate: date(2026, 9, 15, 9), calories: 100, gainMeters: 2, peakBPM: 140)
        let b = DayHealth(startDate: date(2026, 9, 15, 18), calories: 80, gainMeters: 3, peakBPM: 160)
        let merged = DayHealth.merged([a, b])
        XCTAssertEqual(merged?.calories, 180)
        XCTAssertEqual(merged?.gainMeters, 5)
        XCTAssertEqual(merged?.peakBPM, 160)
    }
}

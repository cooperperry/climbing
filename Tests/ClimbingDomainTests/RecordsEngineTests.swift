import XCTest
@testable import ClimbingDomain

final class RecordsEngineTests: XCTestCase {
    func testFirstSessionSetsEveryApplicableRecord() {
        let current = SessionTotals(
            climbs: 5, sends: 3, flashes: 1, points: 200,
            hardestSendGradeIndex: 6, durationSeconds: 3_600
        )
        let records = RecordsEngine.newRecords(
            current: current, hardestSendGradeLabel: "V5", previous: PreviousBests()
        )
        XCTAssertEqual(Set(records.map(\.id)),
                       ["hardestSend", "mostSends", "mostPoints", "longestSession"])
    }

    func testNoRecordsWhenNothingBeaten() {
        let current = SessionTotals(
            climbs: 2, sends: 2, flashes: 0, points: 100,
            hardestSendGradeIndex: 4, durationSeconds: 1_000
        )
        let previous = PreviousBests(
            hardestSendGradeIndex: 6, mostSendsInSession: 5,
            mostPointsInSession: 300, longestSessionSeconds: 5_000
        )
        XCTAssertTrue(
            RecordsEngine.newRecords(current: current, hardestSendGradeLabel: "V2", previous: previous).isEmpty
        )
    }

    func testOnlyPointsBeaten() {
        let current = SessionTotals(
            climbs: 4, sends: 2, flashes: 0, points: 500,
            hardestSendGradeIndex: 4, durationSeconds: 1_000
        )
        let previous = PreviousBests(
            hardestSendGradeIndex: 6, mostSendsInSession: 5,
            mostPointsInSession: 300, longestSessionSeconds: 5_000
        )
        let records = RecordsEngine.newRecords(
            current: current, hardestSendGradeLabel: "V2", previous: previous
        )
        XCTAssertEqual(records.map(\.id), ["mostPoints"])
        XCTAssertEqual(records.first?.detail, "500 pts")
    }

    func testHardestSendMustStrictlyExceedPrevious() {
        let current = SessionTotals(sends: 1, points: 70, hardestSendGradeIndex: 6, durationSeconds: 10)
        let previous = PreviousBests(
            hardestSendGradeIndex: 6, mostSendsInSession: 10,
            mostPointsInSession: 1_000, longestSessionSeconds: 10_000
        )
        // Same hardest index is not a new record.
        let records = RecordsEngine.newRecords(
            current: current, hardestSendGradeLabel: "V5", previous: previous
        )
        XCTAssertFalse(records.contains { $0.id == "hardestSend" })
    }

    func testNoSendsMeansNoSendOrHardestRecords() {
        let current = SessionTotals(
            climbs: 3, sends: 0, flashes: 0, points: 12,
            hardestSendGradeIndex: nil, durationSeconds: 800
        )
        let records = RecordsEngine.newRecords(
            current: current, hardestSendGradeLabel: nil, previous: PreviousBests()
        )
        XCTAssertFalse(records.contains { $0.id == "hardestSend" })
        XCTAssertFalse(records.contains { $0.id == "mostSends" })
        // Points and duration are still first-time records.
        XCTAssertTrue(records.contains { $0.id == "mostPoints" })
        XCTAssertTrue(records.contains { $0.id == "longestSession" })
    }

    func testRecordDisplayStrings() {
        XCTAssertEqual(PersonalRecord.hardestSend(grade: "V7").detail, "V7")
        XCTAssertEqual(PersonalRecord.mostSends(9).detail, "9")
        XCTAssertEqual(PersonalRecord.longestSession(3_661).detail, "1:01:01")
    }
}

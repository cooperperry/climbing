import XCTest
import SwiftData
@testable import Climbing

/// Tests the SwiftData ↔ ScoreEngine bridge (grade index lookup + points).
/// Runs in Xcode / the iOS Simulator, not the Linux Cloud Agent.
@MainActor
final class ScoreBridgeTests: XCTestCase {
    private func makeContext() throws -> ModelContext {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(
            for: ClimbingSession.self, ClimbLog.self, CustomGradeScale.self,
            configurations: config
        )
        return ModelContext(container)
    }

    func testGradeIndexResolvesThroughScale() throws {
        let context = try makeContext()
        let scale = CustomGradeScale(template: .standardVScale(), isDefault: true)
        context.insert(scale)
        let log = ClimbLog(gradeLabel: "V5", outcome: .send, style: .crimp, gradeScale: scale)
        context.insert(log)

        XCTAssertEqual(log.gradeIndex, 6)          // VB=0, V0=1, ..., V5=6
        XCTAssertEqual(log.points, 70)             // difficulty 70 * send 1.0
    }

    func testMissingScaleFallsBackToEasiestIndex() throws {
        let context = try makeContext()
        let log = ClimbLog(gradeLabel: "V5", outcome: .send, style: .crimp)
        context.insert(log)

        XCTAssertEqual(log.gradeIndex, 0)
        XCTAssertEqual(log.points, 10)             // difficulty 10 * send 1.0
    }

    func testFlashScoresMoreThanSend() throws {
        let context = try makeContext()
        let scale = CustomGradeScale(template: .standardVScale(), isDefault: true)
        context.insert(scale)
        let flash = ClimbLog(gradeLabel: "V4", outcome: .flash, style: .sloper, gradeScale: scale)
        let send = ClimbLog(gradeLabel: "V4", outcome: .send, style: .sloper, gradeScale: scale)
        context.insert(flash)
        context.insert(send)

        XCTAssertGreaterThan(flash.points, send.points)
    }

    func testSessionScoreAndHardestSend() throws {
        let context = try makeContext()
        let scale = CustomGradeScale(template: .standardVScale(), isDefault: true)
        context.insert(scale)
        let session = ClimbingSession()
        context.insert(session)

        for (grade, outcome) in [("V2", ClimbOutcome.flash), ("V6", .send), ("V3", .attempt)] {
            context.insert(
                ClimbLog(gradeLabel: grade, outcome: outcome, style: .crimp,
                         session: session, gradeScale: scale)
            )
        }
        try context.save()

        // Indices: V2=3, V6=7, V3=4.
        // V2 flash: 40 * 1.5 = 60; V6 send: 80; V3 attempt: 50 * 0.1 = 5.
        XCTAssertEqual(session.score, 60 + 80 + 5)
        XCTAssertEqual(session.flashCount, 1)
        XCTAssertEqual(session.hardestSend?.gradeLabel, "V6")
    }
}

import XCTest
import SwiftData
@testable import Climbing

/// SwiftData model tests. These run in Xcode / the iOS Simulator (SwiftData is
/// an Apple-platform framework) — they do not run in the Linux Cloud Agent.
/// Each test uses an in-memory `ModelContainer` so nothing touches disk.
@MainActor
final class ClimbingModelTests: XCTestCase {
    private func makeContext() throws -> ModelContext {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(
            for: ClimbingSession.self, ClimbLog.self, CustomGradeScale.self,
            configurations: config
        )
        return ModelContext(container)
    }

    func testNewSessionIsActiveWithZeroDuration() throws {
        let context = try makeContext()
        let start = Date(timeIntervalSince1970: 1_000)
        let session = ClimbingSession(startTime: start)
        context.insert(session)

        XCTAssertTrue(session.isActive)
        XCTAssertEqual(session.duration(asOf: start), 0, accuracy: 0.0001)
        XCTAssertEqual(
            session.duration(asOf: start.addingTimeInterval(90)), 90, accuracy: 0.0001
        )
    }

    func testEndingSessionFreezesDuration() throws {
        let context = try makeContext()
        let start = Date(timeIntervalSince1970: 1_000)
        let session = ClimbingSession(startTime: start)
        context.insert(session)

        session.endTime = start.addingTimeInterval(300)
        XCTAssertFalse(session.isActive)
        // Duration no longer advances past endTime.
        XCTAssertEqual(
            session.duration(asOf: start.addingTimeInterval(9_999)), 300, accuracy: 0.0001
        )
    }

    func testCompletionCountOnlyCountsSendsAndFlashes() throws {
        let context = try makeContext()
        let session = ClimbingSession()
        context.insert(session)

        for outcome in [ClimbOutcome.flash, .send, .project, .attempt] {
            let log = ClimbLog(gradeLabel: "V3", outcome: outcome, style: .crimp, session: session)
            context.insert(log)
        }
        try context.save()

        XCTAssertEqual(session.logs.count, 4)
        XCTAssertEqual(session.completionCount, 2)
    }

    func testDeletingSessionCascadesToLogs() throws {
        let context = try makeContext()
        let session = ClimbingSession()
        context.insert(session)
        context.insert(ClimbLog(gradeLabel: "V4", outcome: .send, style: .overhang, session: session))
        context.insert(ClimbLog(gradeLabel: "V2", outcome: .flash, style: .slab, session: session))
        try context.save()

        XCTAssertEqual(try context.fetch(FetchDescriptor<ClimbLog>()).count, 2)

        context.delete(session)
        try context.save()

        XCTAssertEqual(try context.fetch(FetchDescriptor<ClimbLog>()).count, 0)
    }

    func testAttemptsAreFlooredAtOne() throws {
        let context = try makeContext()
        let log = ClimbLog(gradeLabel: "V5", attempts: 0, outcome: .send, style: .pinch)
        context.insert(log)
        XCTAssertEqual(log.attempts, 1)

        log.setAttempts(-4)
        XCTAssertEqual(log.attempts, 1)

        log.setAttempts(7)
        XCTAssertEqual(log.attempts, 7)
    }

    func testOutcomeAndStyleEnumsPersist() throws {
        let context = try makeContext()
        let log = ClimbLog(gradeLabel: "V6", attempts: 3, outcome: .project, style: .dyno)
        context.insert(log)
        try context.save()

        let fetched = try XCTUnwrap(try context.fetch(FetchDescriptor<ClimbLog>()).first)
        XCTAssertEqual(fetched.outcome, .project)
        XCTAssertEqual(fetched.style, .dyno)
        XCTAssertEqual(fetched.gradeLabel, "V6")
        XCTAssertEqual(fetched.attempts, 3)
    }

    func testGradeScaleFromTemplateStoresOrderedGrades() throws {
        let context = try makeContext()
        let scale = CustomGradeScale(template: .standardVScale(), isDefault: true)
        context.insert(scale)
        try context.save()

        XCTAssertEqual(scale.kind, .boulderVScale)
        XCTAssertTrue(scale.isDefault)
        XCTAssertEqual(scale.grades.first, "VB")
        XCTAssertEqual(scale.index(of: "V0"), 1)
        XCTAssertEqual(scale.index(of: "V17"), 18)
        XCTAssertNil(scale.index(of: "5.12a"))
    }

    func testLogLinksToGradeScale() throws {
        let context = try makeContext()
        let scale = CustomGradeScale(template: .gymColorCircuit(), isDefault: true)
        context.insert(scale)
        let log = ClimbLog(
            gradeLabel: "Blue", outcome: .send, style: .jug, gradeScale: scale
        )
        context.insert(log)
        try context.save()

        XCTAssertEqual(log.gradeScale?.name, "Gym Circuit")
        XCTAssertEqual(scale.logs.count, 1)
    }
}

import XCTest
@testable import ClimbingDomain

final class GradeScaleTemplateTests: XCTestCase {
    func testStandardVScaleContents() {
        let scale = GradeScaleTemplate.standardVScale()
        XCTAssertEqual(scale.kind, .boulderVScale)
        XCTAssertEqual(scale.easiest, "VB")
        XCTAssertEqual(scale.hardest, "V17")
        // VB plus V0...V17 == 19 labels.
        XCTAssertEqual(scale.grades.count, 19)
        XCTAssertTrue(scale.grades.contains("V0"))
        XCTAssertTrue(scale.grades.contains("V10"))
    }

    func testIndexLookup() {
        let scale = GradeScaleTemplate.standardVScale()
        XCTAssertEqual(scale.index(of: "VB"), 0)
        XCTAssertEqual(scale.index(of: "V0"), 1)
        XCTAssertEqual(scale.index(of: "V5"), 6)
        XCTAssertNil(scale.index(of: "5.11a"))
    }

    func testHarderComparison() {
        let scale = GradeScaleTemplate.standardVScale()
        XCTAssertTrue(scale.isHarder("V5", than: "V2"))
        XCTAssertFalse(scale.isHarder("V2", than: "V5"))
        XCTAssertFalse(scale.isHarder("V3", than: "V3"))
    }

    func testUnknownGradeNeverOutranksKnown() {
        let scale = GradeScaleTemplate.standardVScale()
        // Unknown labels sort as easiest, so a known grade is always harder.
        XCTAssertTrue(scale.isHarder("V0", than: "purple"))
        XCTAssertFalse(scale.isHarder("purple", than: "V0"))
    }

    func testGymColorCircuitOrdering() {
        let scale = GradeScaleTemplate.gymColorCircuit()
        XCTAssertEqual(scale.kind, .gymColorCircuit)
        XCTAssertEqual(scale.easiest, "White")
        XCTAssertTrue(scale.isHarder("Black", than: "Green"))
    }

    func testCustomColorsRespectOrder() {
        let scale = GradeScaleTemplate.gymColorCircuit(colors: ["Pink", "Teal", "Gold"])
        XCTAssertEqual(scale.grades, ["Pink", "Teal", "Gold"])
        XCTAssertTrue(scale.isHarder("Gold", than: "Pink"))
    }

    func testTemplateIsCodable() throws {
        let original = GradeScaleTemplate.standardVScale()
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(GradeScaleTemplate.self, from: data)
        XCTAssertEqual(original, decoded)
    }
}

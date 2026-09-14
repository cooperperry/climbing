import Foundation
import SwiftData

/// A user-defined grading scale, such as the standard V-scale or a gym's color
/// circuit. Grades are stored ordered from easiest to hardest.
@Model
final class CustomGradeScale {
    /// Human-readable name, e.g. "V-Scale" or "Downtown Gym Circuit".
    var name: String

    /// Which family of scale this represents.
    var kind: GradeScaleKind

    /// Ordered grade labels, easiest first.
    var grades: [String]

    /// The scale used by default when logging new climbs.
    var isDefault: Bool

    var createdAt: Date

    /// Climbs recorded against this scale. Nullified (not deleted) if the scale
    /// is removed, so historical logs keep their label.
    @Relationship(inverse: \ClimbLog.gradeScale)
    var logs: [ClimbLog] = []

    init(
        name: String,
        kind: GradeScaleKind,
        grades: [String],
        isDefault: Bool = false,
        createdAt: Date = .now
    ) {
        self.name = name
        self.kind = kind
        self.grades = grades
        self.isDefault = isDefault
        self.createdAt = createdAt
    }

    /// Builds a persisted scale from a value-type template.
    convenience init(template: GradeScaleTemplate, isDefault: Bool = false) {
        self.init(
            name: template.name,
            kind: template.kind,
            grades: template.grades,
            isDefault: isDefault
        )
    }

    /// Difficulty index of a label within this scale, or `nil` if absent.
    func index(of grade: String) -> Int? {
        grades.firstIndex(of: grade)
    }
}

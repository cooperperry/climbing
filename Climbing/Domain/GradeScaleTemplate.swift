import Foundation

/// The family a grading scale belongs to.
public enum GradeScaleKind: String, CaseIterable, Codable, Identifiable, Sendable {
    /// The standard bouldering V-scale (Vermin).
    case boulderVScale
    /// Yosemite Decimal System, used for top rope and lead.
    case yds
    /// A gym's color-coded circuit (e.g. white → black).
    case gymColorCircuit
    /// A fully user-defined scale.
    case custom

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .boulderVScale: return "V-Scale"
        case .yds: return "YDS"
        case .gymColorCircuit: return "Gym Circuit"
        case .custom: return "Custom"
        }
    }
}

/// A value-type description of an ordered grading scale.
///
/// Used to seed and reason about persisted `CustomGradeScale` records. Grades
/// are stored from easiest (index 0) to hardest (last index), which lets us rank
/// and compare arbitrary labels — numeric V-grades or gym colors alike.
public struct GradeScaleTemplate: Equatable, Codable, Sendable {
    public let name: String
    public let kind: GradeScaleKind
    public private(set) var grades: [String]

    public init(name: String, kind: GradeScaleKind, grades: [String]) {
        self.name = name
        self.kind = kind
        self.grades = grades
    }

    /// Zero-based difficulty index of a label, or `nil` when it is not in scale.
    public func index(of grade: String) -> Int? {
        grades.firstIndex(of: grade)
    }

    /// Whether `lhs` is harder than `rhs`. Unknown labels are treated as easiest
    /// so they never outrank a known grade.
    public func isHarder(_ lhs: String, than rhs: String) -> Bool {
        let left = index(of: lhs) ?? -1
        let right = index(of: rhs) ?? -1
        return left > right
    }

    public var easiest: String? { grades.first }
    public var hardest: String? { grades.last }

    /// The standard bouldering V-scale: VB, then V0 through V17.
    public static func standardVScale() -> GradeScaleTemplate {
        var grades = ["VB"]
        grades.append(contentsOf: (0...17).map { "V\($0)" })
        return GradeScaleTemplate(name: "V-Scale", kind: .boulderVScale, grades: grades)
    }

    /// Common gym YDS: 5.5–5.9, then 5.10a–5.13d.
    public static func standardYDS() -> GradeScaleTemplate {
        var grades = ["5.5", "5.6", "5.7", "5.8", "5.9"]
        for number in 10...13 {
            for letter in ["a", "b", "c", "d"] {
                grades.append("5.\(number)\(letter)")
            }
        }
        return GradeScaleTemplate(name: "YDS", kind: .yds, grades: grades)
    }

    /// A gym color circuit ordered from easiest to hardest.
    public static func gymColorCircuit(
        colors: [String] = ["White", "Yellow", "Green", "Blue", "Red", "Black", "Purple"]
    ) -> GradeScaleTemplate {
        GradeScaleTemplate(name: "Gym Circuit", kind: .gymColorCircuit, grades: colors)
    }
}

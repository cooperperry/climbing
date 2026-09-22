import Foundation
import SwiftData

/// A problem on the current set for one wall. The photo + these pins are the
/// live map; a set reset deletes them. ClimbLog keeps wall name and grade.
@Model
final class GymRoute {
    var id: UUID
    var grade: String
    var colorName: String
    var x: Double
    var y: Double
    var disciplineRaw: String
    var createdAt: Date
    /// Display name of the climber who last set this route. Optional so older pins migrate.
    var updatedBy: String?
    var updatedAt: Date?
    /// Shared key for routes spaced together (e.g. a circle cluster). Nil = ungrouped.
    var groupKey: String?
    var wall: GymArea?

    var holdColor: HoldColor { HoldColor(rawValue: colorName) ?? .blue }
    var discipline: ClimbDiscipline { ClimbDiscipline(rawValue: disciplineRaw) ?? .boulder }
    var label: String { "\(holdColor.displayName) \(grade)" }

    init(
        id: UUID = UUID(),
        grade: String,
        colorName: String,
        x: Double,
        y: Double,
        discipline: ClimbDiscipline = .boulder,
        wall: GymArea? = nil,
        createdAt: Date = .now,
        updatedBy: String? = nil,
        updatedAt: Date? = nil,
        groupKey: String? = nil
    ) {
        self.id = id
        self.grade = grade
        self.colorName = colorName
        let clamped = GymJoinMath.clampPin(x: x, y: y)
        self.x = clamped.x
        self.y = clamped.y
        self.disciplineRaw = discipline.rawValue
        self.wall = wall
        self.createdAt = createdAt
        self.updatedBy = updatedBy
        self.updatedAt = updatedAt ?? createdAt
        self.groupKey = groupKey
    }

    func setPin(x: Double, y: Double) {
        let clamped = GymJoinMath.clampPin(x: x, y: y)
        self.x = clamped.x
        self.y = clamped.y
    }
}

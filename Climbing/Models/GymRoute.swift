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
        createdAt: Date = .now
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
    }
}

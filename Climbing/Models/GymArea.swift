import Foundation
import SwiftData

/// A named wall / sector on a gym map, stored as a 0...1 pin.
@Model
final class GymArea {
    var id: UUID
    var name: String
    var x: Double
    var y: Double
    var gym: ClimbGym?

    init(
        id: UUID = UUID(),
        name: String,
        x: Double,
        y: Double,
        gym: ClimbGym? = nil
    ) {
        self.id = id
        self.name = name
        let clamped = GymJoinMath.clampPin(x: x, y: y)
        self.x = clamped.x
        self.y = clamped.y
        self.gym = gym
    }
}

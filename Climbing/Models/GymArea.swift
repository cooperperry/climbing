import Foundation
import SwiftData

/// A named wall at a gym. The gym map is these walls — usually a photo you
/// took standing in front of it, not a floor plan.
@Model
final class GymArea {
    var id: UUID
    var name: String
    var x: Double
    var y: Double
    var gym: ClimbGym?

    /// Photo of this wall. Optional so older pins migrate, and so a wall can
    /// be named before anyone snaps it.
    var photoData: Data?

    init(
        id: UUID = UUID(),
        name: String,
        x: Double,
        y: Double,
        gym: ClimbGym? = nil,
        photoData: Data? = nil
    ) {
        self.id = id
        self.name = name
        let clamped = GymJoinMath.clampPin(x: x, y: y)
        self.x = clamped.x
        self.y = clamped.y
        self.gym = gym
        self.photoData = photoData
    }
}

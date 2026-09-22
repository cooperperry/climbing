import Foundation
import SwiftData

/// A climbing gym the user has joined on this phone. Map image and areas are
/// local today; a join code is ready for sharing when sync exists.
@Model
final class ClimbGym {
    var id: UUID
    var name: String
    var joinCode: String
    var joinedAt: Date
    /// One gym is "I'm here" for new sends.
    var isCurrent: Bool
    var mapImageData: Data?
    /// Wall you're on right now. Optional so gyms from before walls existed migrate.
    var currentWallName: String?
    /// Opacity of the chalkboard / floor-plan underlay photo (0...1).
    var underlayOpacity: Double = 0.4
    /// Which floor is shown on the map editor.
    var currentFloorName: String?
    /// Display names of floors whose walls are locked. Routes on a locked floor can still change.
    var lockedFloors: String = ""

    @Relationship(deleteRule: .cascade, inverse: \GymArea.gym)
    var areas: [GymArea] = []

    @Relationship(deleteRule: .nullify, inverse: \ClimbLog.gym)
    var logs: [ClimbLog] = []

    init(
        id: UUID = UUID(),
        name: String,
        joinCode: String = GymJoinMath.joinCode(),
        joinedAt: Date = .now,
        isCurrent: Bool = false,
        mapImageData: Data? = nil,
        underlayOpacity: Double = 0.4,
        currentFloorName: String? = "Main"
    ) {
        self.id = id
        self.name = name
        self.joinCode = joinCode
        self.joinedAt = joinedAt
        self.isCurrent = isCurrent
        self.mapImageData = mapImageData
        self.currentWallName = nil
        self.underlayOpacity = underlayOpacity
        self.currentFloorName = currentFloorName
    }
}

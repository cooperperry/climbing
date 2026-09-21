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
        mapImageData: Data? = nil
    ) {
        self.id = id
        self.name = name
        self.joinCode = joinCode
        self.joinedAt = joinedAt
        self.isCurrent = isCurrent
        self.mapImageData = mapImageData
    }
}

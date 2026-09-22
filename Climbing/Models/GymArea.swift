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

    /// Polyline for this wall on the overhead floor plan (JSON `[PlanPoint]`).
    /// When nil, the map uses a short default segment at `(x, y)`.
    var shapePointsData: Data?

    /// When true, the polyline is drawn closed (square / polygon). Older walls default open.
    var shapeClosed: Bool = false

    /// Zone grouping on the overhead map (Cave, 360, Center…). Empty = General.
    var zoneName: String = ""

    /// Floor / level name. Empty = Main.
    var floorName: String = ""

    /// Today's problems on this photo. Cleared on a set reset; send logs stay.
    @Relationship(deleteRule: .cascade, inverse: \GymRoute.wall)
    var routes: [GymRoute] = []

    init(
        id: UUID = UUID(),
        name: String,
        x: Double,
        y: Double,
        gym: ClimbGym? = nil,
        photoData: Data? = nil,
        shapePointsData: Data? = nil,
        shapeClosed: Bool = false,
        zoneName: String = "",
        floorName: String = ""
    ) {
        self.id = id
        self.name = name
        let clamped = GymJoinMath.clampBoard(x: x, y: y)
        self.x = clamped.x
        self.y = clamped.y
        self.gym = gym
        self.photoData = photoData
        self.shapePointsData = shapePointsData
        self.shapeClosed = shapeClosed
        self.zoneName = zoneName
        self.floorName = floorName
    }

    var displayZone: String { FloorPlanMath.defaultZoneName(zoneName) }
    var displayFloor: String { FloorPlanMath.defaultFloorName(floorName) }

    var shapePoints: [PlanPoint] {
        get { FloorPlanMath.decode(shapePointsData) }
        set {
            shapePointsData = FloorPlanMath.encode(newValue)
            let center = FloorPlanMath.centroid(of: newValue)
            x = center.x
            y = center.y
        }
    }

    /// Points drawn on the floor plan, including a generated segment for older walls.
    func floorPlanPoints() -> [PlanPoint] {
        let stored = shapePoints
        if stored.isEmpty {
            return FloorPlanMath.defaultSegment(anchor: PlanPoint(x: x, y: y))
        }
        return stored
    }

    func setFloorPlanPoints(_ points: [PlanPoint]) {
        shapePoints = points
    }
}

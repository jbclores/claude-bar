import Foundation

/// A floor as the simulation sees it (world.types.ts FloorData): its id, whether it is Robin's own office, its frame
/// for distances, and its spots in the browser's order (BuiltRoom.spots).
public struct SimFloor: Sendable {
    public var id: Int
    /// floors.ts isOwnOffice.
    public var ownOffice: Bool
    public var frame: FloorFrame
    public var spots: [RoomSpot]

    public init(id: Int, ownOffice: Bool, frame: FloorFrame, spots: [RoomSpot]) {
        self.id = id; self.ownOffice = ownOffice; self.frame = frame; self.spots = spots
    }

    /// Every floor with a built room, in the building's order. (Cat Office would also walk a painted floor's own spots;
    /// ClaudeBar builds every floor it shows, so a floor without a room has none here.)
    public static func floors(building: Building, catalogue: RoomCatalogue) -> [SimFloor] {
        building.floors.compactMap { f in
            RoomGeometry.build(floor: f, catalogue: catalogue).map { SimFloor(id: f.id, ownOffice: f.isOwnOffice, frame: $0.frame, spots: $0.spots) }
        }
    }

    /// floor-math.ts pxDistance: on-screen distance between two floor points, in world px.
    public func pxDistance(_ a: FloorPoint, _ b: FloorPoint) -> Double {
        let pa = frame.px(a), pb = frame.px(b)
        return hypot(pb.x - pa.x, pb.y - pa.y)
    }
}

/// decision-engine.ts: utility-based activity choice.
public enum SimChoice {
    /// decision-engine.ts Choice.
    public struct Choice: Sendable {
        public var floorId: Int
        public var spot: RoomSpot
        public var activity: SimActivity
    }

    /// decision-engine.ts urgency 31-34.
    static func urgency(_ level: Double) -> Double {
        let x = min(1, max(0, (80 - level) / 80))
        return pow(x, 1.5)
    }

    /// decision-engine.ts needScore 36-43.
    static func needScore(_ def: SimActivity, _ needs: SimNeeds) -> Double {
        var score = 0.0
        for key in SimNeedKey.allCases {
            let gain = def.gains[key] ?? 0
            if gain > 0 { score += (gain / 100) * urgency(needs[key]) * 2.2 }
        }
        return score
    }

    /// decision-engine.ts chooseActivity 50-94: score every usable spot by how much it relieves the cat's needs (or by
    /// work drive for desks), subtract travel cost, add a little noise (one draw per candidate, in floor and spot
    /// order), then sample among the top three (one more draw). nil when no spot passes the filters.
    /// `isFree`, `canReach` and `only` are DecisionContext's; `only` nil accepts every spot.
    public static func choose(floors: [SimFloor], floorId: Int, position: FloorPoint, needs: SimNeeds, minutesSinceWork: Double,
                              lastSpotId: String?, ownDeskId: String?, rng: inout SimRng,
                              isFree: (RoomSpot) -> Bool, canReach: (Int, RoomSpot) -> Bool,
                              only: ((SimFloor, RoomSpot) -> Bool)? = nil) -> Choice? {
        var scored: [(choice: Choice, score: Double)] = []
        let hasOwnDesk = ownDeskId != nil

        for floor in floors {
            let otherFloor = floor.id != floorId
            for spot in floor.spots {
                if spot.kind == "elevator" { continue }
                guard let def = SimActivities.activity(for: spot) else { continue }
                if spot.kind == "desk" {
                    // Without a desk of its own a cat hot-desks on Robin's office floors (not a project's).
                    if hasOwnDesk ? spot.id != ownDeskId : !floor.ownOffice { continue }
                }
                if let only, !only(floor, spot) { continue }
                if !isFree(spot) || !canReach(floor.id, spot) { continue }

                var score: Double
                if spot.kind == "desk" {
                    // Right after a work block a break is likely; the pull back to the desk grows over ~50 minutes.
                    score = 0.1 + 0.9 * min(1, minutesSinceWork / 50)
                } else {
                    score = 0.12 + needScore(def, needs)
                    if spot.id == lastSpotId { score -= 0.25 }
                }
                if otherFloor {
                    score -= 0.08 * Double(abs(floor.id - floorId))
                } else {
                    score -= 0.04 * (floor.pxDistance(position, spot.standAt) / 2000)
                }
                score += rng.range(0, 0.15)
                scored.append((Choice(floorId: floor.id, spot: spot, activity: def), score))
            }
        }

        if scored.isEmpty { return nil }
        // Array.prototype.sort is stable: equal scores keep their order.
        let sorted = scored.enumerated().sorted { a, b in
            a.element.score != b.element.score ? a.element.score > b.element.score : a.offset < b.offset
        }.map(\.element)
        let top = Array(sorted.prefix(3))
        let weights = top.map { pow(max($0.score, 0.01), 3) }
        let total = weights.reduce(0, +)
        var r = rng.range(0, total)
        for i in top.indices {
            r -= weights[i]
            if r <= 0 { return top[i].choice }
        }
        return top[0].choice
    }
}

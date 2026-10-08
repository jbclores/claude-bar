import Foundation

/// A floor's spots as Cat Office's simulation walks them (`buildRoomOffice(...).building.floors[].spots`), in its order.
enum WalkSpots {
    /// room.ts spotOwner: the piece a spot belongs to.
    static func spotOwner(_ spotId: String) -> String {
        String(spotId.split(separator: ":", omittingEmptySubsequences: false).first ?? "")
    }

    /// room.ts BIN_GROUP: props of this group are trash bins.
    static let binGroup = "trash-bin"

    /// room.ts spotPoints: every floor point cats stand on at a spot.
    static func spotPoints(_ s: RoomSpot) -> [FloorPoint] { [s.standAt] + s.slots }

    /// room.ts onFurniture: a spot up on its prop.
    static func onFurniture(_ s: RoomSpot) -> Bool { s.lift > 0 }

    /// The grid size Cat Office walks (floor.grid.size): nil unless a whole number in 1...512 (as Building.parse's gate).
    static func gridCells(_ gridSize: Double) -> Int? {
        gridSize >= 1 && gridSize <= 512 && gridSize == gridSize.rounded() ? Int(gridSize) : nil
    }

    /// room.ts buildRoomFloor 964-1003 (spots and the optional-spot filter), desks.ts resolveOffice 192 (desk spots
    /// after them) and room.ts closeSpots 1035-1079. `props` in buildRoomFloor's order (PropPlacer.placeInOrder).
    static func spots(room: FloorRoom, frame: FloorFrame, catalogue: RoomCatalogue, gridSize: Double,
                      inOrder props: [PropPlacer.Placed], desks: [PlacedDesk]) -> [RoomSpot] {
        let placed = props.map(\.prop)
        // room.ts 967-974: the elevators' spots.
        var spots = room.wallItems.compactMap { WallItems.elevatorSpot($0, frame: frame, catalogue: catalogue) }.map {
            RoomSpot(id: $0.id, kind: "elevator", pose: nil, standAt: $0.standAt, facing: $0.facing, lift: 0, owner: $0.id)
        }
        // room.ts 976-984: the rugs' spots, noting the optional ones.
        var optional = Set<String>()
        for rug in PropPlacer.roomRugs(frame, room, catalogue, grid: gridSize) {
            guard let def = catalogue.rugs[rug.rug], let defs = def.spots else { continue }
            let list = PropPlacer.rugSpots(def, rug)
            for (i, d) in defs.enumerated() where d.optional == true { optional.insert(list[i].id) }
            spots += list
        }
        // room.ts 985-986: the props' spots.
        for p in placed { spots += p.spots }
        // room.ts 1001-1003: the props' optional spots; optional spots on closed floor (the wall band, another prop) close now.
        for p in placed {
            for (i, d) in (catalogue.props[p.prop]?.spots ?? []).enumerated() where d.optional == true {
                optional.insert(i == 0 ? p.id : "\(p.id):\(d.id ?? "undefined")")
            }
        }
        let n = gridCells(gridSize)
        let open = n.map { NavGrid.roomCells(size: $0, props: placed, spots: spots) }
        if let n, let open {
            spots = spots.filter { !optional.contains($0.id) || onFurniture($0) || open[NavGrid.cellIndex($0.standAt, size: n)] }
        }
        // desks.ts resolveOffice 192: the desks' work spots after the room's.
        spots += desks.map {
            RoomSpot(id: $0.id, kind: "desk", pose: $0.rear ? "stand" : "type", standAt: $0.standAt, facing: $0.facing, lift: 0, owner: $0.id,
                     label: catalogue.desks[$0.design]?.label ?? "", capacity: 1)
        }
        return closeSpots(spots, props: placed, catalogue: catalogue, desks: desks, optional: optional, gridSize: gridSize,
                          nav: n.flatMap { n in open.map { NavGrid(size: n, open: NavGrid.carved($0, desks: desks, size: n), frame: frame) } })
    }

    /// room.ts closeSpots 1035-1079: the walked floor's spots without the optional ones a prop or desk covers or the cats
    /// can't reach from the elevator; a spot standing on a trash bin moves to the nearest free cell beside it, or closes.
    /// `nav` is the walked floor's grid (nil without a grid size: no reach checks, as without an elevator).
    static func closeSpots(_ floorSpots: [RoomSpot], props: [PlacedProp], catalogue: RoomCatalogue, desks: [PlacedDesk],
                           optional: Set<String>, gridSize: Double, nav: NavGrid?) -> [RoomSpot] {
        let bins = props.filter { catalogue.props[$0.prop]?.group == binGroup && !$0.tableBit }
        if optional.isEmpty && bins.isEmpty { return floorSpots }
        let pieces = props.filter { !$0.tableBit }.map { (id: $0.id, fp: $0.footprint) } + desks.map { (id: $0.id, fp: $0.footprint) }
        let covered = { (s: RoomSpot) in pieces.contains { $0.id != spotOwner(s.id) && NavGrid.contains($0.fp, s.standAt) } }
        let underBin = { (s: RoomSpot) in
            !onFurniture(s) && bins.contains { b in b.id != spotOwner(s.id) && spotPoints(s).contains { NavGrid.contains(b.footprint, $0) } }
        }
        let elevator = floorSpots.first { $0.kind == "elevator" }
        let nav = elevator != nil ? nav : nil
        let home = nav.flatMap { nav in elevator.map { nav.regionOf($0.standAt) } } ?? 0
        let closed = { (s: RoomSpot) in
            optional.contains(s.id) && (covered(s) || (nav.map { home == 0 || $0.regionOf(s.standAt) != home } ?? false))
        }
        let step = 1 / gridSize
        let free = { (at: FloorPoint) -> Bool in
            at.u > 0 && at.u < 1 && at.v > 0 && at.v < 1 && !pieces.contains { NavGrid.contains($0.fp, at) }
                && (nav.map { $0.isOpenAt(at) && (home == 0 || $0.regionOf(at) == home) } ?? true)
        }
        // The neighbouring cell (sides before corners) that is free for the whole spot, or nil.
        let shifted = { (s: RoomSpot) -> RoomSpot? in
            for (du, dv) in [(1.0, 0.0), (-1, 0), (0, 1), (0, -1), (1, 1), (1, -1), (-1, 1), (-1, -1)] {
                let move = { (q: FloorPoint) in FloorPoint(u: q.u + du * step, v: q.v + dv * step) }
                if !spotPoints(s).allSatisfy({ free(move($0)) }) { continue }
                var out = s
                out.standAt = move(s.standAt)
                out.slots = s.slots.map(move)
                return out
            }
            return nil
        }
        var spots: [RoomSpot] = []
        for s in floorSpots {
            if underBin(s) {
                if let moved = shifted(s) { spots.append(moved) }
            } else if !closed(s) {
                spots.append(s)
            }
        }
        return spots
    }
}

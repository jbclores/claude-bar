import CoreGraphics
import Foundation

/// A place a cat goes to on a prop or a rug (Cat Office's Spot, without its label, capacity and slots).
public struct RoomSpot: Equatable, Sendable {
    public var id: String
    public var kind: String
    public var pose: String?
    public var standAt: FloorPoint
    public var facing: String
    /// World px the cat sits above its floor point (0 on the floor).
    public var lift: Double
    /// The prop placement or rug the spot belongs to.
    public var owner: String
}

/// A prop standing on a floor (room.ts PlacedProp).
public struct PlacedProp: Equatable, Sendable {
    public var id: String
    public var prop: String
    /// The picture drawn; nil for a placeholder box.
    public var image: String?
    public var mirrored: Bool
    public var footprint: Footprint
    /// Sprite (or placeholder) box on screen, world px.
    public var rect: CGRect
    public var box: OccluderBox
    public var spots: [RoomSpot]
    /// A companion part: the placement id of the prop it comes with.
    public var companionOf: String?
    public var cover: [WorldPoint]?
}

/// A rug as drawn (RoomShell.tsx Rug): its box in floor-plane px (FloorFrame.plane).
public struct PlacedRug: Equatable, Sendable {
    public var id: String
    public var rug: String
    public var image: String?
    public var rect: CGRect
    /// Its art drawn a quarter turn round.
    public var turned: Bool
}

/// Ports room.ts's props, companions, tables, spots, rugs and depth settling.
public enum PropPlacer {
    static let touchEps = 1e-4
    static let placeholderHeightShare = 0.6
    static let tableTopSteps = 8.0
    static let rowZGap = 12
    static let aheadZGap = 10
    static let companionSep = "~"

    // MARK: room.ts 1096-1101

    static func overlapsFp(_ a: Footprint, _ b: Footprint) -> Bool {
        min(a.u1, b.u1) - max(a.u0, b.u0) > touchEps && min(a.v1, b.v1) - max(a.v0, b.v0) > touchEps
    }

    static func within(_ a: Footprint, _ r: Footprint) -> Bool {
        a.u0 >= r.u0 - touchEps && a.u1 <= r.u1 + touchEps && a.v0 >= r.v0 - touchEps && a.v1 <= r.v1 + touchEps
    }

    /// JS Math.round: half up.
    static func jsRound(_ x: Double) -> Double { (x + 0.5).rounded(.down) }

    // MARK: wall seats, room.ts 368-397

    struct WallSeat { var item: WallItemPlacement; var recess: Footprint }

    static func wallItemRecess(_ frame: FloorFrame, _ item: WallItemPlacement, _ def: WallItemDef) -> Footprint? {
        guard let seat = def.seat, seat.count >= 2, let seatDepth = def.seatDepth, seatDepth != 0 else { return nil }
        let a = WallItems.at(item, def, frame: frame, x: seat[0])
        let b = WallItems.at(item, def, frame: frame, x: seat[1])
        let depth = seatDepth * frame.outUnit(item.wall)
        let lo = min(a, b), hi = max(a, b)
        return item.wall == .left ? Footprint(u0: lo, u1: hi, v0: -depth, v1: 0) : Footprint(u0: -depth, u1: 0, v0: lo, v1: hi)
    }

    static func wallSeats(_ frame: FloorFrame, _ items: [WallItemPlacement], _ catalogue: RoomCatalogue) -> [WallSeat] {
        items.compactMap { item in
            guard let def = catalogue.wallItems[item.item], let recess = wallItemRecess(frame, item, def) else { return nil }
            return WallSeat(item: item, recess: recess)
        }
    }

    static func seatUnder(_ fp: Footprint, _ seats: [WallSeat]) -> WallSeat? {
        seats.first { overlapsFp(fp, $0.recess) }
    }

    // MARK: room.ts 457-493

    static func panelRange(_ def: PropDef) -> (min: Int, max: Int)? {
        guard let sizes = def.panels?.sizes, let first = sizes.first, let last = sizes.last else { return nil }
        return (first.panels, last.panels)
    }

    static func propPanels(_ def: PropDef, _ panels: Int? = nil) -> Int? {
        guard let p = def.panels, let range = panelRange(def) else { return nil }
        let n = panels ?? p.default
        return min(range.max, max(range.min, n))
    }

    static func propSize(_ frame: FloorFrame, _ def: PropDef, facing: Int, panels: Int? = nil, grid: Double) -> (du: Double, dv: Double) {
        if let cells = def.cells, cells != 0 {
            let side = Double(cells) / grid
            return (side, side)
        }
        let turned = facing % 2 == 1
        let count = propPanels(def, panels)
        var depth = def.depth
        if let p = def.panels, let count { depth = def.depth + Double(count - p.default) * p.step }
        return ((turned ? def.length : depth) / frame.eu, (turned ? depth : def.length) / frame.ev)
    }

    static func propFootprint(_ frame: FloorFrame, _ def: PropDef, u: Double, v: Double, facing: Int, panels: Int? = nil, grid: Double) -> Footprint {
        let s = propSize(frame, def, facing: facing, panels: panels, grid: grid)
        return Footprint(u0: u - s.du, u1: u, v0: v - s.dv, v1: v)
    }

    // MARK: room.ts 512-556

    static func companionParts(_ frame: FloorFrame, _ def: PropDef, _ placement: PropPlacement, _ catalogue: RoomCatalogue, grid: Double)
        -> (props: [PropPlacement], rugs: [RugPlacement]) {
        var props: [PropPlacement] = [], rugs: [RugPlacement] = []
        guard let companions = def.companions, !companions.isEmpty else { return (props, rugs) }
        let eu = frame.eu, ev = frame.ev
        let u = placement.u, v = placement.v, facing = placement.facing
        let mirrored = facing % 2 == 1
        let fp = propFootprint(frame, def, u: u, v: v, facing: facing, grid: grid)
        for (i, c) in companions.enumerated() {
            if placement.companionsOff?.contains(i) == true { continue }
            var mid = mirrored ? FloorPoint(u: u - c.at.dv / eu, v: v - c.at.du / ev) : FloorPoint(u: u - c.at.du / eu, v: v - c.at.dv / ev)
            if facing >= 2 { mid = FloorPoint(u: fp.u0 + fp.u1 - mid.u, v: fp.v0 + fp.v1 - mid.v) }
            let id = "\(placement.id)\(companionSep)\(i)"
            if let name = c.prop, let prop = catalogue.props[name] {
                let facings = propFacings(prop)
                let f = facings.contains(facing) ? facing : facings.contains(facing % 2) ? facing % 2 : 0
                let size = propSize(frame, prop, facing: f, grid: grid)
                props.append(PropPlacement(id: id, prop: prop.id, u: mid.u + size.du / 2, v: mid.v + size.dv / 2, facing: f,
                                           decor: nil, panels: nil, companionsOff: nil))
            }
            if let name = c.rug, let rug = catalogue.rugs[name], let size = rug.size, size.count >= 2 {
                let turned = mirrored && rug.shape == "rect"
                let (along, across) = turned ? (size[1], size[0]) : (size[0], size[1])
                rugs.append(RugPlacement(id: id, rug: rug.id, u: mid.u, v: mid.v, w: along / ev, d: across / eu, turned: turned ? true : nil))
            }
        }
        return (props, rugs)
    }

    /// room.ts roomRugs: the room's own rugs, then those that come with its props.
    static func roomRugs(_ frame: FloorFrame, _ room: FloorRoom, _ catalogue: RoomCatalogue, grid: Double) -> [RugPlacement] {
        let extra = room.props.flatMap { p -> [RugPlacement] in
            guard let def = catalogue.props[p.prop] else { return [] }
            return companionParts(frame, def, p, catalogue, grid: grid).rugs
        }
        return room.rugs + extra
    }

    // MARK: room.ts 561-606

    static func isTableBit(_ def: PropDef) -> Bool { def.placeOn == "table" }

    struct TableTop { var id: String; var footprint: Footprint; var inset: Footprint; var height: Double }

    static func shrunk(_ fp: Footprint, _ share: Double) -> Footprint {
        let du = (fp.u1 - fp.u0) * share, dv = (fp.v1 - fp.v0) * share
        return Footprint(u0: fp.u0 + du, u1: fp.u1 - du, v0: fp.v0 + dv, v1: fp.v1 - dv)
    }

    static func tableTops(_ frame: FloorFrame, _ props: [PropPlacement], _ catalogue: RoomCatalogue, grid: Double) -> [TableTop] {
        props.compactMap { p in
            guard let def = catalogue.props[p.prop], let top = def.top else { return nil }
            let fp = propFootprint(frame, def, u: p.u, v: p.v, facing: p.facing, grid: grid)
            return TableTop(id: p.id, footprint: fp, inset: shrunk(fp, top.inset), height: top.height)
        }
    }

    static func tableUnder(_ fp: Footprint, _ tables: [TableTop]) -> TableTop? {
        tables.first { within(fp, $0.inset) }
    }

    static func artAnchor(_ frame: FloorFrame, _ def: PropDef, _ placement: PropPlacement, grid: Double) -> FloorPoint {
        let u = placement.u, v = placement.v
        guard let cells = def.cells, cells != 0 else { return FloorPoint(u: u, v: v) }
        let c = propSize(frame, def, facing: placement.facing, grid: grid)
        var shape = def
        shape.cells = nil
        shape.panels = nil
        let drawn = propSize(frame, shape, facing: placement.facing, grid: grid)
        return FloorPoint(u: u - (c.du - drawn.du) / 2, v: v - (c.dv - drawn.dv) / 2)
    }

    // MARK: room.ts 609-673

    static let mirroredFacing = ["back-right": "back-left", "back-left": "back-right", "front-left": "front-right", "front-right": "front-left"]
    static let turnedFacing = ["back-right": "front-left", "front-left": "back-right", "back-left": "front-right", "front-right": "back-left"]

    static func propSpotId(_ placement: PropPlacement, _ index: Int, _ spotId: String?) -> String {
        index == 0 ? placement.id : "\(placement.id):\(spotId ?? "undefined")"
    }

    static func propSpots(_ frame: FloorFrame, _ def: PropDef, _ placement: PropPlacement, _ fp: Footprint, drop: Double, grid: Double) -> [RoomSpot] {
        let anchor = frame.px(artAnchor(frame, def, placement, grid: grid))
        let mirrored = placement.facing % 2 == 1
        let turned = placement.facing >= 2
        return (def.spots ?? []).enumerated().map { i, s in
            let lift = s.lift ?? 0
            var at = frame.uv(WorldPoint(x: anchor.x + (mirrored ? -s.stand.dx : s.stand.dx), y: anchor.y + s.stand.dy + lift))
            var facing = mirrored ? (mirroredFacing[s.facing] ?? s.facing) : s.facing
            if turned {
                at = FloorPoint(u: fp.u0 + fp.u1 - at.u, v: fp.v0 + fp.v1 - at.v)
                facing = turnedFacing[facing] ?? facing
            }
            return RoomSpot(id: propSpotId(placement, i, s.id), kind: s.kind, pose: s.pose, standAt: at, facing: facing,
                            lift: lift - drop > 0 ? lift - drop : 0, owner: placement.id)
        }
    }

    // MARK: room.ts 682-700

    static func rugSpots(_ def: RugDef, _ rug: RugPlacement) -> [RoomSpot] {
        (def.spots ?? []).enumerated().map { i, s in
            let standAt = rug.turned == true
                ? FloorPoint(u: rug.u + s.at.v * rug.d, v: rug.v - s.at.u * rug.w)
                : FloorPoint(u: rug.u + s.at.u * rug.d, v: rug.v + s.at.v * rug.w)
            return RoomSpot(id: i == 0 ? rug.id : "\(rug.id):\(s.id ?? "undefined")", kind: s.kind, pose: s.pose,
                            standAt: standAt, facing: s.facing, lift: 0, owner: rug.id)
        }
    }

    static func footprintCorners(_ frame: FloorFrame, _ fp: Footprint) -> [WorldPoint] {
        [frame.px(FloorPoint(u: fp.u0, v: fp.v0)), frame.px(FloorPoint(u: fp.u1, v: fp.v0)),
         frame.px(FloorPoint(u: fp.u1, v: fp.v1)), frame.px(FloorPoint(u: fp.u0, v: fp.v1))]
    }

    // MARK: room.ts 703-766

    /// A prop as placed, with what the settling passes need to know about it.
    struct Placed {
        var prop: PlacedProp
        var hasPanels: Bool
        var onTable: Bool
        var tableBit: Bool
    }

    static func placeProp(_ frame: FloorFrame, _ def: PropDef, _ placement: PropPlacement, lowered: Bool = false,
                          table: TableTop? = nil, grid: Double) -> Placed {
        let u = placement.u, v = placement.v, facing = placement.facing
        let up = table?.height ?? 0
        let drop = lowered ? (def.raised ?? 0) : table != nil ? -up : 0
        let footprint = propFootprint(frame, def, u: u, v: v, facing: facing, panels: placement.panels, grid: grid)
        let turned = facing >= 2
        let count = propPanels(def, placement.panels)
        let own = count.flatMap { n in def.panels?.sizes?.first { $0.panels == n } }
        let sprite: PropSprite?
        if turned { sprite = def.rear }
        else if let own { sprite = PropSprite(image: own.image, width: own.width, height: own.height, anchor: own.anchor) }
        else if let image = def.image {
            sprite = PropSprite(image: image, width: def.width ?? 0, height: def.height ?? 0, anchor: def.anchor ?? WorldPoint(x: 0, y: 0))
        } else { sprite = nil }
        let mirrored = facing % 2 == 1
        let rect: CGRect
        if let sprite {
            let a = frame.px(artAnchor(frame, def, placement, grid: grid))
            let left = mirrored ? a.x - (sprite.width - sprite.anchor.x) : a.x - sprite.anchor.x
            let top = a.y - sprite.anchor.y + drop
            rect = CGRect(x: left, y: top, width: sprite.width, height: sprite.height)
        } else {
            let pts = footprintCorners(frame, footprint)
            let left = pts.map(\.x).min()!, right = pts.map(\.x).max()!
            let top = pts.map(\.y).min()!, bottom = pts.map(\.y).max()!
            let t = top - (def.height ?? 0) * placeholderHeightShare - up
            rect = CGRect(x: left, y: t, width: right - left, height: bottom - up - t)
        }
        var box = OccluderBox.make(front: FloorPoint(u: u, v: v), rect: rect, back: footprint.u0 + footprint.v0, id: placement.id)
        if let table {
            let t = table.footprint
            let span = t.u1 + t.v1 - (t.u0 + t.v0)
            let share = span > 0 ? min(1, max(0, (u + v - (t.u0 + t.v0)) / span)) : 1
            box.z = FloorFrame.depthZ(t.u1 + t.v1) + 1 + Int(jsRound(share * tableTopSteps))
        }
        let prop = PlacedProp(
            id: placement.id, prop: placement.prop, image: sprite?.image, mirrored: mirrored, footprint: footprint, rect: rect, box: box,
            spots: placement.decor == true ? [] : propSpots(frame, def, placement, footprint, drop: drop, grid: grid),
            companionOf: nil, cover: def.cover)
        return Placed(prop: prop, hasPanels: def.panels != nil, onTable: table != nil, tableBit: isTableBit(def))
    }

    static func propFacings(_ def: PropDef) -> [Int] {
        var facings = def.mirror == true ? [0, 1] : [0]
        if def.rear != nil { facings += def.mirror == true ? [2, 3] : [2] }
        return facings
    }

    // MARK: room.ts 789-856

    static func rectsOverlap(_ a: CGRect, _ b: CGRect) -> Bool {
        a.minX < b.maxX && b.minX < a.maxX && a.minY < b.maxY && b.minY < a.maxY
    }

    static func settlePanelRows(_ props: [Placed], _ desks: [PlacedDesk]) -> [Placed] {
        guard props.contains(where: \.hasPanels) else { return props }
        let pieces = props.map { (id: $0.prop.id, fp: $0.prop.footprint, rect: $0.prop.rect, z: $0.prop.box.z) }
            + desks.map { (id: $0.id, fp: $0.footprint, rect: $0.rect, z: $0.box.z) }
        return props.map { p in
            guard p.hasPanels, !p.onTable else { return p }
            let fp = p.prop.footprint
            var lo = -Double.infinity, hi = Double.infinity
            for q in pieces {
                if q.id == p.prop.id || !rectsOverlap(q.rect, p.prop.rect) { continue }
                let front = q.fp.u0 >= fp.u1 - touchEps || q.fp.v0 >= fp.v1 - touchEps
                let behind = q.fp.u1 <= fp.u0 + touchEps || q.fp.v1 <= fp.v0 + touchEps
                if front && !behind { hi = min(hi, Double(q.z)) }
                else if behind && !front { lo = max(lo, Double(q.z)) }
            }
            let z = Double(p.prop.box.z)
            if (z > lo && z < hi) || hi - lo < 2 { return p }
            let gap = Double(rowZGap)
            let z2 = hi - lo > 2 * gap ? min(hi - gap, max(lo + gap, z)) : ((lo + hi) / 2).rounded(.down)
            var out = p
            out.prop.box.z = Int(z2)
            return out
        }
    }

    static func settleFootprintOrder(_ props: [Placed], _ desks: [PlacedDesk]) -> [Placed] {
        var z: [String: Int] = [:]
        for p in props { z[p.prop.id] = p.prop.box.z }
        let items = props.filter { !$0.hasPanels && !$0.onTable && !$0.tableBit }.map { (id: $0.prop.id, fp: $0.prop.footprint, rect: $0.prop.rect) }
        let fixed = desks.map { (fp: $0.footprint, rect: $0.rect, z: $0.box.z) }
        for _ in 0..<(items.count + 1) {
            var changed = false
            for back in items {
                for front in items {
                    if front.id == back.id || !rectsOverlap(front.rect, back.rect) { continue }
                    let ahead = front.fp.u0 >= back.fp.u1 - touchEps || front.fp.v0 >= back.fp.v1 - touchEps
                    let behind = front.fp.u1 <= back.fp.u0 + touchEps || front.fp.v1 <= back.fp.v0 + touchEps
                    if !ahead || behind { continue }
                    if z[front.id]! <= z[back.id]! {
                        z[front.id] = z[back.id]! + aheadZGap
                        changed = true
                    }
                }
                // A desk keeps its own z: the prop behind it goes lower.
                for d in fixed {
                    if !rectsOverlap(d.rect, back.rect) { continue }
                    let ahead = d.fp.u0 >= back.fp.u1 - touchEps || d.fp.v0 >= back.fp.v1 - touchEps
                    let behind = d.fp.u1 <= back.fp.u0 + touchEps || d.fp.v1 <= back.fp.v0 + touchEps
                    if ahead && !behind && z[back.id]! >= d.z {
                        z[back.id] = d.z - aheadZGap
                        changed = true
                    }
                }
            }
            if !changed { break }
        }
        return props.map { p in
            var out = p
            out.prop.box.z = z[p.prop.id]!
            return out
        }
    }

    // MARK: public entry points

    /// buildRoomFloor's props (room.ts 944-960: wall seats, table tops, each known placement, then companion parts),
    /// settled in depth as room-office.ts 40 does.
    public static func place(room: FloorRoom, frame: FloorFrame, catalogue: RoomCatalogue, desks: [PlacedDesk],
                             gridSize: Double) -> [PlacedProp] {
        let grid = gridSize
        let seats = wallSeats(frame, room.wallItems, catalogue)
        let tables = tableTops(frame, room.props, catalogue, grid: grid)
        var props: [Placed] = []
        var owners: [(def: PropDef, placement: PropPlacement)] = []
        for placement in room.props {
            guard let def = catalogue.props[placement.prop] else { continue }
            let fp = propFootprint(frame, def, u: placement.u, v: placement.v, facing: placement.facing, grid: grid)
            let lowered = def.raised != nil && seatUnder(fp, seats) == nil
            props.append(placeProp(frame, def, placement, lowered: lowered, table: isTableBit(def) ? tableUnder(fp, tables) : nil, grid: grid))
            owners.append((def, placement))
        }
        for owner in owners {
            for placement in companionParts(frame, owner.def, owner.placement, catalogue, grid: grid).props {
                guard let def = catalogue.props[placement.prop] else { continue }
                var p = placeProp(frame, def, placement, grid: grid)
                p.prop.companionOf = owner.placement.id
                props.append(p)
            }
        }
        return settleFootprintOrder(settlePanelRows(props, desks), desks).map(\.prop)
    }

    /// The rugs a room shows (room.ts roomRugs), boxed as RoomShell.tsx Rug draws them in the floor plane.
    public static func rugs(room: FloorRoom, frame: FloorFrame, catalogue: RoomCatalogue, gridSize: Double) -> [PlacedRug] {
        let size = frame.plane.size
        return roomRugs(frame, room, catalogue, grid: gridSize).map { r in
            PlacedRug(id: r.id, rug: r.rug, image: catalogue.rugs[r.rug]?.image,
                      rect: CGRect(x: (r.v - r.w / 2) * size, y: (r.u - r.d / 2) * size, width: r.w * size, height: r.d * size),
                      turned: r.turned == true)
        }
    }

    /// The spots on a room's rugs (buildRoomFloor 978-984: roomRugs, then rugSpots), each owned by its rug.
    public static func rugSpots(room: FloorRoom, frame: FloorFrame, catalogue: RoomCatalogue, gridSize: Double) -> [RoomSpot] {
        roomRugs(frame, room, catalogue, grid: gridSize).flatMap { r -> [RoomSpot] in
            guard let def = catalogue.rugs[r.rug] else { return [] }
            return rugSpots(def, r)
        }
    }
}

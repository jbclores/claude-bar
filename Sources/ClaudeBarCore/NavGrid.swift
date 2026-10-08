import Foundation

/// One floor's walking grid, carved the way Cat Office carves the floor its cats walk (the route finder is separate).
/// Ports of nav-grid.ts's grid queries plus desks.ts `footprintCells` / `cellIndex` / `carveGrid` and room.ts's prop blocking.
public struct NavGrid: Sendable {
    public let size: Int
    private let open: [Bool]
    /// Connected-region id per cell (0 = blocked), 4-connected (nav-grid.ts labelRegions).
    private let regions: [Int]
    private let frame: FloorFrame

    /// desks.ts FOOTPRINT_MARGIN_CELLS.
    static let footprintMarginCells = 0.5
    /// room.ts EDGE_BAND_CELLS.
    static let edgeBandCells = 1

    /// room.ts contains: strictly inside.
    static func contains(_ fp: Footprint, _ p: FloorPoint) -> Bool {
        p.u > fp.u0 && p.u < fp.u1 && p.v > fp.v0 && p.v < fp.v1
    }

    /// The floor as the browser walks it: nil when the floor has no valid `walkable`.
    public init?(floor: Floor, room: BuiltRoom) {
        guard let rows = floor.walkable else { return nil }
        let n = rows.count
        // room.ts buildRoomFloor 930-934: every cell open except a band along the floor's edges. (building.json's own
        // walkable grid only gives the size and says the floor has one: Cat Office walks the built floor, not it.)
        let inside = { (ui: Int, vi: Int) in min(ui, vi, n - 1 - ui, n - 1 - vi) >= Self.edgeBandCells }
        var cells = (0..<(n * n)).map { inside($0 / n, $0 % n) }
        // room.ts 962-963: table bits stand on their tables and take no floor; every other prop (companions too) does.
        let onFloor = room.props.filter { !$0.tableBit }
        for p in onFloor {
            for idx in Self.footprintCells(p.footprint, size: n) { cells[idx] = false }
        }
        // room.ts 991-1001: spots on the floor get their cell back unless another prop covers the point; a lifted spot
        // is on its prop (a sofa seat), so its cell stays blocked.
        let spots = (room.elevator.map { [RoomSpot(id: $0.id, kind: "elevator", pose: nil, standAt: $0.standAt, facing: $0.facing, lift: 0, owner: $0.id)] } ?? [])
            + room.rugSpots + room.props.flatMap(\.spots)
        for s in spots where s.lift <= 0 {
            for at in [s.standAt] + s.slots {
                if onFloor.contains(where: { $0.id != s.owner && Self.contains($0.footprint, at) }) { continue }
                let idx = Self.cellIndex(at, size: n)
                if inside(idx / n, idx % n) { cells[idx] = true }
            }
        }
        // desks.ts carveGrid: block every desk's footprint, then reopen each work cell the grid had open.
        let base = cells
        for d in room.desks {
            for idx in Self.footprintCells(d.footprint, size: n) { cells[idx] = false }
        }
        for d in room.desks {
            let idx = Self.cellIndex(d.standAt, size: n)
            if base[idx] { cells[idx] = true }
        }
        self.init(size: n, open: cells, frame: room.frame)
    }

    /// Already-carved cells (`open[ui * size + vi]`), for tests.
    public init(size: Int, open: [Bool], frame: FloorFrame) {
        precondition(size >= 1 && open.count == size * size)
        self.size = size
        self.open = open
        self.frame = frame
        self.regions = Self.labelRegions(size: size, open: open)
    }

    /// nav-grid.ts labelRegions.
    private static func labelRegions(size n: Int, open: [Bool]) -> [Int] {
        var labels = [Int](repeating: 0, count: n * n)
        var next = 0
        var stack: [Int] = []
        for start in 0..<(n * n) where open[start] && labels[start] == 0 {
            next += 1
            labels[start] = next
            stack.append(start)
            while let idx = stack.popLast() {
                let ui = idx / n, vi = idx % n
                for (du, dv) in [(1, 0), (-1, 0), (0, 1), (0, -1)] {
                    let nu = ui + du, nv = vi + dv
                    guard nu >= 0, nv >= 0, nu < n, nv < n, open[nu * n + nv] else { continue }
                    let j = nu * n + nv
                    if labels[j] != 0 { continue }
                    labels[j] = next
                    stack.append(j)
                }
            }
        }
        return labels
    }

    /// desks.ts footprintCells: every cell whose centre lies inside the footprint grown by `margin` cells.
    static func footprintCells(_ fp: Footprint, size: Int, margin: Double = footprintMarginCells) -> [Int] {
        let n = Double(size)
        let m = margin / n
        func lo(_ x: Double) -> Int { max(0, Int((x * n - 0.5).rounded(.up))) }
        func hi(_ x: Double) -> Int { min(size - 1, Int((x * n - 0.5).rounded(.down))) }
        var cells: [Int] = []
        let u0 = lo(fp.u0 - m), u1 = hi(fp.u1 + m), v0 = lo(fp.v0 - m), v1 = hi(fp.v1 + m)
        guard u0 <= u1, v0 <= v1 else { return cells }
        for ui in u0...u1 { for vi in v0...v1 { cells.append(ui * size + vi) } }
        return cells
    }

    /// desks.ts cellIndex: the grid cell containing a floor point.
    static func cellIndex(_ p: FloorPoint, size: Int) -> Int {
        func c(_ x: Double) -> Int { min(size - 1, max(0, Int((x * Double(size)).rounded(.down)))) }
        return c(p.u) * size + c(p.v)
    }

    public func isOpen(_ ui: Int, _ vi: Int) -> Bool {
        guard ui >= 0, vi >= 0, ui < size, vi < size else { return false }
        return open[ui * size + vi]
    }

    public func isOpenAt(_ p: FloorPoint) -> Bool {
        let c = cellOf(p)
        return isOpen(c.ui, c.vi)
    }

    public func cellOf(_ p: FloorPoint) -> (ui: Int, vi: Int) {
        let i = Self.cellIndex(p, size: size)
        return (i / size, i % size)
    }

    public func cellCenter(_ ui: Int, _ vi: Int) -> FloorPoint {
        FloorPoint(u: (Double(ui) + 0.5) / Double(size), v: (Double(vi) + 0.5) / Double(size))
    }

    /// nav-grid.ts nearestOpenCell: the nearest open cell to a point, searching outward in rings (first strictly
    /// nearer cell in du, dv order wins), optionally only within one region.
    public func nearestOpenCell(_ p: FloorPoint, region: Int? = nil) -> (ui: Int, vi: Int)? {
        func ok(_ ui: Int, _ vi: Int) -> Bool {
            isOpen(ui, vi) && (region == nil || regions[ui * size + vi] == region)
        }
        let start = cellOf(p)
        if ok(start.ui, start.vi) { return start }
        guard size > 1 else { return nil }
        for r in 1..<size {
            var best: (ui: Int, vi: Int)?
            var bestDist = Int.max
            for du in -r...r {
                for dv in -r...r {
                    if max(abs(du), abs(dv)) != r { continue }
                    let ui = start.ui + du, vi = start.vi + dv
                    if !ok(ui, vi) { continue }
                    let d = du * du + dv * dv
                    if d < bestDist { bestDist = d; best = (ui, vi) }
                }
            }
            if let best { return best }
        }
        return nil
    }

    /// Region id of the open cell nearest to p (0 when the grid has no open cells).
    public func regionOf(_ p: FloorPoint) -> Int {
        guard let c = nearestOpenCell(p) else { return 0 }
        return regions[c.ui * size + c.vi]
    }

    /// The carved rows as "1"/"0" strings, as `nav.walkable` in the fixtures.
    public var walkableRows: [String] {
        (0..<size).map { ui in String((0..<size).map { open[ui * size + $0] ? "1" : "0" }) }
    }
}

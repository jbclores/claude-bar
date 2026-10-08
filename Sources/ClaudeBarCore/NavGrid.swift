import Foundation

/// One floor's walking grid, carved the way Cat Office carves the floor its cats walk, with its route finder.
/// Ports of nav-grid.ts's grid queries and `findPath` plus desks.ts `footprintCells` / `cellIndex` / `carveGrid` and room.ts's prop blocking.
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
        let spots = (room.elevator.map { [RoomSpot(id: $0.id, kind: "elevator", pose: nil, standAt: $0.standAt, facing: $0.facing, lift: 0, owner: $0.id)] } ?? [])
            + room.rugSpots + room.props.flatMap(\.spots)
        self.init(size: n, open: Self.carved(Self.roomCells(size: n, props: room.props, spots: spots), desks: room.desks, size: n), frame: room.frame)
    }

    /// room.ts buildRoomFloor's `open` grid (the room's floor before desks), as cells `open[ui * size + vi]`.
    static func roomCells(size n: Int, props: [PlacedProp], spots: [RoomSpot]) -> [Bool] {
        // room.ts buildRoomFloor 930-934: every cell open except a band along the floor's edges. (building.json's own
        // walkable grid only gives the size and says the floor has one: Cat Office walks the built floor, not it.)
        let inside = { (ui: Int, vi: Int) in min(ui, vi, n - 1 - ui, n - 1 - vi) >= Self.edgeBandCells }
        var cells = (0..<(n * n)).map { inside($0 / n, $0 % n) }
        // room.ts 962-963: table bits stand on their tables and take no floor; every other prop (companions too) does.
        let onFloor = props.filter { !$0.tableBit }
        for p in onFloor {
            for idx in Self.footprintCells(p.footprint, size: n) { cells[idx] = false }
        }
        // room.ts 991-1001: spots on the floor get their cell back unless another prop covers the point; a lifted spot
        // is on its prop (a sofa seat), so its cell stays blocked.
        for s in spots where s.lift <= 0 {
            for at in [s.standAt] + s.slots {
                if onFloor.contains(where: { $0.id != s.owner && Self.contains($0.footprint, at) }) { continue }
                let idx = Self.cellIndex(at, size: n)
                if inside(idx / n, idx % n) { cells[idx] = true }
            }
        }
        return cells
    }

    /// desks.ts carveGrid: block every desk's footprint, then reopen each work cell the grid had open.
    static func carved(_ base: [Bool], desks: [PlacedDesk], size n: Int) -> [Bool] {
        var cells = base
        for d in desks {
            for idx in Self.footprintCells(d.footprint, size: n) { cells[idx] = false }
        }
        for d in desks {
            let idx = Self.cellIndex(d.standAt, size: n)
            if base[idx] { cells[idx] = true }
        }
        return cells
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
        // Clamped in Double before converting (JS clamps in floats; Int(Double) traps on huge values). NaN gives an empty range.
        func lo(_ x: Double) -> Int { x.isNaN ? size : Int(min(n, max(0, (x * n - 0.5).rounded(.up)))) }
        func hi(_ x: Double) -> Int { x.isNaN ? -1 : Int(min(n - 1, max(-1, (x * n - 0.5).rounded(.down)))) }
        var cells: [Int] = []
        let u0 = lo(fp.u0 - m), u1 = hi(fp.u1 + m), v0 = lo(fp.v0 - m), v1 = hi(fp.v1 + m)
        guard u0 <= u1, v0 <= v1 else { return cells }
        for ui in u0...u1 { for vi in v0...v1 { cells.append(ui * size + vi) } }
        return cells
    }

    /// desks.ts cellIndex: the grid cell containing a floor point (clamped in Double first; a NaN coordinate maps to cell 0).
    static func cellIndex(_ p: FloorPoint, size: Int) -> Int {
        func c(_ x: Double) -> Int { x.isNaN ? 0 : Int(min(Double(size - 1), max(0, (x * Double(size)).rounded(.down)))) }
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

// MARK: - Routes (nav-grid.ts findPath and its helpers). Cat Office's hazards (a panic's fires) aren't ported: wherever
// nav-grid.ts consults them, this behaves as it does with none.

/// nav-grid.ts STEPS: the four grid steps (+u, -u, +v, -v); cats only walk along the floor axes.
private let steps: [(Int, Int)] = [(1, 0), (-1, 0), (0, 1), (0, -1)]
/// nav-grid.ts NO_DIR: direction index for "no step yet" (the search's start state).
private let noDir = 4
/// nav-grid.ts TURN_COST: extra cost of changing direction, in cells.
private let turnCost = 0.5
/// nav-grid.ts STRAIGHT_PX: a sideways part under this (world px) is rounding, not an offset.
private let straightPx = 1e-6

/// nav-grid.ts Axis.
private enum Axis { case u, v }

/// nav-grid.ts Cell.
private struct Cell: Equatable {
    var ui: Int
    var vi: Int
}

/// nav-grid.ts MinHeap: minimal binary min-heap keyed by number (same sift order, so ties break as in the browser).
private struct MinHeap {
    private var items: [Int] = []
    private var keys: [Double] = []

    var count: Int { items.count }

    mutating func push(_ item: Int, _ key: Double) {
        items.append(item)
        keys.append(key)
        var i = items.count - 1
        while i > 0 {
            let parent = (i - 1) >> 1
            if keys[parent] <= keys[i] { break }
            swapAt(i, parent)
            i = parent
        }
    }

    mutating func pop() -> Int {
        let top = items[0]
        let lastItem = items.removeLast()
        let lastKey = keys.removeLast()
        if !items.isEmpty {
            items[0] = lastItem
            keys[0] = lastKey
            var i = 0
            while true {
                let l = i * 2 + 1
                let r = l + 1
                var smallest = i
                if l < items.count && keys[l] < keys[smallest] { smallest = l }
                if r < items.count && keys[r] < keys[smallest] { smallest = r }
                if smallest == i { break }
                swapAt(i, smallest)
                i = smallest
            }
        }
        return top
    }

    private mutating func swapAt(_ a: Int, _ b: Int) {
        items.swapAt(a, b)
        keys.swapAt(a, b)
    }
}

extension NavGrid {
    /// nav-grid.ts MIN_LEG_PX: a leg shorter than this (world px) is a step too small to see (the walk doesn't turn the
    /// cat for it); it is still a leg of its own, so every leg runs along an axis.
    public static let minLegPx = 2.0

    /// On-screen vector (world px) of one unit of u and of v (nav-grid.ts axisU / axisV).
    private var axisU: (x: Double, y: Double) { (frame.corners.left.x - frame.corners.top.x, frame.corners.left.y - frame.corners.top.y) }
    private var axisV: (x: Double, y: Double) { (frame.corners.right.x - frame.corners.top.x, frame.corners.right.y - frame.corners.top.y) }
    private var pxPerU: Double { frame.eu }
    private var pxPerV: Double { frame.ev }

    private func open(_ c: Cell) -> Bool { isOpen(c.ui, c.vi) }
    private func center(_ c: Cell) -> FloorPoint { cellCenter(c.ui, c.vi) }

    /// nav-grid.ts findPath: waypoints from `from` to `to` (excluding `from`, ending exactly at `to` when it is open,
    /// otherwise on the open floor straight in front of it; see `approach`), nil when unreachable. Every leg runs along
    /// u or along v, with as few turns as the floor allows.
    public func findPath(from: FloorPoint, to: FloorPoint) -> [FloorPoint]? {
        search(from, to)
    }

    /// nav-grid.ts search: A* over open cells, 4-neighbour (along the axes only), with a cost per turn.
    private func search(_ from: FloorPoint, _ to: FloorPoint) -> [FloorPoint]? {
        guard let start = approach(from, toward: to), let goal = approach(to, toward: from) else { return nil }
        guard let cells = cellRoute(start.cell, goal.cell) else { return nil }
        let corners = straighten(cornerCells(cells)).map(center)

        var out: [FloorPoint] = []
        // Off the grid (a seat, a desk being moved): step straight onto the floor in front of it first.
        // (nav-grid.ts tests `start.point !== from` by identity: true exactly when `from` isn't on open floor.)
        if !start.isPoint { out += axisLegs(from, start.point) }
        let at = start.point
        if corners.count == 1 {
            out += axisLegs(at, goal.point)
        } else if corners.count == 2 {
            // One straight leg: keep it on the cat's own line and finish with a small sideways leg if needed.
            out += axisLegs(at, goal.point, first: axisOf(corners[0], corners[1]))
        } else {
            // Slide the first and last legs (within their own row or column of cells) onto the start point and onto
            // the goal point, so neither end needs a diagonal or an extra elbow.
            var pts = corners
            let k = pts.count - 1
            if axisOf(corners[0], corners[1]) == .u { pts[1].v = at.v } else { pts[1].u = at.u }
            if axisOf(corners[k - 1], corners[k]) == .u { pts[k - 1].v = goal.point.v } else { pts[k - 1].u = goal.point.u }
            pts[k] = goal.point
            out += pts[1...]
        }
        return dedupe(from, out)
    }

    /// nav-grid.ts approach: where a walk starts or ends for a point — the point itself on open floor (`isPoint`). Off
    /// it, the open floor straight in front of it along u or v (in the nearest open cell's region, at most 3/4 of a
    /// cell further away on screen); of the sides that qualify, the shortest way on toward `toward` wins. Failing all,
    /// the nearest open cell's centre.
    private func approach(_ p: FloorPoint, toward: FloorPoint) -> (cell: Cell, point: FloorPoint, isPoint: Bool)? {
        guard let nc = nearestOpenCell(p) else { return nil }
        let nearest = Cell(ui: nc.ui, vi: nc.vi)
        if isOpenAt(p) { return (nearest, p, true) }
        let n = size
        let region = regionOf(cell: nearest)
        let co = cellOf(p)
        let c = Cell(ui: co.ui, vi: co.vi)
        let reach = max(abs(nearest.ui - c.ui), abs(nearest.vi - c.vi)) + 1
        let fallback = center(nearest)
        let limit = pxDistance(fallback, p) + (0.75 * min(pxPerU, pxPerV)) / Double(n)
        var best: (cell: Cell, point: FloorPoint)?
        var bestScore = Double.infinity
        for (du, dv) in steps {
            for r in 1...reach {
                let cell = Cell(ui: c.ui + du * r, vi: c.vi + dv * r)
                if !open(cell) { continue }
                if regionOf(cell: cell) != region { break }
                let mid = center(cell)
                let point = du == 0 ? FloorPoint(u: p.u, v: mid.v) : FloorPoint(u: mid.u, v: p.v)
                // Compared in Double (Math.floor without a clamp; Int() would trap on huge values).
                let inCell = (point.u * Double(n)).rounded(.down) == Double(cell.ui)
                    && (point.v * Double(n)).rounded(.down) == Double(cell.vi)
                let hop = pxDistance(point, p)
                if !inCell || hop > limit { break }
                let score = hop + abs(toward.u - point.u) * pxPerU + abs(toward.v - point.v) * pxPerV
                if score < bestScore {
                    best = (cell, point)
                    bestScore = score
                }
                break
            }
        }
        if let best { return (best.cell, best.point, false) }
        return (nearest, fallback, false)
    }

    /// nav-grid.ts pxDistance: on-screen distance between two floor points, in world px.
    private func pxDistance(_ a: FloorPoint, _ b: FloorPoint) -> Double {
        let du = b.u - a.u, dv = b.v - a.v
        return hypot(du * axisU.x + dv * axisV.x, du * axisU.y + dv * axisV.y)
    }

    /// nav-grid.ts cellRoute: the cells of a shortest 4-neighbour route with fewest turns, start to goal inclusive.
    private func cellRoute(_ startCell: Cell, _ goalCell: Cell) -> [Cell]? {
        let n = size
        let startIdx = startCell.ui * n + startCell.vi
        let goalIdx = goalCell.ui * n + goalCell.vi
        if startIdx == goalIdx { return [startCell] }
        // State = cell * 5 + the direction of the step that reached it (noDir at the start).
        let states = n * n * 5
        var cameFrom = [Int](repeating: -1, count: states)
        var gScore = [Double](repeating: .infinity, count: states)
        var closed = [Bool](repeating: false, count: states)
        var heap = MinHeap()
        func h(_ idx: Int) -> Double { Double(abs(idx / n - goalCell.ui) + abs(idx % n - goalCell.vi)) }

        let startState = startIdx * 5 + noDir
        gScore[startState] = 0
        heap.push(startState, h(startIdx))
        var goalState = -1
        while heap.count > 0 {
            let state = heap.pop()
            if closed[state] { continue }
            closed[state] = true
            let idx = state / 5
            if idx == goalIdx {
                goalState = state
                break
            }
            let dir = state % 5
            let cu = idx / n, cv = idx % n
            for d in 0..<steps.count {
                let nu = cu + steps[d].0, nv = cv + steps[d].1
                if !isOpen(nu, nv) { continue }
                let nextIdx = nu * n + nv
                let next = nextIdx * 5 + d
                if closed[next] { continue }
                let tentative = gScore[state] + 1 + (dir != noDir && dir != d ? turnCost : 0)
                if tentative < gScore[next] {
                    gScore[next] = tentative
                    cameFrom[next] = state
                    heap.push(next, tentative + h(nextIdx))
                }
            }
        }
        if goalState == -1 { return nil }

        var cells: [Cell] = []
        var s = goalState
        while s != -1 {
            let idx = s / 5
            cells.append(Cell(ui: idx / n, vi: idx % n))
            s = cameFrom[s]
        }
        return cells.reversed()
    }

    /// nav-grid.ts corners: the cells where the route turns, plus its first and last cell.
    private func cornerCells(_ cells: [Cell]) -> [Cell] {
        if cells.count <= 2 { return cells }
        var out = [cells[0]]
        for i in 1..<(cells.count - 1) {
            let a = cells[i - 1], c = cells[i + 1]
            if a.ui != c.ui && a.vi != c.vi { out.append(cells[i]) }
        }
        out.append(cells[cells.count - 1])
        return out
    }

    /// nav-grid.ts straighten: collapse staircases — from each corner, jump to the farthest later corner reachable with
    /// one clear L (two legs along the axes).
    private func straighten(_ corners: [Cell]) -> [Cell] {
        if corners.count <= 2 { return corners }
        var out = [corners[0]]
        var i = 0
        while i < corners.count - 1 {
            let prevAxis = out.count >= 2 ? cellAxis(out[out.count - 2], out[out.count - 1]) : nil
            var jumped = false
            for j in stride(from: corners.count - 1, to: i, by: -1) {
                guard let plan = clearL(corners[i], corners[j], prefer: prevAxis) else { continue }
                if case .elbow(let e) = plan { out.append(e) }
                out.append(corners[j])
                i = j
                jumped = true
                break
            }
            // Unreachable in practice (the next corner is always one clear leg away); stop rather than loop.
            if !jumped {
                out += corners[(i + 1)...]
                break
            }
        }
        return mergeCollinear(out)
    }

    /// nav-grid.ts clearL's result: null (a straight clear leg) or the elbow cell; nil stands for its undefined.
    private enum LegPlan { case straight, elbow(Cell) }

    /// nav-grid.ts clearL: how to get from a to b along the axes over open cells — a straight clear leg, the elbow of a
    /// clear L (preferring to carry on along `prefer`), or nil when neither works.
    private func clearL(_ a: Cell, _ b: Cell, prefer: Axis?) -> LegPlan? {
        if a.ui == b.ui || a.vi == b.vi { return clearLeg(a, b) ? .straight : nil }
        let uFirst = Cell(ui: b.ui, vi: a.vi)
        let vFirst = Cell(ui: a.ui, vi: b.vi)
        let options = prefer == .v ? [vFirst, uFirst] : [uFirst, vFirst]
        for e in options where clearLeg(a, e) && clearLeg(e, b) { return .elbow(e) }
        return nil
    }

    /// nav-grid.ts clearLeg: true when every cell on the straight row or column from a to b is open.
    private func clearLeg(_ a: Cell, _ b: Cell) -> Bool {
        let du = (b.ui - a.ui).signum(), dv = (b.vi - a.vi).signum()
        let count = max(abs(b.ui - a.ui), abs(b.vi - a.vi))
        for s in 0...count where !isOpen(a.ui + du * s, a.vi + dv * s) { return false }
        return true
    }

    /// nav-grid.ts axisLegs: waypoints (excluding a) from a to b along the axes — b alone when it is straight ahead,
    /// otherwise an elbow and b. The elbow goes along `first` first when given, else along the longer leg first (always
    /// so for a sideways part under minLegPx); an elbow on open floor wins over one that isn't.
    private func axisLegs(_ a: FloorPoint, _ b: FloorPoint, first: Axis? = nil) -> [FloorPoint] {
        let lu = abs(b.u - a.u) * pxPerU
        let lv = abs(b.v - a.v) * pxPerV
        if min(lu, lv) < straightPx { return [b] }
        let uFirst = FloorPoint(u: b.u, v: a.v)
        let vFirst = FloorPoint(u: a.u, v: b.v)
        let along = min(lu, lv) < Self.minLegPx ? nil : first
        let order = (along ?? (lu >= lv ? .u : .v)) == .u ? [uFirst, vFirst] : [vFirst, uFirst]
        // No hazards here: nav-grid.ts's legBurns fallback never fires, so it's the open elbow, else order[0].
        let elbow = order.first(where: isOpenAt) ?? order[0]
        return [elbow, b]
    }

    /// The region id of a cell (nav-grid.ts `this.regions[ui * n + vi]`).
    private func regionOf(cell c: Cell) -> Int { regions[c.ui * size + c.vi] }
}

/// nav-grid.ts axisOf: the axis a straight leg between two points runs along.
private func axisOf(_ a: FloorPoint, _ b: FloorPoint) -> Axis {
    abs(b.u - a.u) >= abs(b.v - a.v) ? .u : .v
}

/// nav-grid.ts cellAxis.
private func cellAxis(_ a: Cell, _ b: Cell) -> Axis {
    a.vi == b.vi ? .u : .v
}

/// nav-grid.ts mergeCollinear: drop repeated cells and the middle of three cells in one row or column.
private func mergeCollinear(_ cells: [Cell]) -> [Cell] {
    var out: [Cell] = []
    for c in cells {
        if let last = out.last, last == c { continue }
        if out.count >= 2 {
            let prev = out[out.count - 2], last = out[out.count - 1]
            if (prev.ui == last.ui && last.ui == c.ui) || (prev.vi == last.vi && last.vi == c.vi) { out.removeLast() }
        }
        out.append(c)
    }
    return out
}

/// nav-grid.ts dedupe: drop waypoints that repeat the one before (or the start point).
private func dedupe(_ start: FloorPoint, _ points: [FloorPoint]) -> [FloorPoint] {
    var out: [FloorPoint] = []
    var prev = start
    for p in points {
        if abs(p.u - prev.u) < 1e-12 && abs(p.v - prev.v) < 1e-12 { continue }
        out.append(p)
        prev = p
    }
    // Always end at the goal, even when the cat is already standing on it.
    if out.isEmpty, let last = points.last { out.append(last) }
    return out
}

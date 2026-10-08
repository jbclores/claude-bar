# ClaudeBar Walking Around Furniture Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Cats in ClaudeBar walk around desks and furniture along the same routes as in the user's own Cat Office.

**Architecture:** A Swift port of Cat Office's walking grid (`src/world/nav-grid.ts` plus the grid carving in
`desks.ts`/`room.ts`) in ClaudeBarCore as `NavGrid`, built per floor from `building.json`'s `grid` and the floor's
`BuiltRoom` (desks and props), cached next to `AppState.rooms`. `WalkPath` gains a route-based initialiser; the office
views ask a small router for each walk's route and fall back to today's L. Correctness is pinned by fixtures produced
by Cat Office's own code (`scripts/room-fixtures.ts`).

**Tech Stack:** Swift 6 toolchain (language mode 5), SwiftPM (ClaudeBarCore / ClaudeBar / ClaudeBarCoreTests), Swift
Testing, SwiftUI; TypeScript run with `npx tsx` from the Cat Office folder for fixtures.

**Spec:** `docs/superpowers/specs/2026-10-08-claudebar-walking-grid-design.md`

## Global Constraints

- No layout is built in: everything comes from the connected Cat Office's `building.json`, room parts, props and desks.
- Match Cat Office: carved grid cells exactly; route points within 0.5 world px; same reachable/unreachable answers.
- Never write into the real Cat Office folder (`~/Documents/projects/cat-ai-office-with-art-20261006-1038`): the
  fixture script only reads it (run from it with `npx tsx`), and writes fixtures into this repo.
- Never touch the real `~/.claude` or `~/.config/claude-bar` in tests.
- A cat is never stuck: no route → today's L (`WalkPath(from:to:)`).
- Not ported: hazards/fires, `wouldSeal`, `hasLineOfSight`, `legBurns`.
- Swift tools 6.0, language mode 5; macOS 14+. Match surrounding style: short doc comments citing the Cat Office
  source they port (e.g. `/// nav-grid.ts cellRoute.`), no new dependencies.
- Test command: `swift test`. Build: `bash scripts/build.sh`.

## Review Focus

1. A floor in `building.json` without `grid` (older Cat Office) or with ragged rows: no crash, L walks.
2. A walk whose end point is on a blocked cell (a seat, a bed, a desk's stand-at under a neighbour's footprint margin):
   the cat steps straight off/on along an axis, as Cat Office's `approach`.
3. Walks between two floors' points never mix grids: the router uses the grid of the floor being shown.
4. A walk interrupted mid-route (the cat's target changes): the new route starts from where the cat is now (possibly
   between cell centres), not from its old start.
5. Rounding: view ↔ world ↔ floor conversions round-trip within 0.01 world px, so a route's end lands exactly on the
   seat the cat draws at.

---

## File Structure

| File | Responsibility |
|---|---|
| `scripts/room-fixtures.ts` (modify) | Also write each floor's carved grid and Cat Office's routes for fixed pairs |
| `Tests/ClaudeBarCoreTests/Fixtures/rooms/{user,edge}/expected.json` (regenerate) | Fixture data |
| `Sources/ClaudeBarCore/Building.swift` (modify) | `Floor.walkable: [String]?` from `grid.walkable` |
| `Sources/ClaudeBarCore/RoomGeometry/Props.swift` (modify) | `PlacedProp.tableBit` |
| `Sources/ClaudeBarCore/NavGrid.swift` (create) | carving, regions, cells, `findPath` |
| `Tests/ClaudeBarCoreTests/NavGridTests.swift` (create) | fixture + unit tests |
| `Sources/ClaudeBarCore/WalkPath.swift` (modify) | `init(points:)` |
| `Tests/ClaudeBarCoreTests/WalkPathTests.swift` (modify) | route-based walks |
| `Sources/ClaudeBarCore/SceneFit.swift` (modify) | `world(_:)` inverse of `point(_:)` |
| `Sources/ClaudeBarCore/WalkRouter.swift` (create) | view points → route → `WalkPath`, with the L fallback |
| `Sources/ClaudeBar/AppState.swift` (modify) | `navs: [Int: NavGrid]` built with `rooms` |
| `Sources/ClaudeBar/Views/OfficePeekView.swift` (modify) | the three `WalkPath(from:to:)` walk sites use the router |

---

### Task 1: Fixtures from Cat Office's own walking code

**Files:**
- Modify: `scripts/room-fixtures.ts`
- Regenerate: `Tests/ClaudeBarCoreTests/Fixtures/rooms/user/expected.json`, `Tests/ClaudeBarCoreTests/Fixtures/rooms/edge/expected.json`

**Interfaces:**
- Produces, in each `expected.json` floor object, a new key `nav`:
  ```json
  "nav": {
    "size": 48,
    "walkable": ["0011…", "…"],            // the carved grid the browser walks: size strings of size chars
    "routes": [
      { "from": {"u": 0.1, "v": 0.2}, "to": {"u": 0.7, "v": 0.4},
        "path": [{"u": …, "v": …}, …] }    // findPath's result (excluding `from`), or null when unreachable
    ]
  }
  ```
  Numbers rounded to 1e-6 (`r6`). Floors without a grid get no `nav` key.

- [ ] **Step 1: Find the floor the browser walks.** In the Cat Office folder (read-only), trace what `SimulationEngine`
  is constructed with in the app (`src/app/App.tsx` → … → `new SimulationEngine(…)`), and what `indexFloors` passes to
  `new NavGrid(floor)`. Confirm whether `office.building.floors` from `buildRoomOffice` (already used by the script)
  already has props and desks carved into `grid.walkable` (`room.ts` ~line 963 for props, `desks.ts` `carveGrid` via
  ~line 191 for desks), or whether the app applies the desk layout afterwards. Use exactly that floor. Write what you
  found (file:line) in your report.

- [ ] **Step 2: Add the `nav` output.** In `scripts/room-fixtures.ts`, import `NavGrid` from `src/world/nav-grid.ts`
  and, inside the per-floor loop, for each floor that has `grid`:

```ts
    const nav = new NavGrid(walkFloor);            // walkFloor: the floor found in Step 1
    const pts: { u: number; v: number }[] = [];
    const elevator = walkFloor.spots.find((s: any) => s.kind === 'elevator');
    if (elevator) pts.push(elevator.standAt);
    for (const d of placedDesksForWalk) pts.push(d.standAt);        // the desks found in Step 1
    for (const s of walkFloor.spots) if (s.kind !== 'elevator' && s.standAt) pts.push(s.standAt);
    // Plus fixed probes across the floor (some on open floor, some on furniture), the same for every floor.
    for (const [u, v] of [[0.1, 0.1], [0.5, 0.5], [0.9, 0.9], [0.2, 0.8], [0.8, 0.2], [0.33, 0.66]]) pts.push({ u, v });
    const routes: unknown[] = [];
    for (let i = 0; i < pts.length; i++) {
      for (let j = 0; j < pts.length; j++) {
        if (i === j) continue;
        // Every pair from/to the elevator, else a fixed sample: pairs (i, i+1), (i, i+3), (i, i+7) mod n.
        const n = pts.length;
        const sampled = i === 0 || j === 0 || j === (i + 1) % n || j === (i + 3) % n || j === (i + 7) % n;
        if (!sampled) continue;
        const path = nav.findPath(pts[i], pts[j]);
        routes.push({ from: { u: r6(pts[i].u), v: r6(pts[i].v) }, to: { u: r6(pts[j].u), v: r6(pts[j].v) },
                      path: path ? path.map((p: any) => ({ u: r6(p.u), v: r6(p.v) })) : null });
      }
    }
    floorOut.nav = { size: walkFloor.grid.size, walkable: walkFloor.grid.walkable, routes };
```

  (Adapt the names `walkFloor`, `placedDesksForWalk` and `floorOut` to the script's variables; keep the pair selection
  exactly as written so the fixture is deterministic.)

- [ ] **Step 3: Regenerate both fixtures.** From the Cat Office folder:
  `cd ~/Documents/projects/cat-ai-office-with-art-20261006-1038 && npx tsx ~/Documents/projects/claude-bar/scripts/room-fixtures.ts ~/Documents/projects/claude-bar/Tests/ClaudeBarCoreTests/Fixtures/rooms/user ~/Documents/projects/claude-bar/Tests/ClaudeBarCoreTests/Fixtures/rooms/user/expected.json`
  and the same with `edge`. Expected: `room-fixtures: N floors → …` for each. Check with
  `git diff --stat Tests/ClaudeBarCoreTests/Fixtures` that only `expected.json` files changed, and that the existing
  keys are byte-identical apart from the added `nav` (e.g. `python3 -c` comparing the JSON with `nav` removed against
  `git show HEAD:<file>`).

- [ ] **Step 4: Existing tests still pass.** Run: `swift test 2>&1 | grep -E "tests passed|failed after"`.
  Expected: all pass (the new key is ignored).

- [ ] **Step 5: Commit.**

```bash
git add scripts/room-fixtures.ts Tests/ClaudeBarCoreTests/Fixtures/rooms
git commit -m "test: fixtures with Cat Office's carved walking grids and routes"
```

---

### Task 2: `NavGrid` — the carved grid

**Files:**
- Modify: `Sources/ClaudeBarCore/Building.swift` (parse `grid.walkable`), `Sources/ClaudeBarCore/RoomGeometry/Props.swift` (`tableBit`)
- Create: `Sources/ClaudeBarCore/NavGrid.swift`, `Tests/ClaudeBarCoreTests/NavGridTests.swift`

**Interfaces:**
- Consumes: Task 1's `nav.walkable`; `RoomGeometry.build` → `BuiltRoom` (`frame: FloorFrame`, `desks: [PlacedDesk]`
  with `footprint`, `standAt`; `props: [PlacedProp]` with `footprint`); `Footprint(u0,u1,v0,v1)`, `FloorPoint(u,v)`.
- Produces:
  - `Floor.walkable: [String]?` (nil when `grid.walkable` is missing or any row length ≠ size, or size isn't an integer ≥ 1).
  - `PlacedProp.tableBit: Bool` (true when its def has `placeOn == "table"`; set where `PropPlacer` builds props).
  - `public struct NavGrid: Sendable` with
    - `public init?(floor: Floor, room: BuiltRoom)` — nil when the floor has no valid `walkable`.
    - `public init(size: Int, open: [Bool], frame: FloorFrame)` — for tests (already-carved cells).
    - `public let size: Int`
    - `public func isOpen(_ ui: Int, _ vi: Int) -> Bool`
    - `public func isOpenAt(_ p: FloorPoint) -> Bool`
    - `public func cellOf(_ p: FloorPoint) -> (ui: Int, vi: Int)`
    - `public func cellCenter(_ ui: Int, _ vi: Int) -> FloorPoint`
    - `public func nearestOpenCell(_ p: FloorPoint, region: Int? = nil) -> (ui: Int, vi: Int)?`
    - `public func regionOf(_ p: FloorPoint) -> Int`
    - `public var walkableRows: [String]` (for tests: "1"/"0" rows)
  - `static func footprintCells(_ fp: Footprint, size: Int, margin: Double = 0.5) -> [Int]` and
    `static func cellIndex(_ p: FloorPoint, size: Int) -> Int` (ports of desks.ts).

- [ ] **Step 1: Write the failing fixture test** in `Tests/ClaudeBarCoreTests/NavGridTests.swift`:

```swift
import Foundation
import Testing
@testable import ClaudeBarCore

struct NavFixture: Decodable {
    struct P: Decodable { var u: Double; var v: Double }
    struct Route: Decodable { var from: P; var to: P; var path: [P]? }
    struct Nav: Decodable { var size: Int; var walkable: [String]; var routes: [Route] }
    struct FloorOut: Decodable { var id: Int; var nav: Nav? }
    var floors: [FloorOut]
}

@Suite struct NavGridTests {
    func load(_ b: String) throws -> (Building, RoomCatalogue, NavFixture) {
        let building = try #require(Building.parse(building: fixture("rooms/\(b)/building.json"), parts: fixture("rooms/\(b)/room-parts.json")))
        let catalogue = try #require(RoomCatalogue.parse(parts: fixture("rooms/\(b)/room-parts.json"),
                                                         props: fixture("rooms/\(b)/props.json"),
                                                         desks: fixture("rooms/\(b)/desks.json")))
        let expected = try JSONDecoder().decode(NavFixture.self, from: fixture("rooms/\(b)/expected.json"))
        return (building, catalogue, expected)
    }

    @Test(arguments: ["user", "edge"]) func carvedGridMatchesCatOffice(_ b: String) throws {
        let (building, catalogue, expected) = try load(b)
        var checked = 0
        for f in expected.floors {
            guard let nav = f.nav else { continue }
            let floor = try #require(building.floors.first { $0.id == f.id })
            let room = try #require(RoomGeometry.build(floor: floor, catalogue: catalogue))
            let grid = try #require(NavGrid(floor: floor, room: room))
            #expect(grid.size == nav.size)
            #expect(grid.walkableRows == nav.walkable, "floor \(f.id)")
            checked += 1
        }
        #expect(checked > 0)
    }

    @Test func noGridNoNavGrid() throws {
        let (building, catalogue, _) = try load("user")
        var floor = try #require(building.floors.first)
        let room = try #require(RoomGeometry.build(floor: floor, catalogue: catalogue))
        floor.walkable = nil
        #expect(NavGrid(floor: floor, room: room) == nil)
    }

    @Test func footprintCellsPortsDesksTs() {
        // A footprint covering cell (2,3)'s centre exactly, size 10, margin half a cell: cells 1…3 × 2…4.
        let cells = NavGrid.footprintCells(Footprint(u0: 0.2, u1: 0.3, v0: 0.3, v1: 0.4), size: 10)
        #expect(Set(cells) == Set([1, 2, 3].flatMap { u in [2, 3, 4].map { v in u * 10 + v } }))
        #expect(NavGrid.cellIndex(FloorPoint(u: 0.999, v: 0), size: 10) == 90)
        #expect(NavGrid.cellIndex(FloorPoint(u: 1.5, v: -1), size: 10) == 90)
    }
}
```

  (Check `RoomCatalogue.parse`'s real signature in `Tests/ClaudeBarCoreTests/RoomGeometryTests.swift` and use the same
  loading code those tests use; adjust the helper, not the assertions. Verify the `footprintCellsPortsDesksTs`
  expectation by hand against desks.ts `footprintCells` — `lo(x) = max(0, ceil(x*size - 0.5))`,
  `hi(x) = min(size-1, floor(x*size - 0.5))` with x grown by margin/size — and fix the expected set if the arithmetic
  says otherwise, noting it in the report.)

- [ ] **Step 2: Run to see it fail.** Run: `swift test --filter NavGridTests 2>&1 | tail -5`. Expected: build errors
  (`NavGrid`, `walkable` not found).

- [ ] **Step 3: Implement.**
  - `Building.swift`: in the floor parser next to `gridSize`, read `grid.walkable` as `[String]`; keep it only when
    `size` is an integer ≥ 1, there are exactly `size` rows, and every row has exactly `size` characters. Add
    `public var walkable: [String]?` to `Floor` (with an `init` parameter defaulting to nil).
  - `Props.swift`: add `public var tableBit: Bool = false` to `PlacedProp`; set it from `isTableBit(def)` where props
    (and companion parts) are built.
  - `NavGrid.swift`: port, citing sources:
    - desks.ts `footprintCells` (margin `FOOTPRINT_MARGIN_CELLS` = 0.5) and `cellIndex`.
    - Carving, as the floor the browser walks (Task 1 Step 1's finding, in the Task 1 report): start from `walkable`;
      block `footprintCells` of every prop with `tableBit == false` (companions included); block every desk's
      `footprintCells`; reopen each desk's `cellIndex(standAt)` when the base `walkable` has it open. If Task 1 found
      that `building.json`'s grid already carries some of these, carving them again is harmless (same cells) — but the
      fixture test decides: the carved rows must equal `nav.walkable` exactly.
    - nav-grid.ts constructor axes (`axisU`/`axisV` from `frame.corners` top→left / top→right, `pxPerU`/`pxPerV`),
      `labelRegions` (4-connected), `regionOf`, `isOpen`, `isOpenAt`, `cellOf`, `cellCenter`, `nearestOpenCell`
      (read nav-grid.ts 248-291 and port it line by line: same search order and tie-breaking).

- [ ] **Step 4: Run to see it pass.** Run: `swift test --filter NavGridTests 2>&1 | tail -5`. Expected: all pass. Then
  `swift test 2>&1 | grep -E "tests passed|failed after"` — all pass.

- [ ] **Step 5: Commit.**

```bash
git add Sources/ClaudeBarCore/Building.swift Sources/ClaudeBarCore/RoomGeometry/Props.swift Sources/ClaudeBarCore/NavGrid.swift Tests/ClaudeBarCoreTests/NavGridTests.swift
git commit -m "feat: NavGrid — each floor's walking grid, carved like Cat Office's"
```

---

### Task 3: `NavGrid.findPath` — routes

**Files:**
- Modify: `Sources/ClaudeBarCore/NavGrid.swift`, `Tests/ClaudeBarCoreTests/NavGridTests.swift`

**Interfaces:**
- Consumes: Task 2's `NavGrid`.
- Produces: `public func findPath(from: FloorPoint, to: FloorPoint) -> [FloorPoint]?` — nav-grid.ts `findPath`:
  waypoints excluding `from`, ending at `to` when open (else on the open floor in front of it), nil when unreachable.
  `public static let minLegPx = 2.0`.

- [ ] **Step 1: Write the failing tests** (append to `NavGridTests`):

```swift
    @Test(arguments: ["user", "edge"]) func routesMatchCatOffice(_ b: String) throws {
        let (building, catalogue, expected) = try load(b)
        var checked = 0
        for f in expected.floors {
            guard let nav = f.nav else { continue }
            let floor = try #require(building.floors.first { $0.id == f.id })
            let room = try #require(RoomGeometry.build(floor: floor, catalogue: catalogue))
            let grid = try #require(NavGrid(floor: floor, room: room))
            for r in nav.routes {
                let got = grid.findPath(from: FloorPoint(u: r.from.u, v: r.from.v), to: FloorPoint(u: r.to.u, v: r.to.v))
                guard let want = r.path else { #expect(got == nil, "floor \(f.id) \(r.from)→\(r.to) should be unreachable"); continue }
                let path = try #require(got, "floor \(f.id) \(r.from)→\(r.to) should be reachable")
                #expect(path.count == want.count, "floor \(f.id) \(r.from)→\(r.to): \(path.count) points, want \(want.count)")
                for (p, w) in zip(path, want) {
                    let a = room.frame.px(p), e = room.frame.px(FloorPoint(u: w.u, v: w.v))
                    #expect(hypot(a.x - e.x, a.y - e.y) <= 0.5, "floor \(f.id) \(r.from)→\(r.to)")
                }
                checked += 1
            }
        }
        #expect(checked > 20)
    }

    /// A 10×10 open floor with one blocked 2×6 wall in the middle (cells u 4…5, v 2…7).
    func walled() throws -> NavGrid {
        var open = [Bool](repeating: true, count: 100)
        for u in 4...5 { for v in 2...7 { open[u * 10 + v] = false } }
        let frame = try #require(FloorFrame(corners: FloorCorners(top: WorldPoint(x: 0, y: 0), left: WorldPoint(x: -200, y: 100),
                                                                bottom: WorldPoint(x: 0, y: 200), right: WorldPoint(x: 200, y: 100))))
        return NavGrid(size: 10, open: open, frame: frame)
    }

    @Test func routeGoesRoundAWallAlongTheAxes() throws {
        let g = try walled()
        let from = FloorPoint(u: 0.15, v: 0.45), to = FloorPoint(u: 0.85, v: 0.45)
        let path = try #require(g.findPath(from: from, to: to))
        #expect(path.last == to)
        var prev = from
        for p in path {
            // Every leg runs along u or along v.
            #expect(abs(p.u - prev.u) < 1e-9 || abs(p.v - prev.v) < 1e-9)
            // No point of any leg is in a blocked cell (sampled every 1/100).
            for i in 0...100 {
                let t = Double(i) / 100
                #expect(g.isOpenAt(FloorPoint(u: prev.u + (p.u - prev.u) * t, v: prev.v + (p.v - prev.v) * t)))
            }
            prev = p
        }
    }

    @Test func boxedInSpotIsUnreachable() throws {
        var open = [Bool](repeating: true, count: 100)
        for u in 3...5 { for v in 3...5 where !(u == 4 && v == 4) { open[u * 10 + v] = false } }   // a ring round (4,4)
        let frame = try #require(FloorFrame(corners: FloorCorners(top: WorldPoint(x: 0, y: 0), left: WorldPoint(x: -200, y: 100),
                                                                bottom: WorldPoint(x: 0, y: 200), right: WorldPoint(x: 200, y: 100))))
        let g = NavGrid(size: 10, open: open, frame: frame)
        #expect(g.findPath(from: FloorPoint(u: 0.05, v: 0.05), to: FloorPoint(u: 0.45, v: 0.45)) == nil)
    }

    @Test func aSeatOnFurnitureStepsOffAlongAnAxis() throws {
        let g = try walled()
        let seat = FloorPoint(u: 0.45, v: 0.25)          // inside the wall (blocked)
        let path = try #require(g.findPath(from: seat, to: FloorPoint(u: 0.15, v: 0.85)))
        let first = path[0]
        #expect(abs(first.u - seat.u) < 1e-9 || abs(first.v - seat.v) < 1e-9, "the hop off runs along an axis")
        #expect(g.isOpenAt(first))
    }
```

  (`FloorCorners`/`WorldPoint` initialisers: use the real ones from `Building.swift`/`FloorMath.swift`.)

- [ ] **Step 2: Run to see them fail.** Run: `swift test --filter NavGridTests 2>&1 | tail -5`. Expected: build error
  (`findPath` not found).

- [ ] **Step 3: Port** nav-grid.ts `findPath`, `search`, `approach`, `pxDistance`, `cellRoute` (with its `MinHeap`,
  `STEPS`, `NO_DIR`, `TURN_COST` = 0.5, tie-breaking exactly as written), `corners`, `straighten`, `clearL`, `clearLeg`,
  `axisLegs`, `axisOf`, `dedupe`, `MIN_LEG_PX` = 2 and `STRAIGHT_PX`, line by line, each with a `/// nav-grid.ts <name>.`
  comment. Skip hazards: wherever nav-grid.ts consults `hazard`/`legBurns`, the Swift version behaves as with no
  hazards (keep a one-line comment saying so). Read the whole of nav-grid.ts 248–581 before writing; the fixtures
  decide correctness.

- [ ] **Step 4: Run to see them pass.** Run: `swift test --filter NavGridTests 2>&1 | tail -5` then the full
  `swift test`. Expected: all pass. If a fixture route differs, compare against the TS line by line (heap order, tie
  breaks, float rounding) — don't loosen the 0.5 px tolerance.

- [ ] **Step 5: Commit.**

```bash
git add Sources/ClaudeBarCore/NavGrid.swift Tests/ClaudeBarCoreTests/NavGridTests.swift
git commit -m "feat: NavGrid.findPath — Cat Office's routes around furniture"
```

---

### Task 4: Walks along routes (`WalkPath`, `SceneFit`, `WalkRouter`)

**Files:**
- Modify: `Sources/ClaudeBarCore/WalkPath.swift`, `Sources/ClaudeBarCore/SceneFit.swift`
- Create: `Sources/ClaudeBarCore/WalkRouter.swift`
- Test: `Tests/ClaudeBarCoreTests/WalkPathTests.swift` (add), `Tests/ClaudeBarCoreTests/WalkRouterTests.swift` (create)

**Interfaces:**
- Consumes: `NavGrid.findPath`, `FloorFrame.px/uv`, `SceneFit.point`.
- Produces:
  - `WalkPath.init(points: [CGPoint])` — a walk through the given screen points in order (first = start). Each leg's
    direction from its screen vector with the same mapping as today (`+u` = down-left "front-left", `−u` "back-right",
    `+v` down-right "front-right", `−v` "back-left"); legs shorter than `minLeg` merge into the next; fewer than 2
    distinct points → a zero-length walk at the point.
  - `SceneFit.world(_ p: CGPoint) -> WorldPoint` — inverse of `point(_:)`.
  - `public enum WalkRouter { public static func path(from: CGPoint, to: CGPoint, grid: NavGrid?, frame: FloorFrame?, fit: SceneFit?) -> WalkPath }`
    — when all three are given: view → world (`fit.world`) → floor (`frame.uv`) → `grid.findPath` → floor → world →
    view, `WalkPath(points: [from] + route)` with the route's last point replaced by `to` exactly; otherwise, or when
    `findPath` is nil, `WalkPath(from:to:)`.

- [ ] **Step 1: Write the failing tests.**
  In `WalkPathTests.swift` add:

```swift
    @Test func walkThroughRoutePointsFacesEachLeg() {
        // Screen: +u is (−2, 1), +v is (2, 1). A +v leg then a +u leg.
        let w = WalkPath(points: [CGPoint(x: 0, y: 0), CGPoint(x: 40, y: 20), CGPoint(x: 0, y: 40)])
        #expect(w.points == [CGPoint(x: 0, y: 0), CGPoint(x: 40, y: 20), CGPoint(x: 0, y: 40)])
        #expect(w.direction(atDistance: 1) == "front-right")
        #expect(w.direction(atDistance: w.length - 1) == "front-left")
        #expect(abs(w.length - 2 * hypot(40, 20)) < 1e-9)
        #expect(w.position(atDistance: w.length + 5) == CGPoint(x: 0, y: 40))
    }

    @Test func tinyLegsMergeAndOnePointIsStill() {
        let w = WalkPath(points: [CGPoint(x: 0, y: 0), CGPoint(x: 0.5, y: 0.25), CGPoint(x: 40, y: 20)])
        #expect(w.points.count == 2)
        let still = WalkPath(points: [CGPoint(x: 3, y: 4)])
        #expect(still.length == 0 && still.position(atDistance: 10) == CGPoint(x: 3, y: 4))
    }
```

  Create `Tests/ClaudeBarCoreTests/WalkRouterTests.swift`:

```swift
import CoreGraphics
import Testing
@testable import ClaudeBarCore

@Suite struct WalkRouterTests {
    let frame = FloorFrame(corners: FloorCorners(top: WorldPoint(x: 0, y: 0), left: WorldPoint(x: -200, y: 100),
                                                 bottom: WorldPoint(x: 0, y: 200), right: WorldPoint(x: 200, y: 100)))!
    let fit = SceneFit(scale: 0.5, origin: CGPoint(x: 120, y: 10))

    func grid(wall: Bool) -> NavGrid {
        var open = [Bool](repeating: true, count: 100)
        if wall { for u in 4...5 { for v in 2...7 { open[u * 10 + v] = false } } }
        return NavGrid(size: 10, open: open, frame: frame)
    }
    func view(_ u: Double, _ v: Double) -> CGPoint { fit.point(frame.px(FloorPoint(u: u, v: v))) }

    @Test func fitRoundTrips() {
        let p = CGPoint(x: 77.3, y: 41.9)
        let back = fit.point(fit.world(p))
        #expect(abs(back.x - p.x) < 1e-9 && abs(back.y - p.y) < 1e-9)
    }

    @Test func routesAroundAWallAndEndsExactlyAtTheTarget() {
        let from = view(0.15, 0.45), to = view(0.85, 0.45)
        let w = WalkRouter.path(from: from, to: to, grid: grid(wall: true), frame: frame, fit: fit)
        #expect(w.points.first == from && w.points.last == to)
        #expect(w.points.count > 3, "goes round, not straight through")
    }

    @Test func noGridOrNoRouteFallsBackToTheL() {
        let from = view(0.15, 0.45), to = view(0.85, 0.45)
        #expect(WalkRouter.path(from: from, to: to, grid: nil, frame: frame, fit: fit) == WalkPath(from: from, to: to))
        var open = [Bool](repeating: true, count: 100)
        for v in 0..<10 { open[50 + v] = false }   // a full wall across u = 5: the far side is unreachable
        let cut = NavGrid(size: 10, open: open, frame: frame)
        #expect(WalkRouter.path(from: from, to: to, grid: cut, frame: frame, fit: fit) == WalkPath(from: from, to: to))
    }
}
```

- [ ] **Step 2: Run to see them fail.** Run: `swift test --filter 'WalkPathTests|WalkRouterTests' 2>&1 | tail -5`.
  Expected: build errors (`init(points:)`, `world`, `WalkRouter` missing).

- [ ] **Step 3: Implement.**
  - `WalkPath.init(points:)`: build `points`/`directions`/`length` as described; refactor the existing L initialiser
    to compute its corner points and call the shared leg builder, so both share one facing/length implementation (the
    existing L tests must still pass unchanged).
  - `SceneFit.world`: `WorldPoint(x: Double((p.x - origin.x) / scale), y: Double((p.y - origin.y) / scale))`.
  - `WalkRouter.path`: as in Interfaces.

- [ ] **Step 4: Run to see them pass.** Run: `swift test --filter 'WalkPathTests|WalkRouterTests'` then full
  `swift test`. Expected: all pass, including the existing WalkPath and ElevatorTrip tests.

- [ ] **Step 5: Commit.**

```bash
git add Sources/ClaudeBarCore/WalkPath.swift Sources/ClaudeBarCore/SceneFit.swift Sources/ClaudeBarCore/WalkRouter.swift Tests/ClaudeBarCoreTests/WalkPathTests.swift Tests/ClaudeBarCoreTests/WalkRouterTests.swift
git commit -m "feat: walks follow routes (WalkRouter), with the L as fallback"
```

---

### Task 5: The office walks around furniture

**Files:**
- Modify: `Sources/ClaudeBar/AppState.swift`, `Sources/ClaudeBar/Views/OfficePeekView.swift`

**Interfaces:**
- Consumes: `NavGrid(floor:room:)`, `WalkRouter.path`, `AppState.rooms`, `OfficePeekView.fits[floorId]`.
- Produces: `AppState.navs: [Int: NavGrid]` (published, rebuilt in `rebuildRooms()` from the same floors and rooms).

- [ ] **Step 1: Cache grids with rooms.** In `AppState.rebuildRooms()` (AppState.swift ~line 33), after `rooms` is
  built, set `navs = Dictionary(uniqueKeysWithValues: rooms.compactMap { id, room in building.floors.first { $0.id == id }.flatMap { NavGrid(floor: $0, room: room) }.map { (id, $0) } })`
  (and `navs = [:]` where `rooms = [:]`). Declare `@Published private(set) var navs: [Int: NavGrid] = [:]` next to `rooms`.

- [ ] **Step 2: Route the three walks.** In `OfficePeekView.swift`, replace the three `WalkPath(from: X, to: Y)` walk
  constructions (the walk to the elevator ~line 107, the walk out of the elevator ~line 244, the desk/seat walk ~line
  257) with
  `WalkRouter.path(from: X, to: Y, grid: state.navs[floorId], frame: state.rooms[floorId]?.frame, fit: fits[floorId])`.
  All three run on the floor being shown (`floorId`); leave `WalkPath(from: place, to: place)` (~line 612, a still
  rider) as it is.

- [ ] **Step 3: Build and run every test.**
  Run: `swift test 2>&1 | grep -E "tests passed|failed after"; bash scripts/build.sh 2>&1 | grep -E "error:|Built"`
  then `build/ClaudeBar.app/Contents/MacOS/ClaudeBar --test-tabs | tail -2`, `--test-zoom` (if present: check
  `RenderPeek.swift` for the flag names) and `--test-setup | tail -1`, `--test-undo | tail -1`.
  Expected: all pass, `Built build/ClaudeBar.app`.

- [ ] **Step 4: Look at a walk.** Render the peek mid-walk around furniture with the existing replay hook:
  `CLAUDEBAR_RENDER_FLIP_AT=1 CLAUDEBAR_RENDER_MIDWALK=0.6 build/ClaudeBar.app/Contents/MacOS/ClaudeBar --render-peek /tmp/cb-mock/walk-mid.png`
  (read `RenderPeek.swift`'s `--render-peek` for how the replay hook works and adjust the timing values if the cat
  isn't mid-walk). Read the PNG with the Read tool: the walking cat must not be drawn over a desk or prop. Note in the
  report what you saw; if no walk happens on the live data, say so (the unit tests carry correctness).

- [ ] **Step 5: Commit.**

```bash
git add Sources/ClaudeBar/AppState.swift Sources/ClaudeBar/Views/OfficePeekView.swift
git commit -m "feat: cats walk around furniture in the office and the peek"
```

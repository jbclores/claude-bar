# ClaudeBar Floors Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace ClaudeBar's single office room with Cat Office's building. One floor is shown at a time, each with its own desks and look. A floor menu has ▲▼, a busy-floors strip and Follow, and cats ride the elevator between floors.

**Architecture:** Pure logic in `ClaudeBarCore`:

- `Building` parses Cat Office's `building.json` and `room-parts.json`.
- `FloorPlan` decides each agent's floor, desk or spot, and the Follow target.
- `ElevatorTrip` handles ride timing.

SwiftUI views in the `ClaudeBar` target draw one floor (`FloorRoomView`) and the picker (`FloorPicker`). They reuse today's desk station, labels, hover cards, zoom, night look and walking.

**Tech Stack:** Swift 6 toolchain (language mode 5), SwiftPM, SwiftUI + AppKit, Swift Testing (`import Testing`), macOS 14+, Command Line Tools only (no Xcode).

**Spec:** `docs/superpowers/specs/2026-10-07-claudebar-floors-design.md`, which builds on `docs/superpowers/specs/2026-10-06-claude-bar-design.md`.

## Global Constraints

- **Data source:** `/data/building.json` and `/data/room-parts.json` from Cat Office (no token). Cache a copy so floors still show while Cat Office is offline.
- **Floor rules:**
  - idle → Lounge (id 1)
  - working or waiting with a project → the floor whose `repo.root` equals or contains the agent's `repoRoot ?? cwd`
  - no matching floor → Desk pool (the floor named "Desk pool", else the first floor without a repo other than the Lounge)
  - sub-agent → its parent's floor (by `parentName`), else the Desk pool
  - ended → not shown
- **ClaudeBar never creates floors.**
- **Desks:** the floor's own `room.desks[]` (design, flip, rear) in stored order, up to 2 rows of 6.
  - Helpers take the free desk nearest their parent, else stand beside the parent's desk at 0.8×, labeled "working nearby", up to 2 per parent, then "+N".
  - Any other overflow queues at the right edge, then "+N".
- **Lounge:** 10 fixed spots (round sofa, sofa, cat bed, two bean bags, two floor cushions, rug), then "+N asleep". Lounge sign on the back wall.
- **Picker:**
  - a floor menu "12 claude-bar · 3 cats" listing every floor (empty ones dimmed, amber dot = needs you)
  - ▲ / ▼ step one floor
  - Follow toggle
  - a strip with one bar per floor: gray empty, green working, amber needs you, dark shown
- **Follow:**
  - **Target order:** the floor with a cat that needs you (newest first), else the floor where a cat most recently started or finished work, else the floor with the most working cats, else the Lounge.
  - **On by default and on each open.** Picking a floor yourself (menu, ▲▼, strip) turns it off.
  - **The peek always follows** and shows the floor in its header ("Cat Office · 12 claude-bar").
  - **Zoom resets when the floor changes.**
- **Elevator ride (2× Cat Office):** walk to the elevator, board (face back-left, fade out 0.35s), ride 0.7s + 0.35s per floor, arrive (fade in facing front-right, 0.35s), walk to the spot, hop. Waiting cats stand in 3 positions. With Reduce Motion, cats switch floors instantly.
- **Elevator plate:** the floor number on the plate from `room-parts.json` (`plate` x/y/width/height/color), font 0.8 × plate height.
- **Testing:** `swift test` must pass. Renders use the existing `--render-peek` / `--render-dropdown`. UI click tests click only exact targets (menu button, ▲▼, Follow), never sweeps.
- **Commits:** end every commit message with `Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>`.

## Review Focus

1. **A floor's `repo.root` that is a parent of another floor's root** (e.g. `~/Documents` vs `~/Documents/projects/claude-bar`): the agent goes to the **longest** (most specific) matching root. Covered in Task 2.
2. **A helper whose parent is idle (in the Lounge):** it still goes to the parent's floor (the Lounge) and stands beside the parent's seat, not in the Desk pool. Covered in Task 3.
3. **`building.json` missing or broken while Cat Office is up:** the Office tab falls back to the cached copy, else a one-floor building (the Lounge) with today's room, and never crashes. Covered in Task 1.
4. **The shown floor disappears from `building.json`** (a deleted floor) while Follow is off: the view switches to Follow's target and Follow turns on. Covered in Task 6.
5. **Two cats with the same reported desk design and orientation on one floor:** each gets its own desk of that design, and the second takes the next match or a free desk. Covered in Task 3.

---

## File structure

| File | Responsibility |
|---|---|
| `Sources/ClaudeBarCore/Building.swift` (new) | `Building`, `Floor`, `FloorDesk`, `RoomTexture`, `WallItemArt`: parse both JSON files |
| `Sources/ClaudeBarCore/FloorPlan.swift` (new) | Floor per agent, seating per floor (desks, helpers, overflow, lounge spots), Follow target, strip states |
| `Sources/ClaudeBarCore/ElevatorTrip.swift` (new) | Ride phases and timing |
| `Sources/ClaudeBarCore/ArtCache.swift` (modify) | `building()` fetch and cache; texture and wall-item images via the existing `image(path:)` |
| `Sources/ClaudeBar/FloorSelection.swift` (new) | Shown floor plus the Follow state (ObservableObject) |
| `Sources/ClaudeBar/Views/FloorPicker.swift` (new) | Menu, ▲▼, Follow, strip |
| `Sources/ClaudeBar/Views/FloorRoomView.swift` (new) | One floor: backdrop, elevator, desks or lounge, cats, walkers, riders. Replaces `OfficeRoomView`'s room body |
| `Sources/ClaudeBar/Views/OfficePeekView.swift` (modify) | `OfficeRoomView` hosts `FloorRoomView`; the peek header shows the floor |
| `Sources/ClaudeBar/Views/DropdownView.swift` (modify) | The Office tab adds `FloorPicker` above the room |
| `Sources/ClaudeBar/AppState.swift` (modify) | Loads the building and publishes `building` |
| `Tests/ClaudeBarCoreTests/BuildingTests.swift`, `FloorPlanTests.swift`, `ElevatorTripTests.swift` (new) | Unit tests |

---

## Stage 1: floors and picker

### Task 1: Parse Cat Office's building

**Files:**
- Create: `Sources/ClaudeBarCore/Building.swift`
- Test: `Tests/ClaudeBarCoreTests/BuildingTests.swift`

**Interfaces:**
- Produces:
  - `public struct Building: Equatable, Sendable { floors: [Floor]; static let fallback: Building }`
  - `public struct Floor: Equatable, Sendable, Identifiable { id: Int; name: String; repoRoot: String?; floorTexture: RoomTexture?; wallTexture: RoomTexture?; desks: [FloorDesk]; elevator: WallItemArt?; hasLoungeSign: Bool; isLounge: Bool }`
  - `public struct FloorDesk: Equatable, Sendable { id: String; design: String; flip: Bool; rear: Bool }`
  - `public struct RoomTexture: Equatable, Sendable { id: String; image: String; tile: CGSize; color: String }`
  - `public struct WallItemArt: Equatable, Sendable { id: String; image: String; size: CGSize; plate: CGRect?; plateColor: String? }`
  - `public static func Building.parse(building: Data, parts: Data) -> Building?`
  - `Building.lounge`, `Building.deskPool`, `Building.floor(id:)`
- `repoRoot` is **normalized** (`Paths.normalize`, `~` expanded).

- [ ] **Step 1: Write the failing test**

```swift
// Tests/ClaudeBarCoreTests/BuildingTests.swift
import CoreGraphics
import Foundation
import Testing
@testable import ClaudeBarCore

@Suite struct BuildingTests {
    let buildingJSON = #"""
    {"floors":[
      {"id":1,"name":"Lounge","room":{"floor":"oak","wall":"plaster-lounge","desks":[],
        "wallItems":[{"id":"sign-lounge-1","item":"sign-lounge","wall":"right","at":0.25},{"id":"elevator-lounge-1","item":"elevator-lounge","wall":"left","at":0.5}]}},
      {"id":6,"name":"Desk pool","room":{"floor":"oak","wall":"plaster","desks":[{"id":"d1","desk":"s1-oak","u":0.1,"v":0.2,"flip":false}],
        "wallItems":[{"id":"e6","item":"elevator","wall":"left","at":0.5}]}},
      {"id":12,"name":"claude-bar","repo":{"root":"~/Documents/projects/claude-bar"},
        "room":{"floor":"slate","wall":"plaster","desks":[{"id":"f12-desk-1","desk":"s1-walnut","u":0.9,"v":0.1,"flip":true},{"id":"f12-desk-2","desk":"s3-mint","u":0.1,"v":0.3,"flip":false,"rear":true}],
        "wallItems":[{"id":"elevator-12","item":"elevator","wall":"left","at":0.5}]}}
    ]}
    """#
    let partsJSON = #"""
    {"floors":[{"id":"oak","image":"assets/room/floors/oak.png","tile":[1024,528],"color":"#e3a56c"},
               {"id":"slate","image":"assets/room/floors/slate.png","tile":[1024,528],"color":"#6b7280"}],
     "walls":[{"id":"plaster","image":"assets/room/walls/plaster.png","tile":[200,267],"color":"#fdeee0"},
              {"id":"plaster-lounge","image":"assets/room/walls/plaster-lounge.png","tile":[200,432],"color":"#fbe8dc"}],
     "wallItems":[{"id":"elevator","image":"assets/room/wall-items/elevator.png","width":262,"height":231,"plate":{"x":80,"y":10,"width":68,"height":21,"color":"#f4ece6"}},
                  {"id":"elevator-lounge","image":"assets/room/wall-items/elevator-lounge.png","width":256,"height":360,"plate":{"x":77,"y":19,"width":58,"height":23,"color":"#f4ece6"}},
                  {"id":"sign-lounge","image":"assets/room/wall-items/sign-lounge.png","width":195,"height":91}]}
    """#

    func building() throws -> Building {
        try #require(Building.parse(building: Data(buildingJSON.utf8), parts: Data(partsJSON.utf8)))
    }

    @Test func parsesFloorsInIdOrder() throws {
        let b = try building()
        #expect(b.floors.map(\.id) == [1, 6, 12])
        #expect(b.floors.map(\.name) == ["Lounge", "Desk pool", "claude-bar"])
    }

    @Test func projectFloorsCarryANormalizedRepoRoot() throws {
        let b = try building()
        #expect(b.floor(id: 12)?.repoRoot == Paths.normalize("~/Documents/projects/claude-bar"))
        #expect(b.floor(id: 1)?.repoRoot == nil)
    }

    @Test func texturesAndElevatorComeFromRoomParts() throws {
        let f = try #require(try building().floor(id: 12))
        #expect(f.floorTexture == RoomTexture(id: "slate", image: "assets/room/floors/slate.png", tile: CGSize(width: 1024, height: 528), color: "#6b7280"))
        #expect(f.wallTexture?.id == "plaster")
        #expect(f.elevator?.image == "assets/room/wall-items/elevator.png")
        #expect(f.elevator?.plate == CGRect(x: 80, y: 10, width: 68, height: 21))
        #expect(f.elevator?.plateColor == "#f4ece6")
    }

    @Test func desksKeepStoredOrderAndOrientation() throws {
        let f = try #require(try building().floor(id: 12))
        #expect(f.desks == [FloorDesk(id: "f12-desk-1", design: "s1-walnut", flip: true, rear: false),
                            FloorDesk(id: "f12-desk-2", design: "s3-mint", flip: false, rear: true)])
    }

    @Test func loungeAndDeskPoolAreFound() throws {
        let b = try building()
        #expect(b.lounge?.id == 1 && b.lounge?.isLounge == true && b.lounge?.hasLoungeSign == true)
        #expect(b.deskPool?.id == 6)
    }

    @Test func deskPoolFallsBackToTheFirstSharedFloorAfterTheLounge() throws {
        let json = #"{"floors":[{"id":1,"name":"Lounge","room":{}},{"id":2,"name":"Office","room":{}},{"id":4,"name":"x","repo":{"root":"/r"},"room":{}}]}"#
        let b = try #require(Building.parse(building: Data(json.utf8), parts: Data("{}".utf8)))
        #expect(b.deskPool?.id == 2)
    }

    @Test func brokenDataGivesNilAndTheFallbackIsOneLounge() {
        #expect(Building.parse(building: Data("nope".utf8), parts: Data("{}".utf8)) == nil)
        #expect(Building.fallback.floors.count == 1 && Building.fallback.floors[0].isLounge)
    }
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `cd ~/Documents/projects/claude-bar && swift test --filter BuildingTests 2>&1 | grep -E "error:|passed|failed" | head -3`
Expected: `error: cannot find 'Building' in scope`

- [ ] **Step 3: Write the implementation**

```swift
// Sources/ClaudeBarCore/Building.swift
import CoreGraphics
import Foundation

/// A floor/wall texture from Cat Office's room-parts.json.
public struct RoomTexture: Equatable, Sendable {
    public var id: String
    public var image: String
    public var tile: CGSize
    public var color: String

    public init(id: String, image: String, tile: CGSize, color: String) {
        self.id = id
        self.image = image
        self.tile = tile
        self.color = color
    }
}

/// Wall-item art (the elevator, signs): its image, size and the elevator's number plate.
public struct WallItemArt: Equatable, Sendable {
    public var id: String
    public var image: String
    public var size: CGSize
    public var plate: CGRect?
    public var plateColor: String?
}

/// A desk placed on a floor (building.json room.desks): its design, mirrored, turned.
public struct FloorDesk: Equatable, Sendable {
    public var id: String
    public var design: String
    public var flip: Bool
    public var rear: Bool

    public init(id: String, design: String, flip: Bool, rear: Bool) {
        self.id = id
        self.design = design
        self.flip = flip
        self.rear = rear
    }
}

public struct Floor: Equatable, Sendable, Identifiable {
    public var id: Int
    public var name: String
    /// Normalized project folder for a project floor; nil for shared floors.
    public var repoRoot: String?
    public var floorTexture: RoomTexture?
    public var wallTexture: RoomTexture?
    public var desks: [FloorDesk]
    public var elevator: WallItemArt?
    public var hasLoungeSign: Bool

    /// Floor 1 is the Lounge in Cat Office (src/world/floors.ts LOUNGE_FLOOR).
    public var isLounge: Bool { id == 1 }
}

/// Cat Office's building (public/data/building.json + room-parts.json).
public struct Building: Equatable, Sendable {
    public var floors: [Floor]

    /// Without Cat Office's data: just a Lounge, drawn with ClaudeBar's own room art.
    public static let fallback = Building(floors: [
        Floor(id: 1, name: "Lounge", repoRoot: nil, floorTexture: nil, wallTexture: nil, desks: [], elevator: nil, hasLoungeSign: false),
    ])

    public func floor(id: Int) -> Floor? { floors.first { $0.id == id } }
    public var lounge: Floor? { floors.first(where: \.isLounge) }
    /// The floor named "Desk pool", else the first shared (repo-less) floor other than the Lounge.
    public var deskPool: Floor? {
        floors.first { $0.name == "Desk pool" } ?? floors.first { !$0.isLounge && $0.repoRoot == nil }
    }

    public static func parse(building: Data, parts: Data) -> Building? {
        guard let root = try? JSONSerialization.jsonObject(with: building) as? [String: Any],
              let rawFloors = root["floors"] as? [[String: Any]] else { return nil }
        let partsRoot = (try? JSONSerialization.jsonObject(with: parts) as? [String: Any]) ?? [:]
        func list(_ key: String) -> [[String: Any]] { partsRoot[key] as? [[String: Any]] ?? [] }
        func texture(_ id: String?, in key: String) -> RoomTexture? {
            guard let id, let t = list(key).first(where: { $0["id"] as? String == id }), let image = t["image"] as? String else { return nil }
            let tile = (t["tile"] as? [NSNumber]).map { CGSize(width: $0.first?.doubleValue ?? 1024, height: $0.last?.doubleValue ?? 528) }
            return RoomTexture(id: id, image: image, tile: tile ?? CGSize(width: 1024, height: 528), color: t["color"] as? String ?? "#e3a56c")
        }
        func wallItem(_ id: String) -> WallItemArt? {
            guard let w = list("wallItems").first(where: { $0["id"] as? String == id }), let image = w["image"] as? String else { return nil }
            let n = { (k: String) in (w[k] as? NSNumber)?.doubleValue ?? 0 }
            let plate = (w["plate"] as? [String: Any]).map { p -> CGRect in
                let v = { (k: String) in (p[k] as? NSNumber)?.doubleValue ?? 0 }
                return CGRect(x: v("x"), y: v("y"), width: v("width"), height: v("height"))
            }
            return WallItemArt(id: id, image: image, size: CGSize(width: n("width"), height: n("height")), plate: plate,
                               plateColor: (w["plate"] as? [String: Any])?["color"] as? String)
        }
        let floors = rawFloors.compactMap { f -> Floor? in
            guard let id = (f["id"] as? NSNumber)?.intValue else { return nil }
            let room = f["room"] as? [String: Any] ?? [:]
            let items = (room["wallItems"] as? [[String: Any]] ?? []).compactMap { $0["item"] as? String }
            let desks = (room["desks"] as? [[String: Any]] ?? []).compactMap { d -> FloorDesk? in
                guard let did = d["id"] as? String, let design = d["desk"] as? String else { return nil }
                return FloorDesk(id: did, design: design, flip: d["flip"] as? Bool ?? false, rear: d["rear"] as? Bool ?? false)
            }
            return Floor(
                id: id, name: f["name"] as? String ?? "Floor \(id)",
                repoRoot: ((f["repo"] as? [String: Any])?["root"] as? String).map(Paths.normalize),
                floorTexture: texture(room["floor"] as? String, in: "floors"),
                wallTexture: texture(room["wall"] as? String, in: "walls"),
                desks: desks,
                elevator: items.first { $0.hasPrefix("elevator") }.flatMap(wallItem),
                hasLoungeSign: items.contains { $0.hasPrefix("sign-lounge") })
        }
        guard !floors.isEmpty else { return nil }
        return Building(floors: floors.sorted { $0.id < $1.id })
    }
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `swift test --filter BuildingTests 2>&1 | grep -E "error:|✘|passed|failed" | head -5`
Expected: `✔ Test run with 7 tests passed`

- [ ] **Step 5: Commit**

```bash
git add Sources/ClaudeBarCore/Building.swift Tests/ClaudeBarCoreTests/BuildingTests.swift
git commit -m "feat: parse Cat Office's building (floors, desks, textures, elevator)

Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"
```

### Task 2: Which floor each agent is on

**Files:**
- Create: `Sources/ClaudeBarCore/FloorPlan.swift`
- Test: `Tests/ClaudeBarCoreTests/FloorPlanTests.swift`

**Interfaces:**
- Consumes: `Building`, `Floor` (Task 1); `OfficeAgent` (`status`, `repoRoot`, `cwd`, `isSubagent`, `parentName`, `name`).
- Produces: `public enum FloorPlan { static func floorId(for agent: OfficeAgent, among agents: [OfficeAgent], in building: Building) -> Int? }` (nil = not shown: ended, or no floor at all).

- [ ] **Step 1: Write the failing test**

```swift
// Tests/ClaudeBarCoreTests/FloorPlanTests.swift
import CoreGraphics
import Foundation
import Testing
@testable import ClaudeBarCore

@Suite struct FloorAssignmentTests {
    let building = Building(floors: [
        Floor(id: 1, name: "Lounge", repoRoot: nil, floorTexture: nil, wallTexture: nil, desks: [], elevator: nil, hasLoungeSign: true),
        Floor(id: 4, name: "docs", repoRoot: "/w", floorTexture: nil, wallTexture: nil, desks: [], elevator: nil, hasLoungeSign: false),
        Floor(id: 6, name: "Desk pool", repoRoot: nil, floorTexture: nil, wallTexture: nil, desks: [], elevator: nil, hasLoungeSign: false),
        Floor(id: 12, name: "claude-bar", repoRoot: "/w/claude-bar", floorTexture: nil, wallTexture: nil, desks: [], elevator: nil, hasLoungeSign: false),
    ])

    func agent(_ name: String, _ status: AgentStatus, cwd: String = "/tmp/x", repoRoot: String? = nil, parent: String? = nil) -> OfficeAgent {
        var a = OfficeAgent(id: name, name: name, owner: "office", status: status, cwd: cwd, repoRoot: repoRoot)
        if let parent { a.kind = "subagent"; a.parentName = parent }
        return a
    }

    func floor(_ a: OfficeAgent, _ all: [OfficeAgent] = []) -> Int? { FloorPlan.floorId(for: a, among: all + [a], in: building) }

    @Test func idleGoesToTheLounge() { #expect(floor(agent("a", .idle, repoRoot: "/w/claude-bar")) == 1) }

    @Test func workingAndWaitingGoToTheirProjectFloor() {
        #expect(floor(agent("a", .working, repoRoot: "/w/claude-bar")) == 12)
        #expect(floor(agent("a", .waiting, cwd: "/w/claude-bar/Sources")) == 12, "a subfolder of the project")
    }

    @Test func theMostSpecificRootWins() {
        // /w (floor 4) contains /w/claude-bar (floor 12): the longer root wins.
        #expect(floor(agent("a", .working, repoRoot: "/w/claude-bar")) == 12)
        #expect(floor(agent("a", .working, cwd: "/w/other")) == 4)
    }

    @Test func noProjectGoesToTheDeskPool() { #expect(floor(agent("a", .working, cwd: "/Users/me")) == 6) }

    @Test func helpersFollowTheirParentEvenToTheLounge() {
        let parent = agent("office-p", .idle, repoRoot: "/w/claude-bar")
        let helper = agent("h", .working, repoRoot: "/w/claude-bar", parent: "office-p")
        #expect(floor(helper, [parent]) == 1)
        let busy = agent("office-p", .working, repoRoot: "/w/claude-bar")
        #expect(floor(helper, [busy]) == 12)
    }

    @Test func helpersWithoutAParentInTheOfficeGoToTheDeskPool() {
        #expect(floor(agent("h", .working, repoRoot: "/w/claude-bar", parent: "gone")) == 6)
    }

    @Test func endedIsNotShown() { #expect(floor(agent("a", .ended)) == nil) }
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `swift test --filter FloorAssignmentTests 2>&1 | grep -E "error:" | head -1`
Expected: `error: cannot find 'FloorPlan' in scope`

- [ ] **Step 3: Write the implementation**

```swift
// Sources/ClaudeBarCore/FloorPlan.swift
import CoreGraphics
import Foundation

/// Where cats go in Cat Office's building (src/world/floors.ts, MissionControl.tsx): idle → Lounge; working or
/// waiting → their project's floor (the most specific matching repo root), else the Desk pool; helpers → their
/// parent's floor.
public enum FloorPlan {
    public static func floorId(for agent: OfficeAgent, among agents: [OfficeAgent], in building: Building) -> Int? {
        guard agent.status != .ended else { return nil }
        if agent.isSubagent {
            if let parent = agents.first(where: { $0.name == agent.parentName && !$0.isSubagent && $0.status != .ended }) {
                return floorId(for: parent, among: agents, in: building)
            }
            return building.deskPool?.id ?? building.lounge?.id
        }
        if agent.status == .idle { return building.lounge?.id ?? building.floors.first?.id }
        let place = agent.repoRoot ?? agent.cwd
        let match = building.floors
            .filter { $0.repoRoot.map { Paths.isInside(place, $0) } ?? false }
            .max { ($0.repoRoot?.count ?? 0) < ($1.repoRoot?.count ?? 0) }
        return match?.id ?? building.deskPool?.id ?? building.lounge?.id
    }
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `swift test --filter FloorAssignmentTests 2>&1 | grep -E "error:|✘|passed|failed" | head -5`
Expected: `✔ Test run with 7 tests passed`

- [ ] **Step 5: Commit**

```bash
git add Sources/ClaudeBarCore/FloorPlan.swift Tests/ClaudeBarCoreTests/FloorPlanTests.swift
git commit -m "feat: put each agent on its Cat Office floor

Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"
```

### Task 3: Seating on a floor (desks, helpers, overflow, lounge)

**Files:**
- Modify: `Sources/ClaudeBarCore/FloorPlan.swift`
- Test: `Tests/ClaudeBarCoreTests/FloorPlanTests.swift` (add a suite)

**Interfaces:**
- Consumes: `Floor`, `FloorDesk` (Task 1); `OfficeAgent.desk: AgentDesk?` (id/flip/rear), `isSubagent`, `parentName`, `status`.
- Produces:
  - `public struct FloorSeating: Equatable, Sendable`, with:
    - `desks: [String?]`: the agent id at each of the floor's desks, aligned to `floor.desks`
    - `nearby: [String: [String]]`: parent agent id → helper ids beside it (at most 2)
    - `nearbyOverflow: [String: Int]`
    - `queue: [String]`: at most 3 shown
    - `queueOverflow: Int`
    - `lounge: [String?]`: `FloorSeating.loungeSpots` = 10 entries
    - `loungeOverflow: Int`
  - `public static func FloorPlan.seating(on floor: Floor, agents: [OfficeAgent], previous: FloorSeating?) -> FloorSeating`, where `agents` are the agents on this floor.
  - `public static func FloorPlan.deskPosition(_ index: Int) -> (row: Int, column: Int)`: rows of 6.

- [ ] **Step 1: Write the failing test** (append to `FloorPlanTests.swift`)

```swift
@Suite struct FloorSeatingTests {
    let desks = [
        FloorDesk(id: "d0", design: "s1-walnut", flip: false, rear: false),
        FloorDesk(id: "d1", design: "s2-pink", flip: true, rear: false),
        FloorDesk(id: "d2", design: "s2-pink", flip: true, rear: false),
        FloorDesk(id: "d3", design: "s1-oak", flip: false, rear: false),
    ]
    var floor: Floor { Floor(id: 12, name: "claude-bar", repoRoot: "/w", floorTexture: nil, wallTexture: nil, desks: desks, elevator: nil, hasLoungeSign: false) }
    var lounge: Floor { Floor(id: 1, name: "Lounge", repoRoot: nil, floorTexture: nil, wallTexture: nil, desks: [], elevator: nil, hasLoungeSign: true) }

    func a(_ id: String, _ status: AgentStatus = .working, desk: AgentDesk? = nil, parent: String? = nil) -> OfficeAgent {
        var x = OfficeAgent(id: id, name: id, owner: "office", status: status, cwd: "/w")
        x.desk = desk
        if let parent { x.kind = "subagent"; x.parentName = parent }
        return x
    }

    @Test func catsSitAtTheirReportedDeskDesign() {
        let s = FloorPlan.seating(on: floor, agents: [a("p", desk: AgentDesk(id: "s2-pink", flip: true, rear: false))], previous: nil)
        #expect(s.desks == [nil, "p", nil, nil])
    }

    @Test func twoCatsWithTheSameDesignGetTwoDesks() {
        let pink = AgentDesk(id: "s2-pink", flip: true, rear: false)
        let s = FloorPlan.seating(on: floor, agents: [a("p", desk: pink), a("q", desk: pink)], previous: nil)
        #expect(s.desks == [nil, "p", "q", nil])
    }

    @Test func catsKeepTheirDeskWhileOthersComeAndGo() {
        let first = FloorPlan.seating(on: floor, agents: [a("x"), a("y")], previous: nil)
        #expect(first.desks == ["x", "y", nil, nil])
        let next = FloorPlan.seating(on: floor, agents: [a("y"), a("z")], previous: first)
        #expect(next.desks == ["z", "y", nil, nil], "y stays at d1; z takes the free d0")
    }

    @Test func helpersTakeTheFreeDeskNearestTheirParent() {
        let s = FloorPlan.seating(on: floor, agents: [a("p", desk: AgentDesk(id: "s1-oak", flip: false, rear: false)), a("h", parent: "p")], previous: nil)
        #expect(s.desks == [nil, nil, "h", "p"])
    }

    @Test func helpersStandBesideTheirParentWhenNoDeskIsFree() {
        let agents = [a("p"), a("q"), a("r"), a("s"), a("h1", parent: "p"), a("h2", parent: "p"), a("h3", parent: "p")]
        let s = FloorPlan.seating(on: floor, agents: agents, previous: nil)
        #expect(s.desks == ["p", "q", "r", "s"])
        #expect(s.nearby["p"] == ["h1", "h2"] && s.nearbyOverflow["p"] == 1)
    }

    @Test func otherOverflowQueuesThenCounts() {
        let agents = ["a", "b", "c", "d", "e", "f", "g", "h"].map { a($0) }
        let s = FloorPlan.seating(on: floor, agents: agents, previous: nil)
        #expect(s.desks == ["a", "b", "c", "d"])
        #expect(s.queue == ["e", "f", "g"] && s.queueOverflow == 1)
    }

    @Test func loungeSeatsTenThenCountsAndHelpersSitBesideTheirParent() {
        let cats = (0..<12).map { a("c\($0)", .idle) } + [a("h", .working, parent: "c0")]
        let s = FloorPlan.seating(on: lounge, agents: cats, previous: nil)
        #expect(s.lounge.count == FloorSeating.loungeSpots && s.lounge.compactMap { $0 }.count == 10)
        #expect(s.loungeOverflow == 2)
        #expect(s.nearby["c0"] == ["h"])
    }

    @Test func deskPositionsRunInRowsOfSix() {
        #expect(FloorPlan.deskPosition(0) == (0, 0) && FloorPlan.deskPosition(5) == (0, 5) && FloorPlan.deskPosition(6) == (1, 0))
    }
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `swift test --filter FloorSeatingTests 2>&1 | grep -E "error:" | head -1`
Expected: `error: cannot find 'FloorSeating' in scope`

- [ ] **Step 3: Write the implementation** (append to `FloorPlan.swift`)

```swift
/// Who sits where on one floor.
public struct FloorSeating: Equatable, Sendable {
    public static let loungeSpots = 10
    public static let nearbyShown = 2
    public static let queueShown = 3

    /// The agent id at each of the floor's desks (aligned to Floor.desks).
    public var desks: [String?] = []
    /// Parent agent id → helpers standing beside its desk or seat.
    public var nearby: [String: [String]] = [:]
    public var nearbyOverflow: [String: Int] = [:]
    /// Cats with no desk, standing at the right edge.
    public var queue: [String] = []
    public var queueOverflow = 0
    /// The Lounge's spots (Lounge floor only).
    public var lounge: [String?] = []
    public var loungeOverflow = 0

    public init() {}
}

extension FloorPlan {
    public static func deskPosition(_ index: Int) -> (row: Int, column: Int) { (index / 6, index % 6) }

    public static func seating(on floor: Floor, agents: [OfficeAgent], previous: FloorSeating?) -> FloorSeating {
        var s = FloorSeating()
        let byName = { (x: OfficeAgent, y: OfficeAgent) in x.name.localizedCaseInsensitiveCompare(y.name) == .orderedAscending }
        let mains = agents.filter { !$0.isSubagent }.sorted(by: byName)
        let helpers = agents.filter(\.isSubagent).sorted(by: byName)

        func beside(_ helper: OfficeAgent, _ parentId: String) {
            if (s.nearby[parentId]?.count ?? 0) < FloorSeating.nearbyShown { s.nearby[parentId, default: []].append(helper.id) }
            else { s.nearbyOverflow[parentId, default: 0] += 1 }
        }
        func parentId(of helper: OfficeAgent) -> String? { mains.first { $0.name == helper.parentName }?.id }

        if floor.isLounge {
            s.lounge = StableSlots.assign(mains.map(\.id), previous: previous?.lounge ?? [], count: FloorSeating.loungeSpots)
            s.loungeOverflow = max(0, mains.count - FloorSeating.loungeSpots)
            for h in helpers {
                if let p = parentId(of: h), s.lounge.contains(p) { beside(h, p) }
                else if s.queue.count < FloorSeating.queueShown { s.queue.append(h.id) } else { s.queueOverflow += 1 }
            }
            return s
        }

        var seats = [String?](repeating: nil, count: floor.desks.count)
        let here = Set(agents.map(\.id))
        // 1. Keep last time's desks.
        for (i, id) in (previous?.desks ?? []).prefix(seats.count).enumerated() where id.map(here.contains) == true { seats[i] = id }
        func seated(_ id: String) -> Bool { seats.contains(id) }
        func free(_ i: Int) -> Bool { seats[i] == nil }
        // 2. Main agents: their reported desk design, else the first free desk; else the queue.
        var unseated: [OfficeAgent] = []
        for m in mains where !seated(m.id) {
            if let d = m.desk, let i = floor.desks.indices.first(where: { free($0) && floor.desks[$0].design == d.id && floor.desks[$0].flip == d.flip && floor.desks[$0].rear == d.rear }) {
                seats[i] = m.id
            } else {
                unseated.append(m)
            }
        }
        for m in unseated {
            if let i = seats.indices.first(where: free) { seats[i] = m.id }
            else if s.queue.count < FloorSeating.queueShown { s.queue.append(m.id) } else { s.queueOverflow += 1 }
        }
        // 3. Helpers: the free desk nearest their parent's desk, else beside the parent, else the queue.
        for h in helpers where !seated(h.id) {
            let p = parentId(of: h)
            let parentDesk = p.flatMap { pid in seats.firstIndex(of: pid) }
            let nearest = seats.indices.filter(free).min { x, y in
                guard let pd = parentDesk else { return x < y }
                let (pr, pc) = deskPosition(pd), (xr, xc) = deskPosition(x), (yr, yc) = deskPosition(y)
                return abs(xr - pr) + abs(xc - pc) < abs(yr - pr) + abs(yc - pc)
            }
            if let i = nearest { seats[i] = h.id }
            else if let p, parentDesk != nil { beside(h, p) }
            else if s.queue.count < FloorSeating.queueShown { s.queue.append(h.id) } else { s.queueOverflow += 1 }
        }
        s.desks = seats
        return s
    }
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `swift test --filter FloorSeatingTests 2>&1 | grep -E "error:|✘|passed|failed" | head -5`
Expected: `✔ Test run with 8 tests passed`

- [ ] **Step 5: Commit**

```bash
git add Sources/ClaudeBarCore/FloorPlan.swift Tests/ClaudeBarCoreTests/FloorPlanTests.swift
git commit -m "feat: seat cats on a floor — their desks, helpers near parents, overflow, lounge

Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"
```

### Task 4: Follow target and the busy-floors strip

**Files:**
- Modify: `Sources/ClaudeBarCore/FloorPlan.swift`
- Test: `Tests/ClaudeBarCoreTests/FloorPlanTests.swift` (add a suite)

**Interfaces:**
- Consumes: `FloorPlan.floorId` (Task 2); `attention: Set<String>` (session keys) and `since: [String: Date]` from `AttentionTracker`.
- Produces:
  - `public enum FloorActivity: Equatable, Sendable { case empty, idle, working, needsYou }`
  - `public static func FloorPlan.activity(of building: Building, agents: [OfficeAgent], attention: Set<String>) -> [Int: FloorActivity]`
  - `public static func FloorPlan.cats(on floorId: Int, agents: [OfficeAgent], in building: Building) -> [OfficeAgent]`
  - `public static func FloorPlan.followTarget(building: Building, agents: [OfficeAgent], attention: Set<String>, since: [String: Date], now: Date) -> Int`

- [ ] **Step 1: Write the failing test** (append)

```swift
@Suite struct FollowTests {
    let building = Building(floors: [
        Floor(id: 1, name: "Lounge", repoRoot: nil, floorTexture: nil, wallTexture: nil, desks: [], elevator: nil, hasLoungeSign: true),
        Floor(id: 6, name: "Desk pool", repoRoot: nil, floorTexture: nil, wallTexture: nil, desks: [], elevator: nil, hasLoungeSign: false),
        Floor(id: 10, name: "pnp", repoRoot: "/w/pnp", floorTexture: nil, wallTexture: nil, desks: [], elevator: nil, hasLoungeSign: false),
        Floor(id: 12, name: "claude-bar", repoRoot: "/w/claude-bar", floorTexture: nil, wallTexture: nil, desks: [], elevator: nil, hasLoungeSign: false),
    ])
    let now = Date(timeIntervalSince1970: 1_791_300_000)

    func a(_ id: String, _ status: AgentStatus, _ root: String, waitingSince: Date? = nil) -> OfficeAgent {
        OfficeAgent(id: id, name: id, owner: "office", status: status, cwd: root, repoRoot: root, waitingSince: waitingSince)
    }

    @Test func needsYouWinsNewestFirst() {
        let agents = [a("x", .working, "/w/claude-bar"), a("y", .waiting, "/w/pnp", waitingSince: now - 30), a("z", .waiting, "/w/claude-bar", waitingSince: now - 300)]
        #expect(FloorPlan.followTarget(building: building, agents: agents, attention: [], since: [:], now: now) == 10)
    }

    @Test func thenTheMostRecentStartOrFinishWithinAMinute() {
        let agents = [a("x", .working, "/w/claude-bar"), a("y", .working, "/w/claude-bar"), a("p", .working, "/w/pnp")]
        #expect(FloorPlan.followTarget(building: building, agents: agents, attention: [], since: ["p": now - 5, "x": now - 600], now: now) == 10)
    }

    @Test func thenTheBusiestFloorThenTheLounge() {
        let agents = [a("x", .working, "/w/claude-bar"), a("y", .working, "/w/claude-bar"), a("p", .working, "/w/pnp")]
        #expect(FloorPlan.followTarget(building: building, agents: agents, attention: [], since: [:], now: now) == 12)
        #expect(FloorPlan.followTarget(building: building, agents: [a("i", .idle, "/w/pnp")], attention: [], since: [:], now: now) == 1)
    }

    @Test func attentionCountsAsNeedsYou() {
        let agents = [a("x", .working, "/w/claude-bar"), a("done", .idle, "/w/pnp")]
        #expect(FloorPlan.followTarget(building: building, agents: agents, attention: ["done"], since: ["done": now - 2], now: now) == 1,
                "finished: it went idle, so it's in the Lounge")
    }

    @Test func stripShowsEachFloorsState() {
        let agents = [a("x", .working, "/w/claude-bar"), a("y", .waiting, "/w/pnp"), a("i", .idle, "/w/pnp")]
        let activity = FloorPlan.activity(of: building, agents: agents, attention: [])
        #expect(activity == [1: .idle, 6: .empty, 10: .needsYou, 12: .working])
        #expect(FloorPlan.cats(on: 10, agents: agents, in: building).map(\.id) == ["y"])
    }
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `swift test --filter FollowTests 2>&1 | grep -E "error:" | head -1`
Expected: `error: type 'FloorPlan' has no member 'followTarget'`

- [ ] **Step 3: Write the implementation** (append)

```swift
public enum FloorActivity: Equatable, Sendable { case empty, idle, working, needsYou }

extension FloorPlan {
    /// A start or finish this recent makes Follow go to its floor.
    static let recentChange: TimeInterval = 60

    public static func cats(on floorId: Int, agents: [OfficeAgent], in building: Building) -> [OfficeAgent] {
        agents.filter { floorId == self.floorId(for: $0, among: agents, in: building) }
    }

    public static func activity(of building: Building, agents: [OfficeAgent], attention: Set<String>) -> [Int: FloorActivity] {
        var out: [Int: FloorActivity] = [:]
        for f in building.floors {
            let here = cats(on: f.id, agents: agents, in: building)
            if here.contains(where: { $0.status == .waiting || attention.contains($0.key) }) { out[f.id] = .needsYou }
            else if here.contains(where: { $0.status == .working }) { out[f.id] = .working }
            else { out[f.id] = here.isEmpty ? .empty : .idle }
        }
        return out
    }

    /// Follow: a cat that needs you (newest first), else the most recent start or finish (within a minute), else
    /// the busiest floor, else the Lounge.
    public static func followTarget(building: Building, agents: [OfficeAgent], attention: Set<String>, since: [String: Date], now: Date) -> Int {
        let alive = agents.filter { $0.status != .ended }
        let floorOf = { (a: OfficeAgent) in floorId(for: a, among: agents, in: building) }
        let needy = alive.filter { $0.status == .waiting || attention.contains($0.key) }
            .max { ($0.waitingSince ?? since[$0.key] ?? .distantPast) < ($1.waitingSince ?? since[$1.key] ?? .distantPast) }
        if let needy, let f = floorOf(needy) { return f }
        let recent = alive.compactMap { a in since[a.key].map { (a, $0) } }
            .filter { now.timeIntervalSince($0.1) <= recentChange }
            .max { $0.1 < $1.1 }
        if let (a, _) = recent, let f = floorOf(a) { return f }
        let busy = Dictionary(grouping: alive.filter { $0.status == .working }.compactMap(floorOf), by: { $0 })
            .max { $0.value.count < $1.value.count || ($0.value.count == $1.value.count && $0.key > $1.key) }
        return busy?.key ?? building.lounge?.id ?? building.floors.first?.id ?? 1
    }
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `swift test 2>&1 | grep -E "error:|✘ Test|tests passed|failed" | head -5`
Expected: all tests pass.

- [ ] **Step 5: Commit**

```bash
git add Sources/ClaudeBarCore/FloorPlan.swift Tests/ClaudeBarCoreTests/FloorPlanTests.swift
git commit -m "feat: Follow target and per-floor activity for the floors strip

Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"
```

### Task 5: Load the building, and the floor choice (Follow / manual)

**Files:**
- Modify: `Sources/ClaudeBarCore/ArtCache.swift` (add `building()`)
- Create: `Sources/ClaudeBarCore/FloorChoice.swift`
- Modify: `Sources/ClaudeBar/AppState.swift` (publish `building`, add `followFloor`)
- Test: `Tests/ClaudeBarCoreTests/FloorPlanTests.swift` (add a suite)

**Interfaces:**
- Consumes: `Building.parse` (Task 1), `FloorPlan.followTarget` (Task 4), `ArtCache.json(_:)` (existing, private: add `building()` inside `ArtCache`).
- Produces:
  - `ArtCache.building() async -> Building?`: fetches `data/building.json` and `data/room-parts.json`, cached on disk like `cats.json`.
  - `public struct FloorChoice: Equatable, Sendable` with:
    - `var follow = true`, `var manual: Int?`
    - `func shown(target: Int, floors: [Int]) -> Int`
    - `mutating func pick(_ id: Int)`
    - `mutating func step(_ delta: Int, from shown: Int, floors: [Int])`
    - `mutating func resumeFollow()`
  - `AppState.building: Building` (`@Published`) and `AppState.followFloor: Int`.

- [ ] **Step 1: Write the failing test** (append)

```swift
@Suite struct FloorChoiceTests {
    let floors = [1, 2, 6, 12]

    @Test func followShowsTheTarget() {
        #expect(FloorChoice().shown(target: 12, floors: floors) == 12)
    }

    @Test func pickingAFloorTurnsFollowOff() {
        var c = FloorChoice()
        c.pick(6)
        #expect(!c.follow && c.shown(target: 12, floors: floors) == 6)
        c.resumeFollow()
        #expect(c.follow && c.shown(target: 12, floors: floors) == 12)
    }

    @Test func stepsMoveOneFloorAndStopAtTheEnds() {
        var c = FloorChoice()
        c.step(1, from: 6, floors: floors)
        #expect(c.manual == 12 && !c.follow)
        c.step(1, from: 12, floors: floors)
        #expect(c.manual == 12)
        c.step(-1, from: 1, floors: floors)
        #expect(c.manual == 1)
    }

    @Test func aDeletedFloorFallsBackToFollow() {
        var c = FloorChoice()
        c.pick(9)
        #expect(c.shown(target: 12, floors: floors) == 12, "floor 9 no longer exists")
    }
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `swift test --filter FloorChoiceTests 2>&1 | grep -E "error:" | head -1`
Expected: `error: cannot find 'FloorChoice' in scope`

- [ ] **Step 3: Write the implementation**

```swift
// Sources/ClaudeBarCore/FloorChoice.swift
/// Which floor the Office tab shows: Follow (the default) shows FloorPlan.followTarget; picking a floor (menu, ▲▼,
/// strip) shows that one until Follow is pressed. A picked floor that no longer exists shows the target.
public struct FloorChoice: Equatable, Sendable {
    public var follow = true
    public var manual: Int?

    public init() {}

    public func shown(target: Int, floors: [Int]) -> Int {
        guard !follow, let manual, floors.contains(manual) else { return target }
        return manual
    }

    public mutating func pick(_ id: Int) {
        manual = id
        follow = false
    }

    public mutating func step(_ delta: Int, from shown: Int, floors: [Int]) {
        let sorted = floors.sorted()
        guard let i = sorted.firstIndex(of: shown) else { return }
        pick(sorted[min(sorted.count - 1, max(0, i + delta))])
    }

    public mutating func resumeFollow() {
        follow = true
        manual = nil
    }
}
```

In `ArtCache.swift`, inside `ArtCache` next to `catalog()`:

```swift
    /// Cat Office's building (floors, desks, textures), refreshed when Cat Office answers, else the cached copy.
    public func building() async -> Building? {
        guard let floors = await json("data/building.json"), let parts = await json("data/room-parts.json") else { return nil }
        return Building.parse(building: floors, parts: parts)
    }
```

In `AppState.swift`, next to `@Published private(set) var catIds`:

```swift
    /// Cat Office's floors (the fallback Lounge until it has loaded).
    @Published private(set) var building = Building.fallback

    /// Where Follow points now (FloorPlan.followTarget).
    var followFloor: Int {
        FloorPlan.followTarget(building: building, agents: office?.agents ?? [], attention: attention, since: statusSince, now: Date())
    }

    private func loadBuilding() {
        Task { @MainActor in
            if let b = await art.building(), b != building { building = b }
        }
    }
```

Call `loadBuilding()` at the end of `loadCatalog()`'s task. In `start()`, add a 60s timer `Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in Task { @MainActor in self?.loadBuilding() } }`, since Cat Office adds floors for new projects.

- [ ] **Step 4: Run the tests and the build**

Run: `swift test 2>&1 | grep -E "tests passed|failed" && bash scripts/build.sh 2>&1 | grep -E "error:|Built"`
Expected: all tests pass; `Built build/ClaudeBar.app`.

- [ ] **Step 5: Commit**

```bash
git add Sources/ClaudeBarCore/FloorChoice.swift Sources/ClaudeBarCore/ArtCache.swift Sources/ClaudeBar/AppState.swift Tests/ClaudeBarCoreTests/FloorPlanTests.swift
git commit -m "feat: load Cat Office's building; Follow / manual floor choice

Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"
```

### Task 6: One floor at a time, with the picker

**Files:**
- Create: `Sources/ClaudeBar/FloorSelection.swift`
- Create: `Sources/ClaudeBar/Views/FloorPicker.swift`
- Modify: `Sources/ClaudeBar/Views/OfficePeekView.swift`:
  - `OfficeRoomView` draws one floor
  - `FreeDesk(seat:)`
  - `NearbyHelper`
  - the peek header
- Modify: `Sources/ClaudeBar/Views/DropdownView.swift` (the Office tab adds the picker; `DropdownController` owns a `FloorSelection`)
- Modify: `Sources/ClaudeBar/StatusItemController.swift` (the peek gets an always-follow `FloorSelection`)
- Modify: `Sources/ClaudeBar/RenderPeek.swift` (renders pass a `FloorSelection`)
- Delete: `PeekLayout` use in views (keep the type and its tests: harmless, and `CatMotion` lives in that file)

**Interfaces:**
- Consumes:
  - `FloorPlan.cats(on:agents:in:)`, `FloorPlan.seating(on:agents:previous:)`, `FloorPlan.activity(of:agents:attention:)` (Tasks 3–4)
  - `FloorChoice` and `AppState.building` / `followFloor` (Task 5)
  - existing `CatView`, `DeskStation`, `Lounge`, `RoomBackdrop`, walking
- Produces:
  - `@MainActor final class FloorSelection: ObservableObject { @Published var choice = FloorChoice(); let alwaysFollow: Bool; func shown(_ state: AppState) -> Int }`
  - `struct FloorPicker: View` (needs `FloorSelection` and `AppState` environment objects)
  - `OfficeRoomView` reads `@EnvironmentObject var floors: FloorSelection`

- [ ] **Step 1: Add `FloorSelection`**

```swift
// Sources/ClaudeBar/FloorSelection.swift
import ClaudeBarCore
import SwiftUI

/// The floor shown in one office view. The dropdown's can be picked; the peek's always follows.
@MainActor
final class FloorSelection: ObservableObject {
    @Published var choice = FloorChoice()
    let alwaysFollow: Bool

    init(alwaysFollow: Bool = false) { self.alwaysFollow = alwaysFollow }

    func shown(_ state: AppState) -> Int {
        alwaysFollow ? state.followFloor : choice.shown(target: state.followFloor, floors: state.building.floors.map(\.id))
    }

    /// Follow comes back on each time the dropdown opens.
    func reopen() { choice.resumeFollow() }
}
```

- [ ] **Step 2: Add `FloorPicker`** (option C: menu, ▲▼, Follow, strip)

```swift
// Sources/ClaudeBar/Views/FloorPicker.swift
import ClaudeBarCore
import SwiftUI

/// "12 claude-bar · 3 cats ⌃⌄" menu, ▲ / ▼, Follow, and a strip with one bar per floor.
struct FloorPicker: View {
    @EnvironmentObject var state: AppState
    @EnvironmentObject var floors: FloorSelection

    var body: some View {
        let shown = floors.shown(state)
        let agents = state.office?.agents ?? []
        let activity = FloorPlan.activity(of: state.building, agents: agents, attention: state.attention)
        let ids = state.building.floors.map(\.id)
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 8) {
                Menu {
                    ForEach(state.building.floors) { f in
                        let count = FloorPlan.cats(on: f.id, agents: agents, in: state.building).count
                        Button { floors.choice.pick(f.id) } label: {
                            Text("\(activity[f.id] == .needsYou ? "● " : "")\(f.id) \(f.name)\(count > 0 ? " · \(count)" : "")")
                        }
                    }
                } label: {
                    HStack(spacing: 4) {
                        Text("\(shown)").font(.caption.weight(.bold))
                        Text(state.building.floor(id: shown)?.name ?? "Lounge").font(.callout.weight(.semibold)).lineLimit(1)
                        let count = FloorPlan.cats(on: shown, agents: agents, in: state.building).count
                        Text("· \(count) cat\(count == 1 ? "" : "s")").font(.caption).foregroundStyle(.secondary)
                    }
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
                Button { floors.choice.step(1, from: shown, floors: ids) } label: { Image(systemName: "chevron.up") }
                    .buttonStyle(.borderless).help("Up a floor")
                Button { floors.choice.step(-1, from: shown, floors: ids) } label: { Image(systemName: "chevron.down") }
                    .buttonStyle(.borderless).help("Down a floor")
                Spacer()
                Button { floors.choice.resumeFollow() } label: {
                    Label("Follow", systemImage: "scope").font(.caption)
                        .padding(.horizontal, 8).padding(.vertical, 3)
                        .background(Capsule().fill(floors.choice.follow ? Theme.working.opacity(0.25) : Color.primary.opacity(0.06)))
                }
                .buttonStyle(.plain)
                .help(floors.choice.follow ? "Following where things happen" : "Follow where things happen")
            }
            HStack(spacing: 3) {
                ForEach(state.building.floors) { f in
                    Capsule()
                        .fill(f.id == shown ? Color.primary.opacity(0.6) : color(activity[f.id] ?? .empty))
                        .frame(height: 4)
                        .frame(maxWidth: 30)
                        .contentShape(Rectangle().inset(by: -4))
                        .onTapGesture { floors.choice.pick(f.id) }
                        .help("\(f.id) · \(f.name)")
                }
            }
        }
    }

    private func color(_ a: FloorActivity) -> Color {
        switch a {
        case .needsYou: Theme.waiting
        case .working: Theme.working
        case .idle: Theme.idle.opacity(0.5)
        case .empty: Color.primary.opacity(0.12)
        }
    }
}
```

- [ ] **Step 3: `OfficeRoomView` draws one floor.** In `OfficePeekView.swift`:

(a) Replace the slot state and the `layout`/`slotKey`/`updateSlots`/`DeskSlot`/`deskRow`/`room(_:)` members with:

```swift
    @EnvironmentObject var floors: FloorSelection
    /// Who sits where, per floor, kept between updates so cats keep their desks and seats.
    @State private var seatings: [Int: FloorSeating] = [:]

    private var floorId: Int { floors.shown(state) }
    private var floor: Floor { state.building.floor(id: floorId) ?? Building.fallback.floors[0] }
    private var floorCats: [OfficeAgent] { FloorPlan.cats(on: floorId, agents: state.office?.agents ?? [], in: state.building) }
    /// Changes when who's on the shown floor, or their status or desk, changes.
    private var seatKey: String {
        "\(floorId)|" + floorCats.map { "\($0.id):\($0.status.rawValue):\($0.desk?.id ?? "")" }.sorted().joined(separator: ",")
    }

    private func updateSeating() {
        seatings[floorId] = FloorPlan.seating(on: floor, agents: floorCats, previous: seatings[floorId])
    }

    private func room() -> some View {
        let seating = seatings[floorId] ?? FloorPlan.seating(on: floor, agents: floorCats, previous: nil)
        let byId = Dictionary(floorCats.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        return Group {
            if floor.isLounge {
                Lounge(slots: Array(seating.lounge.prefix(Lounge.spots.count)).map { $0.flatMap { byId[$0] } },
                       overflow: seating.loungeOverflow + seating.lounge.dropFirst(Lounge.spots.count).compactMap { $0 }.count)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            } else {
                deskGrid(seating, byId)
            }
        }
        .padding(.bottom, 8)
        .frame(maxHeight: .infinity, alignment: .bottom)
    }

    /// The floor's own desks in rows of 6 (shrunk to fit two rows), helpers beside their parents, a queue at the right.
    private func deskGrid(_ seating: FloorSeating, _ byId: [String: OfficeAgent]) -> some View {
        let rows = stride(from: 0, to: floor.desks.count, by: 6).map { Array($0..<min($0 + 6, floor.desks.count)) }
        return HStack(alignment: .bottom, spacing: 6) {
            VStack(alignment: .leading, spacing: 2) {
                ForEach(rows, id: \.self) { row in
                    HStack(alignment: .bottom, spacing: 4) {
                        ForEach(row, id: \.self) { i in
                            let seat = floor.desks[i]
                            if let id = seating.desks.indices.contains(i) ? seating.desks[i] : nil, let agent = byId[id] {
                                CatView(agent: agent, atDesk: true, seat: seat).catFrame(agent.id)
                                    .overlay(alignment: .bottomTrailing) {
                                        HStack(spacing: -6) {
                                            ForEach(seating.nearby[id] ?? [], id: \.self) { hid in
                                                if let helper = byId[hid] { NearbyHelper(agent: helper).catFrame(helper.id) }
                                            }
                                            if let more = seating.nearbyOverflow[id] { RoomPill(text: "+\(more)") }
                                        }
                                        .offset(x: 18)
                                    }
                            } else {
                                FreeDesk(seat: seat)
                            }
                        }
                    }
                }
                if floor.desks.isEmpty { RoomPill(text: "No desks on this floor") }
            }
            .scaleEffect(rows.count > 1 ? 0.72 : 1, anchor: .bottomLeading)
            .padding(.leading, 36)
            .frame(maxWidth: .infinity, alignment: .leading)
            if !seating.queue.isEmpty {
                VStack(spacing: 2) {
                    ForEach(seating.queue, id: \.self) { id in
                        if let agent = byId[id] { NearbyHelper(agent: agent).catFrame(agent.id) }
                    }
                    if seating.queueOverflow > 0 { RoomPill(text: "+\(seating.queueOverflow)") }
                }
                .padding(.trailing, 10)
            }
        }
    }
```

(b) In `body`:
- replace `room(PeekLayout.make(office.agents))` with `room()`
- replace `.onChange(of: slotKey, initial: true) { _, _ in updateSlots() }` with:

```swift
        .onChange(of: seatKey, initial: true) { _, _ in updateSeating() }
        .onChange(of: floorId) { _, _ in
            // A different floor: show the whole room and don't walk anyone across from the last floor.
            zoom.reset()
            walks = [:]
            lastFeet = [:]
        }
```

(c) In `startWalks`, change the pruning so it keeps only cats on the shown floor:

```swift
        let here = Set(floorCats.map(\.id))
        lastFeet = lastFeet.filter { here.contains($0.key) }
```

(replacing the `if let agents = state.office?.agents { … }` block).

(d) `CatView` gains `var seat: FloorDesk? = nil`. In its body, when `atDesk`, draw the floor's desk:

```swift
                if atDesk {
                    DeskStation(agent: agent, cat: cat, scene: DeskScene(seated(agent)))
                }
```

with the helper

```swift
    /// The agent as seated at this floor's desk (design, mirrored, turned), so DeskStation draws that desk.
    private func seated(_ agent: OfficeAgent) -> OfficeAgent {
        guard let seat else { return agent }
        var a = agent
        a.desk = AgentDesk(id: seat.design, flip: seat.flip, rear: seat.rear)
        return a
    }
```

and `let scene = DeskScene(seated(agent))` replacing `let scene = DeskScene(agent)`.

(e) Replace `FreeDesk` with a version that draws the floor's desk:

```swift
/// A desk nobody is at: the floor's own desk design, dimmed.
struct FreeDesk: View {
    var seat: FloorDesk?
    @EnvironmentObject var state: AppState
    @Environment(\.officeNight) private var officeNight

    var body: some View {
        VStack(spacing: 1) {
            SpriteImage(key: "desk-\(seat?.design ?? "default")-\(seat?.rear ?? false)", fallback: nil) {
                await state.art.deskImage(id: seat?.design, rear: seat?.rear ?? false)
            }
            .frame(width: 60, height: 53)
            .scaleEffect(x: seat?.flip == true ? -1 : 1, y: 1)
            .colorMultiply(officeNight ? Night.furniture : .white)
            .opacity(0.75)
            .frame(width: 64, height: 64 * 1.34, alignment: .bottom)
            .padding(.bottom, 14)
            RoomPill(text: "free desk").opacity(0.6)
        }
    }
}
```

(f) Add `NearbyHelper`, a helper standing beside its parent at 0.8×, facing front:

```swift
/// A helper with no free desk: standing beside its parent's desk, a little smaller ("working nearby").
struct NearbyHelper: View {
    let agent: OfficeAgent
    @EnvironmentObject var state: AppState
    @Environment(\.officeNight) private var officeNight

    var body: some View {
        let cat = CatPicker.cat(for: agent, catIds: state.catIds)
        SpriteImage(key: "\(cat)-standing-front-left", fallback: Theme.color(agent.status)) {
            await state.art.catImage(cat: cat, pose: .standing, direction: "front-left")
        }
        .frame(width: 40, height: 42)
        .colorMultiply(officeNight ? Night.furniture : .white)
        .help("\(agent.label) · working nearby")
    }
}
```

(g) In `OfficePeekView`'s header, show the floor:

```swift
            HStack(spacing: 6) {
                Text("Cat Office").font(.headline)
                let f = state.building.floor(id: state.followFloor)
                Text("· \(f?.id ?? 1) \(f?.name ?? "Lounge")").font(.callout.weight(.semibold))
                if let office = state.office { OfficeSummary(office: office).font(.callout) }
            }
```

- [ ] **Step 4: Hand out `FloorSelection`s**
  - **`DropdownController`:** add `let floorSelection = FloorSelection()`. Inject it with `.environmentObject(floorSelection)` in the content host's root, and call `floorSelection.reopen()` inside `resetZoom()`, which runs each time the dropdown opens.
  - **`OfficeTabView`:** put `FloorPicker()` above `OfficeRoomView()`, replacing the `OfficeSummary` line.
  - **`StatusItemController`:** add `private let peekFloors = FloorSelection(alwaysFollow: true)` and inject it into the peek's root with `.environmentObject(peekFloors)`.
  - **`DropdownView`** (render-only): add `.environmentObject(FloorSelection())`.
  - **`RenderPeek`:** add `.environmentObject(FloorSelection(alwaysFollow: true))` to both peek render roots. In `TestTabs` and `TestZoom` (which build `DropdownController`), nothing changes, since the controller injects its own.

- [ ] **Step 5: Build, then render the floors**

Run:
```bash
cd ~/Documents/projects/claude-bar && swift test 2>&1 | grep -E "tests passed|failed" && bash scripts/build.sh 2>&1 | grep -E "error:|Built"
CLAUDEBAR_RENDER_SUBAGENT=5 CLAUDEBAR_RENDER_LIGHT=1 build/ClaudeBar.app/Contents/MacOS/ClaudeBar --render-dropdown /tmp/cb-mock/floors-office.png office
CLAUDEBAR_RENDER_LIGHT=1 build/ClaudeBar.app/Contents/MacOS/ClaudeBar --render-peek /tmp/cb-mock/floors-peek.png
```
Expected:
- tests pass and the build succeeds
- the Office tab shows the picker ("12 claude-bar · N cats", ▲▼, Follow, a strip of 12 bars) above the followed floor
- with 5 helpers, the parent sits at its desk and helpers take the free desks nearest it, then stand beside it with "+N"
- the peek header reads "Cat Office · 12 claude-bar …"

Open both images and check them.

- [ ] **Step 6: Click test for the picker** (exact targets only: ▲, ▼, Follow)

Add to `TestTabs` (after the tab clicks, on the Office tab):
1. Find the `FloorPicker`'s ▲ button: use `DropdownController.floorSelection` and read `choice` before and after.
2. Click ▲ (its frame centre, located by walking the content host's accessibility children for the "Up a floor" help tag). If that can't be found, call `floorSelection.choice.step(1, from: shown, floors: ids)` directly and print that the click target wasn't found.
3. Print `choice` after each step: ▲ → `follow false, manual = shown+1`; ▼ → back; Follow → `follow true`.

Run: `(CLAUDEBAR_START_TAB=office build/ClaudeBar.app/Contents/MacOS/ClaudeBar --test-tabs > /tmp/cb-tabtest.log 2>&1 &); sleep 14; pkill -f build/ClaudeBar.app/Contents/MacOS/ClaudeBar; grep -E "floor|clicked" /tmp/cb-tabtest.log`
Expected: the three steps print the expected choices.

- [ ] **Step 7: Install and commit**

```bash
pkill -f "MacOS/ClaudeBar"; sleep 1; rm -rf ~/Applications/ClaudeBar.app && cp -R build/ClaudeBar.app ~/Applications/ && open ~/Applications/ClaudeBar.app
git add -A && git commit -m "feat: Cat Office's floors — one floor at a time, floor menu, ▲▼, Follow and busy strip

Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"
```

---

## Stage 2: each floor's look

### Task 7: Floor textures, the elevator with its number, the Lounge sign, the 10-spot lounge

**Files:**
- Modify: `Sources/ClaudeBar/Views/OfficePeekView.swift`:
  - `RoomBackdrop(floor:)`
  - new `ElevatorArt`
  - new `LoungeFloor` (replaces `Lounge` on floor 1)
  - `Lounge.spots` stays for the fallback building only

**Interfaces:**
- Consumes: `Floor.floorTexture`, `.wallTexture`, `.elevator` (`WallItemArt`: `image`, `size`, `plate`, `plateColor`), `.hasLoungeSign` (Task 1); `ArtCache.image(path:maxPixelSize:)` (existing); `FloorSeating.lounge` (10 entries, Task 3).
- Produces:
  - `RoomBackdrop(floor: Floor)`
  - `ElevatorArt.door() -> CGPoint`: where riders stand, in "roomContent", used by Task 9
  - `LoungeFloor(slots: [OfficeAgent?], overflow: Int)`

- [ ] **Step 1: `RoomBackdrop(floor:)`.** Replace the hard-coded plaster and birch with the floor's textures:

```swift
struct RoomBackdrop: View {
    let floor: Floor
    @EnvironmentObject var state: AppState
    @Environment(\.officeNight) private var officeNight

    /// The back wall's height and where the floor starts (the floor line).
    static let wallHeight: CGFloat = 46

    var body: some View {
        let night = officeNight
        ZStack(alignment: .topLeading) {
            VStack(spacing: 0) {
                texture(floor.wallTexture?.image ?? "assets/room/walls/plaster.png", color: floor.wallTexture?.color ?? "#fdeee0")
                    .frame(height: Self.wallHeight).clipped()
                Rectangle().fill(Color(hex: 0x73503F)).frame(height: 3)
                texture(floor.floorTexture?.image ?? "assets/room/floors/birch.png", color: floor.floorTexture?.color ?? "#eadbc8")
                    .frame(maxHeight: .infinity)
            }
            .colorMultiply(night ? Night.room : .white)
            ElevatorArt(floor: floor).offset(x: ElevatorArt.leading, y: 0)
            if floor.hasLoungeSign {
                roomArt("assets/room/wall-items/sign-lounge.png", size: 512).frame(width: 43, height: 20)
                    .frame(maxWidth: .infinity).offset(y: 12)
                    .colorMultiply(night ? Night.furniture : .white)
            }
            roomArt("assets/room/props/tall-plant.png", size: 480).frame(height: 52).offset(x: ElevatorArt.leading + 64, y: 22)
                .colorMultiply(night ? Night.furniture : .white)
            if night { LampLight() }
            roomArt("assets/room/props/floor-lamp.png", size: 480).frame(height: 64)
                .frame(maxWidth: .infinity, alignment: .trailing).padding(.trailing, 14).offset(y: 12)
                .colorMultiply(night ? Night.furniture : .white)
        }
    }

    /// A texture tiled at Retina scale, on its own colour until it loads.
    private func texture(_ path: String, color: String) -> some View {
        SpriteImage(key: path, fallback: nil, mode: .tile) { await state.art.image(path: path, maxPixelSize: 1024) }
            .background(Color(hexString: color))
    }

    private func roomArt(_ path: String, size: Int) -> some View {
        SpriteImage(key: path, fallback: nil, mode: .fit) { await state.art.image(path: path, maxPixelSize: size) }
    }
}

extension Color {
    /// "#rrggbb" (Cat Office's room-parts colours).
    init(hexString: String) {
        self.init(hex: UInt32(hexString.trimmingCharacters(in: CharacterSet(charactersIn: "#")), radix: 16) ?? 0xEADBC8)
    }
}
```

Update the call site in `OfficeRoomView.body` to `RoomBackdrop(floor: floor)`. In `RenderPeek`'s offline and fallback paths, `floor` falls back to `Building.fallback.floors[0]`.

- [ ] **Step 2: `ElevatorArt`.** The floor's elevator on the back wall with the floor number on its plate:

```swift
/// The floor's elevator (Cat Office's wall item) standing on the floor line at the left of the back wall, with the
/// floor number on its plate (room-parts.json plate rect and colour; font 0.8 × plate height).
struct ElevatorArt: View {
    let floor: Floor
    @EnvironmentObject var state: AppState
    @Environment(\.officeNight) private var officeNight

    static let leading: CGFloat = 8
    static let height: CGFloat = 54

    /// Where riders wait and appear: in front of the door, on the floor.
    static func door() -> CGPoint { CGPoint(x: leading + 26, y: RoomBackdrop.wallHeight + 16) }

    var body: some View {
        if let art = floor.elevator {
            let k = Self.height / art.size.height
            SpriteImage(key: art.image, fallback: nil) { await state.art.image(path: art.image, maxPixelSize: 512) }
                .frame(width: art.size.width * k, height: Self.height)
                .overlay(alignment: .topLeading) {
                    if let plate = art.plate {
                        Text("\(floor.id)")
                            .font(.system(size: max(6, plate.height * k * 0.8), weight: .bold).monospacedDigit())
                            .foregroundStyle(Color(hex: 0x5B4636))
                            .frame(width: plate.width * k, height: plate.height * k)
                            .background(Color(hexString: art.plateColor ?? "#f4ece6"))
                            .offset(x: plate.minX * k, y: plate.minY * k)
                    }
                }
                .colorMultiply(officeNight ? Night.furniture : .white)
                // Standing on the floor line: its foot at the wall's base.
                .offset(y: RoomBackdrop.wallHeight + 3 - Self.height + 6)
        }
    }
}
```

- [ ] **Step 3: `LoungeFloor`.** Ten seats across the whole Lounge:
  - The props and spots are fixed positions in room points: x from the left; y is the feet line, from the top.
  - The spots are: round sofa ×2, sofa ×2, cat bed, bean bag ×2, floor cushion ×2, rug.
  - It reports feet and hover frames like `Lounge`.

```swift
struct LoungeFloor: View {
    let slots: [OfficeAgent?]
    let overflow: Int
    @EnvironmentObject var state: AppState
    @Environment(\.officeNight) private var officeNight

    /// Props: (image, maxPixel, frame in room points).
    static let props: [(String, Int, CGRect)] = [
        ("assets/room/rugs/round-cream.png", 1024, CGRect(x: 160, y: 96, width: 170, height: 70)),
        ("assets/room/props/sofa-round.png", 512, CGRect(x: 100, y: 52, width: 104, height: 70)),
        ("assets/room/props/sofa.png", 512, CGRect(x: 300, y: 52, width: 120, height: 66)),
        ("assets/room/props/cat-bed-blue.png", 384, CGRect(x: 210, y: 128, width: 56, height: 40)),
        ("assets/room/props/bean-bag-cream.png", 384, CGRect(x: 92, y: 118, width: 44, height: 44)),
        ("assets/room/props/bean-bag-brown.png", 384, CGRect(x: 400, y: 118, width: 44, height: 44)),
        ("assets/room/props/floor-cushion-blue.png", 384, CGRect(x: 300, y: 138, width: 40, height: 26)),
        ("assets/room/props/floor-cushion-cream.png", 384, CGRect(x: 350, y: 140, width: 40, height: 26)),
    ]
    /// Feet points for spots 0…9 (seats on the props above, then the rug).
    static let spots: [CGPoint] = [
        CGPoint(x: 135, y: 92), CGPoint(x: 168, y: 92),   // round sofa
        CGPoint(x: 340, y: 90), CGPoint(x: 380, y: 90),   // sofa
        CGPoint(x: 238, y: 158),                         // cat bed
        CGPoint(x: 114, y: 154), CGPoint(x: 422, y: 154), // bean bags
        CGPoint(x: 320, y: 158), CGPoint(x: 370, y: 160), // cushions
        CGPoint(x: 260, y: 128),                         // rug
    ]
    static let catWidth: CGFloat = 40

    var body: some View {
        ZStack(alignment: .topLeading) {
            ForEach(Array(Self.props.enumerated()), id: \.offset) { _, p in
                SpriteImage(key: p.0, fallback: nil) { await state.art.image(path: p.0, maxPixelSize: p.1) }
                    .frame(width: p.2.width, height: p.2.height)
                    .colorMultiply(officeNight ? Night.furniture : .white)
                    .offset(x: p.2.minX, y: p.2.minY)
            }
            ForEach(Array(slots.prefix(Self.spots.count).enumerated()), id: \.offset) { i, agent in
                if let agent {
                    CatView(agent: agent, atDesk: false, width: Self.catWidth, plain: true)
                        .offset(x: Self.spots[i].x - Self.catWidth / 2, y: Self.spots[i].y - Self.catWidth * 0.95 * 0.9)
                }
            }
            RoomPill(text: overflow > 0 ? "lounge · \(slots.compactMap { $0 }.count + overflow) asleep" : "lounge")
                .offset(x: 200, y: 4 + RoomBackdrop.wallHeight + 110)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(GeometryReader { proxy in
            let origin = proxy.frame(in: .named("roomContent")).origin
            Color.clear
                .preference(key: CatFeetKey.self, value: feet(origin))
                .preference(key: CatFramesKey.self, value: frames(origin))
        })
    }

    private func feet(_ o: CGPoint) -> [String: CGPoint] {
        var out: [String: CGPoint] = [:]
        for (i, a) in slots.prefix(Self.spots.count).enumerated() { if let a { out[a.id] = CGPoint(x: o.x + Self.spots[i].x, y: o.y + Self.spots[i].y) } }
        return out
    }

    private func frames(_ o: CGPoint) -> [String: CGRect] {
        var out: [String: CGRect] = [:]
        let w = Self.catWidth, h = w * 0.95
        for (i, a) in slots.prefix(Self.spots.count).enumerated() {
            if let a { out[a.id] = CGRect(x: o.x + Self.spots[i].x - w / 2, y: o.y + Self.spots[i].y - h * 0.9, width: w, height: h) }
        }
        return out
    }
}
```

In `OfficeRoomView.room()`, the Lounge branch becomes:

```swift
                LoungeFloor(slots: seating.lounge.map { $0.flatMap { byId[$0] } }, overflow: seating.loungeOverflow)
```

`CatFramesKey` is `private` in this file, and `LoungeFloor` is in the same file, so it can use it.

- [ ] **Step 4: Build, then render the Lounge, a project floor and the Desk pool, light and dark**

Run:
```bash
cd ~/Documents/projects/claude-bar && bash scripts/build.sh 2>&1 | grep -E "error:|Built"
for mode in "" 1; do CLAUDEBAR_RENDER_LIGHT=$mode build/ClaudeBar.app/Contents/MacOS/ClaudeBar --render-peek /tmp/cb-mock/floor-follow-$mode.png; done
CLAUDEBAR_RENDER_LIGHT=1 build/ClaudeBar.app/Contents/MacOS/ClaudeBar --render-dropdown /tmp/cb-mock/floor-office.png office
```
Expected:
- each floor shows its own wall and floor
- the elevator stands at the left with the floor number on its plate
- the Lounge has the sign and up to 10 sleeping cats on its furniture
- dark mode uses the night look

Open the images and compare against Cat Office's floors.

- [ ] **Step 5: Commit**

```bash
git add -A && git commit -m "feat: each floor's own textures, the elevator with its number, the Lounge sign and 10 seats

Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"
```

---

## Stage 3: the elevator ride

### Task 8: Ride timing

**Files:**
- Create: `Sources/ClaudeBarCore/ElevatorTrip.swift`
- Test: `Tests/ClaudeBarCoreTests/ElevatorTripTests.swift`

**Interfaces:**
- Produces:
  - `public struct ElevatorTrip: Equatable, Sendable { from: Int; to: Int; start: Date; walkIn: TimeInterval; init(from:to:start:walkIn:) }`
  - `public enum ElevatorTrip.Phase: Equatable, Sendable { case walkingIn(Double), boarding(Double), riding, arriving(Double), arrived }`, where the `Double` is progress 0…1 within the phase
  - `func phase(at: Date) -> Phase`
  - `var arrivalTime: Date` (when the fade-in starts on the new floor)
  - `var doneTime: Date`
  - Static timings: `board = 0.35`, `rideBase = 0.7`, `perFloor = 0.35`, `arrive = 0.35`
  - `static func rideTime(floors: Int) -> TimeInterval`
  - `static func waitingOffset(index: Int) -> CGFloat`: −12, 0, +12 for index % 3

- [ ] **Step 1: Write the failing test**

```swift
// Tests/ClaudeBarCoreTests/ElevatorTripTests.swift
import Foundation
import Testing
@testable import ClaudeBarCore

@Suite struct ElevatorTripTests {
    let t0 = Date(timeIntervalSince1970: 1_791_300_000)

    @Test func rideTakesBasePlusPerFloor() {
        #expect(ElevatorTrip.rideTime(floors: 1) == 0.7 + 0.35)
        #expect(abs(ElevatorTrip.rideTime(floors: 11) - (0.7 + 0.35 * 11)) < 1e-9)
    }

    @Test func phasesRunWalkBoardRideArrive() {
        let trip = ElevatorTrip(from: 12, to: 1, start: t0, walkIn: 2)
        #expect(trip.phase(at: t0 + 1) == .walkingIn(0.5))
        if case .boarding(let p) = trip.phase(at: t0 + 2 + 0.175) { #expect(abs(p - 0.5) < 1e-6) } else { Issue.record("not boarding") }
        #expect(trip.phase(at: t0 + 2 + 0.35 + 1) == .riding)
        let ride = ElevatorTrip.rideTime(floors: 11)
        #expect(trip.arrivalTime == t0 + 2 + 0.35 + ride)
        if case .arriving(let p) = trip.phase(at: trip.arrivalTime + 0.175) { #expect(abs(p - 0.5) < 1e-6) } else { Issue.record("not arriving") }
        #expect(trip.phase(at: trip.doneTime + 0.01) == .arrived)
    }

    @Test func waitingCatsStandInThreePlaces() {
        #expect([0, 1, 2, 3].map(ElevatorTrip.waitingOffset) == [-12, 0, 12, -12])
    }
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `swift test --filter ElevatorTripTests 2>&1 | grep -E "error:" | head -1`
Expected: `error: cannot find 'ElevatorTrip' in scope`

- [ ] **Step 3: Write the implementation**

```swift
// Sources/ClaudeBarCore/ElevatorTrip.swift
import CoreGraphics
import Foundation

/// A cat's ride between floors, Cat Office's sequence (simulation-engine.ts:32-34, 1134-1152) at 2× speed: walk to the
/// elevator, board (fade out), ride (base + per floor), arrive (fade in), then walk to its spot (WalkPath).
public struct ElevatorTrip: Equatable, Sendable {
    public static let board: TimeInterval = 0.35
    public static let rideBase: TimeInterval = 0.7
    public static let perFloor: TimeInterval = 0.35
    public static let arrive: TimeInterval = 0.35

    public enum Phase: Equatable, Sendable {
        case walkingIn(Double), boarding(Double), riding, arriving(Double), arrived
    }

    public var from: Int
    public var to: Int
    public var start: Date
    /// How long the walk to the elevator takes (from WalkPath length and the cat's speed).
    public var walkIn: TimeInterval

    public init(from: Int, to: Int, start: Date, walkIn: TimeInterval) {
        self.from = from
        self.to = to
        self.start = start
        self.walkIn = walkIn
    }

    public static func rideTime(floors: Int) -> TimeInterval { rideBase + perFloor * Double(max(1, floors)) }

    /// Cats waiting for the elevator stand in 3 places (Cat Office: (index % 3) - 1).
    public static func waitingOffset(index: Int) -> CGFloat { CGFloat(index % 3 - 1) * 12 }

    public var arrivalTime: Date { start + walkIn + Self.board + Self.rideTime(floors: abs(to - from)) }
    public var doneTime: Date { arrivalTime + Self.arrive }

    public func phase(at now: Date) -> Phase {
        let t = now.timeIntervalSince(start)
        if t < walkIn { return .walkingIn(walkIn > 0 ? t / walkIn : 1) }
        if t < walkIn + Self.board { return .boarding((t - walkIn) / Self.board) }
        if now < arrivalTime { return .riding }
        if now < doneTime { return .arriving(now.timeIntervalSince(arrivalTime) / Self.arrive) }
        return .arrived
    }
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `swift test --filter ElevatorTripTests 2>&1 | grep -E "error:|✘|passed|failed" | head -4`
Expected: `✔ Test run with 3 tests passed`

- [ ] **Step 5: Commit**

```bash
git add Sources/ClaudeBarCore/ElevatorTrip.swift Tests/ClaudeBarCoreTests/ElevatorTripTests.swift
git commit -m "feat: elevator ride timing (walk, board, ride per floor, arrive)

Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"
```

### Task 9: Riders: leaving and arriving

**Files:**
- Modify: `Sources/ClaudeBar/Views/OfficePeekView.swift` (`OfficeRoomView`: track each agent's floor, start trips, draw riders; new `RidersLayer`)

**Interfaces:**
- Consumes:
  - `ElevatorTrip` (Task 8), `ElevatorArt.door()` (Task 7)
  - `FloorPlan.floorId` (Task 2)
  - `WalkPath`, `CatWalk.baseSpeed` and `WalkPath.speed(for:base:)` (existing walking)
  - `WalkersLayer.preload` (existing)
- Produces: `struct Rider { id, agent, trip, walkIn: WalkPath?, waitIndex }` and `struct RidersLayer: View`.
- **Behavior:**
  - **Showing the floor a cat leaves:** it walks from its last feet to the door (offset by its waiting place), fades out facing back-left, and is gone.
  - **Showing the floor it arrives on:**
    - it fades in at the door facing front-right at `arrivalTime`, then walks to its spot with today's walking and hops
    - its spot stays empty until then (it's in `walkingCats`)
  - **Moves within a floor** use today's walking.
  - **Reduce Motion:** no rides.

- [ ] **Step 1: Track floors and start trips.** Add to `OfficeRoomView`:

```swift
    /// Each agent's floor at the last update, to notice floor changes.
    @State private var floorOf: [String: Int] = [:]
    /// Rides in progress, by agent id.
    @State private var rides: [String: Rider] = [:]

    /// Changes when any agent's floor changes.
    private var floorKey: String {
        let agents = state.office?.agents ?? []
        return agents.compactMap { a in FloorPlan.floorId(for: a, among: agents, in: state.building).map { "\(a.id)@\($0)" } }
            .sorted().joined(separator: ",")
    }

    private func noticeFloorChanges() {
        let agents = state.office?.agents ?? []
        var next: [String: Int] = [:]
        for a in agents { if let f = FloorPlan.floorId(for: a, among: agents, in: state.building) { next[a.id] = f } }
        guard !reduceMotion else { floorOf = next; return }
        let now = Date()
        var waiting = 0
        for (id, to) in next {
            guard let from = floorOf[id], from != to, let agent = agents.first(where: { $0.id == id }) else { continue }
            // The walk to the elevator, from where the cat last stood on the shown floor (if it was there).
            let door = ElevatorArt.door()
            let place = CGPoint(x: door.x + ElevatorTrip.waitingOffset(index: waiting), y: door.y)
            let walkIn = from == floorId ? lastFeet[id].map { WalkPath(from: $0, to: place) } : nil
            let speed = WalkPath.speed(for: id, base: CatWalk.baseSpeed)
            let trip = ElevatorTrip(from: from, to: to, start: now, walkIn: TimeInterval((walkIn?.length ?? 0) / speed))
            rides[id] = Rider(id: id, agent: agent, trip: trip, walkIn: walkIn, waitIndex: waiting)
            waiting += 1
            DispatchQueue.main.asyncAfter(deadline: .now() + trip.doneTime.timeIntervalSince(now) + 0.1) {
                if rides[id]?.trip == trip { rides[id] = nil }
            }
        }
        floorOf = next
    }
```

Wire it into `body`:

```swift
        .onChange(of: floorKey, initial: true) { _, _ in noticeFloorChanges() }
```

Add the overlay (next to the walkers overlay):

```swift
            .overlay(alignment: .topLeading) { RidersLayer(rides: Array(rides.values), floorId: floorId, catIds: state.catIds) }
```

and hide riders' spots: `.environment(\.walkingCats, Set(walks.keys).union(arrivingHere))` with

```swift
    /// Cats riding up to the shown floor: their spot stays empty until they've walked out of the elevator.
    private var arrivingHere: Set<String> {
        Set(rides.values.filter { $0.trip.to == floorId && Date() < $0.trip.doneTime }.map(\.id))
    }
```

- [ ] **Step 2: Arrivals walk to their spot.** In `startWalks(to:)`, before computing `from`:

```swift
            // Riding in: it walks out of the elevator once it has arrived, from the door.
            if let ride = rides[id], ride.trip.to == floorId {
                let delay = max(0, ride.trip.doneTime.timeIntervalSince(now))
                let door = ElevatorArt.door()
                DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                    let walk = CatWalk(id: id, agent: ride.agent, path: WalkPath(from: door, to: to), start: Date())
                    walks[id] = walk
                    DispatchQueue.main.asyncAfter(deadline: .now() + walk.duration + CatWalk.hop) {
                        if walks[id]?.start == walk.start { walks[id] = nil }
                    }
                }
                continue
            }
            // Riding out: the rider draws its walk to the elevator.
            if let ride = rides[id], ride.trip.from == floorId { continue }
```

In `.onChange(of: floorId)`, keep `rides` (don't clear them), so Follow switching to the arrival floor shows the arrival.

- [ ] **Step 3: `RidersLayer`** draws the leaving side (walk to the door, then fade out facing back-left) and the arriving side (fade in at the door facing front-right):

```swift
struct Rider: Equatable {
    let id: String
    let agent: OfficeAgent
    let trip: ElevatorTrip
    let walkIn: WalkPath?
    let waitIndex: Int
}

struct RidersLayer: View {
    let rides: [Rider]
    let floorId: Int
    let catIds: [String]
    @EnvironmentObject var state: AppState
    @Environment(\.officeNight) private var officeNight

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30, paused: rides.isEmpty)) { context in
            ZStack(alignment: .topLeading) {
                ForEach(rides, id: \.id) { ride in rider(ride, now: context.date) }
            }
        }
        .allowsHitTesting(false)
    }

    @ViewBuilder
    private func rider(_ ride: Rider, now: Date) -> some View {
        let door = ElevatorArt.door()
        let place = CGPoint(x: door.x + ElevatorTrip.waitingOffset(index: ride.waitIndex), y: door.y)
        switch (ride.trip.phase(at: now), ride.trip.from == floorId, ride.trip.to == floorId) {
        case (.walkingIn, true, _):
            let speed = WalkPath.speed(for: ride.id, base: CatWalk.baseSpeed)
            let d = CGFloat(now.timeIntervalSince(ride.trip.start)) * speed
            let path = ride.walkIn ?? WalkPath(from: place, to: place)
            sprite(ride, feet: path.position(atDistance: d), direction: path.direction(atDistance: d),
                   frame: WalkPath.frame(distance: d, stride: CatWalk.stride, phase: WalkPath.phase(for: ride.id)), alpha: 1)
        case (.boarding(let p), true, _):
            sprite(ride, feet: place, direction: "back-left", frame: 0, alpha: 1 - p)
        case (.arriving(let p), _, true):
            sprite(ride, feet: place, direction: "front-right", frame: 0, alpha: p)
        default:
            EmptyView()
        }
    }

    private func sprite(_ ride: Rider, feet: CGPoint, direction: String, frame: Int, alpha: Double) -> some View {
        let cat = CatPicker.cat(for: ride.agent, catIds: catIds)
        let s = DeskComposition.catScale * DeskStation.scale
        return SpriteImage(key: "walk-\(cat)-\(direction)-\(frame)", fallback: Theme.color(ride.agent.status)) {
            await state.art.walkImage(cat: cat, direction: direction, frame: frame)
        }
        .frame(width: 360 * s, height: 380 * s)
        .colorMultiply(officeNight ? Night.furniture : .white)
        .opacity(alpha)
        .offset(x: feet.x - 180 * s, y: feet.y - 300 * s)
    }
}
```

- [ ] **Step 4: Build, then capture a ride from both sides** (the render-only flip from the walking work: `CLAUDEBAR_RENDER_FLIP_AT` / `CLAUDEBAR_RENDER_FLIP_TO`)

Run:
```bash
cd ~/Documents/projects/claude-bar && bash scripts/build.sh 2>&1 | grep -E "error:|Built"
# A sleeping cat starts work: it leaves the Lounge (peek follows to its project floor → the arrival side).
for t in 0.4 1.2 2.0 3.0; do CLAUDEBAR_RENDER_FLIP_TO=working CLAUDEBAR_RENDER_LIGHT=1 CLAUDEBAR_RENDER_FLIP_AT=5 CLAUDEBAR_RENDER_MIDWALK=$t build/ClaudeBar.app/Contents/MacOS/ClaudeBar --render-peek /tmp/cb-mock/ride-$t.png; done
```
Expected: across the captures:
1. the arrival floor is shown (Follow)
2. the cat fades in at the elevator facing front-right
3. it walks to a desk
4. it types

Open the images and check them. Then capture with `CLAUDEBAR_RENDER_FLIP_TO` unset (working → idle, Follow goes to the Lounge): the cat fades in at the Lounge's elevator and walks to a seat.

- [ ] **Step 5: Install and commit**

```bash
swift test 2>&1 | grep -E "tests passed|failed"
pkill -f "MacOS/ClaudeBar"; sleep 1; rm -rf ~/Applications/ClaudeBar.app && cp -R build/ClaudeBar.app ~/Applications/ && open ~/Applications/ClaudeBar.app
git add -A && git commit -m "feat: cats ride the elevator between floors

Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"
```

### Task 10: Final checks

**Files:**
- Modify: `README.md` (one paragraph on floors), `docs/superpowers/specs/2026-10-07-claudebar-floors-design.md` (Status: Implemented)

- [ ] **Step 1:** `swift test` passes, and `bash scripts/test-statusline.sh` passes all 8 checks.
- [ ] **Step 2:** The tab click test and the zoom test still pass:
  - `--test-tabs`: Projects, Settings, Office and Projects each switch
  - `--test-zoom`: double-click 2×, drag, ⌘-scroll, the 1× pill
- [ ] **Step 3:** Renders:
  - the Lounge, a project floor with 5 helpers, and the Desk pool, light and dark
  - the peek header showing the floor
- [ ] **Step 4:** Add to the README:

```markdown
## Floors

The Office tab and the hover peek show Cat Office's building one floor at a time: idle cats in the Lounge, working
cats on their project's floor (else the Desk pool), helpers beside their parent. The floor menu, ▲▼ and the strip pick
a floor; Follow (on whenever the dropdown opens) shows where things happen. Cats ride the elevator between floors.
```

- [ ] **Step 5:** Commit:

```bash
git add -A && git commit -m "docs: floors in the README; floors spec implemented

Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"
```

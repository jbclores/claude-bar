# ClaudeBar Exact Floors Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Draw each Cat Office floor exactly as that person's Cat Office lays it out, with cats at real desks and seats.
Today ClaudeBar shows simplified rows.

**Architecture:**
- A pure Swift port of Cat Office's room positioning (`RoomGeometry`, in Core) turns a floor's `room` plus Cat Office's
  catalogues into world-pixel placements, spots and depth.
- The port is checked against fixtures produced by Cat Office's own TypeScript.
- A new `FloorScene` view draws the room once into an image per floor. It then draws cats live on top, re-drawing any
  furniture that stands in front of a cat.
- Seating moves from grid rows to the real desks and seat spots.

**Tech Stack:** Swift 6 toolchain (language mode 5), SwiftPM, SwiftUI + AppKit, Swift Testing, macOS 14+. The fixture
script runs Cat Office's TypeScript with its own `tsx`.

**Spec:** `docs/superpowers/specs/2026-10-07-claudebar-exact-floors-design.md`

## Global Constraints

- ClaudeBar draws whatever Cat Office it is connected to. No layout is built in: no floor, desk, prop or Lounge spot may
  be hard-coded.
- Cat Office source for porting and fixtures: `~/Documents/projects/cat-ai-office-with-art-20261006-1038` (call it
  `$CO`). Line references below are to this version.
- **Port steps:** a step that says "port `file.ts:a-b`" means translate those lines literally into Swift: same
  arithmetic, same order, same constants. The fixture tests are the arbiter. This plan writes out every Swift type,
  signature and test in full, and cites the TypeScript for function bodies instead of writing them twice.
- **Units:**
  - All geometry is in Cat Office world pixels (the building is 2752×1536; `catHeight` is 160).
  - Floor points are `(u, v)` with `uvToPx`.
  - Views scale world px to points only at drawing time.
- Fixture tolerance: 0.5 world px for positions and sizes, 1e-4 for floor (u, v), and exact for ids, images, mirroring,
  facings and z order.
- **Fallbacks per spec §4:**
  - a floor without room data, or with geometry that isn't usable → today's simple room for that floor
  - an unknown prop, desk or wall item id → that item is skipped
  - art that fails to load → its colour, or nothing for decorations
- Only a full set of catalogues that parses replaces the cached copy (the same rule as `ArtCache.building()`).
- Walking stays an L-path along the floor axes. No walking grid.
- Every task's verification includes `swift test`. Every UI task also includes `bash scripts/build.sh`.
- Commit messages end with `Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>`.

## Review Focus

1. **A teammate's catalogue has ids this port has never seen** (a newer zip's prop, desk or wall item): only that item
   disappears; the floor still draws and cats still seat. Pinned in Task 2 (`unknownIdsAreSkipped`) and Task 6
   (`unknownPropSkipped`).
2. **Rooms that Cat Office would snap or align on load** (`snapRoomsToCells`, `alignShafts`): ClaudeBar uses stored
   values. The fixture script fails loudly if either would move anything on a fixture building, so drift is never
   silent. Pinned in Task 1.
3. **A floor with no `room`, or degenerate corners** (zero-area parallelogram): that floor falls back to the simple room
   and nothing crashes. Pinned in Task 7 (`degenerateFloorFallsBack`) and Task 9 (render of a fallback floor).
4. **A cat behind a desk or sofa:** the furniture in front is drawn over the cat, and nothing behind is. Pinned in
   Task 7 (`catBehindDeskIsOccluded`) and the Task 10 render.
5. **Name pills on a crowded floor:** no two pills overlap at any zoom, and pills appear at 2×. Pinned in Task 10
   (`pillsNeverOverlap`).

---

## File Structure

| File | Responsibility |
|---|---|
| `scripts/room-fixtures.ts` | Runs Cat Office's room code on a building and writes the expected placements as JSON |
| `Tests/ClaudeBarCoreTests/Fixtures/rooms/` | Input copies (`building.json`, `room-parts.json`, `props.json`, `desks.json`, `wall-item-art.json`) and expected output, for two buildings: `user` and `edge` |
| `Sources/ClaudeBarCore/RoomCatalogue.swift` | Codable defs for floors, walls, rugs, wall items, props and desks; `RoomCatalogue.parse` |
| `Sources/ClaudeBarCore/RoomData.swift` | A floor's base geometry (corners) and `room` (floor, wall, rugs, wallItems, props, desks, wallHeight), parsed from `building.json` |
| `Sources/ClaudeBarCore/RoomGeometry/FloorMath.swift` | `uvToPx`, `pxToUv`, axes, `depthZ`, the floor plane and wall frames |
| `Sources/ClaudeBarCore/RoomGeometry/WallItems.swift` | Wall item sizes, boxes, mirroring, images, window pieces, plate, elevator door and spot |
| `Sources/ClaudeBarCore/RoomGeometry/Desks.swift` | Desk placement, footprint, stand spot, facing, occluder box |
| `Sources/ClaudeBarCore/RoomGeometry/Props.swift` | Prop size, footprint, companions, raised/table, sprite rect, spots, settle orders, rugs |
| `Sources/ClaudeBarCore/RoomGeometry/RoomGeometry.swift` | `BuiltRoom`: one floor fully placed; `catZ`; validity |
| `Sources/ClaudeBarCore/FloorPlan.swift` (modify) | Seating on real desks (nearest by world distance) and Lounge seats from spots |
| `Sources/ClaudeBarCore/ArtCache.swift` (modify) | Loads the catalogues as one set |
| `Sources/ClaudeBar/AppState.swift` (modify) | Holds `RoomCatalogue` and the built rooms |
| `Sources/ClaudeBar/Views/FloorScene.swift` | The room image, the live cat layer, pills, hover frames, walking and riding coordinates |
| `Sources/ClaudeBar/Views/OfficePeekView.swift` (modify) | `OfficeRoomView` uses `FloorScene`, else the simple room |

---

### Task 1: Fixtures from Cat Office's own code

**Files:**
- Create: `scripts/room-fixtures.ts`
- Create: `Tests/ClaudeBarCoreTests/Fixtures/rooms/user/{building,room-parts,props,desks,wall-item-art}.json` (copied
  from `$CO`) and `expected.json`
- Create: `Tests/ClaudeBarCoreTests/Fixtures/rooms/edge/building.json` (hand-made) and `expected.json`
- Modify: `Package.swift`: add `resources: [.copy("Fixtures")]` to the `ClaudeBarCoreTests` target if it isn't there

**Interfaces:**
- Produces: `expected.json` = `{ floors: [ExpectedFloor] }`, used by Tasks 3–7:

```
ExpectedFloor = {
  id, corners: {top,left,bottom,right}, wallHeight, eu, ev,
  floorPlane: { size, a, b, c, d, e, f },
  walls: { left: { length, a, b, e, f }, right: { length, a, b, e, f } },
  rugs: [{ id, rug, image, left, top, width, height, turned }],
  wallItems: [{ id, item, wall, image, mirrored, left, top, width, height, plate: {left,top,width,height} | null }],
  elevators: [{ id, standAt: {u,v}, facing }],
  fixtures: [{ id, image, mirrored, left, top, width, height, z }],
  desks: [{ id, desk, image, flip, rear, left, top, width, height, z, standAt: {u,v}, facing }],
  props: [{ id, prop, image, mirrored, left, top, width, height, z, companionOf, spots: [{ id, kind, pose, u, v, facing, lift }] }]
}
```

- [ ] **Step 1: Write the fixture script**

```ts
// scripts/room-fixtures.ts — run from a Cat Office folder: npx tsx <claude-bar>/scripts/room-fixtures.ts <in-dir> <out.json>
// Reads building.json, room-parts.json, props.json, desks.json (and wall-item-art.json) from <in-dir>, runs Cat Office's
// own room code on them, and writes what ClaudeBar's RoomGeometry must reproduce.
import { readFileSync, writeFileSync } from 'node:fs';
import { join, resolve } from 'node:path';
import { pathToFileURL } from 'node:url';

const co = process.cwd();
const [inDir, outFile] = process.argv.slice(2).map((p) => resolve(p));
const load = (f: string) => JSON.parse(readFileSync(join(inDir, f), 'utf8'));
const mod = (p: string) => import(pathToFileURL(join(co, p)).href);

const { indexParts, roomWallHeight, wallItemSize, wallItemMirrored, wallItemImage, wallBase, wallLength, elevatorSpot } = await mod('src/world/room.ts');
const { buildRoomOffice } = await mod('src/world/room-office.ts');
const { alignShafts } = await mod('src/world/room-shaft.ts');
const { snapRoomsToCells } = await mod('src/world/room-edit.ts');
const { isBuiltRoom } = await mod('src/world/room-parts.ts');
const { roomRugs, placeFixture } = await mod('src/world/room.ts');

const building = load('building.json');
const manifest = load('room-parts.json');
const props = load('props.json');
const desks = load('desks.json').desks;
const parts = indexParts(manifest, props);

let rooms: Record<number, unknown> = {};
for (const f of building.floors) if (isBuiltRoom(f.room)) rooms[f.id] = f.room;
const aligned = alignShafts(building, rooms, parts);
const snapped = snapRoomsToCells(building, aligned.rooms, parts, desks);
if (aligned.moved.length || snapped.moved.length) {
  console.error(`room-fixtures: Cat Office would move rooms on load (aligned ${aligned.moved}, snapped ${snapped.moved}); ClaudeBar uses stored values`);
  process.exit(2);
}
rooms = snapped.rooms;
const office = buildRoomOffice(building, rooms, parts, desks);

const r = (n: number) => Math.round(n * 1000) / 1000;
const out = { floors: [] as unknown[] };
for (const floor of office.building.floors) {
  const room = rooms[floor.id] as any;
  const built = office.rooms[floor.id];
  if (!room || !built) continue;
  const { top, left, right } = floor.corners;
  const eu = Math.hypot(left.x - top.x, left.y - top.y), ev = Math.hypot(right.x - top.x, right.y - top.y);
  const size = (eu + ev) / 2;
  const wallHeight = roomWallHeight(parts, floor.id, room);
  const wall = (side: 'left' | 'right') => {
    const { from, to } = wallBase(floor, side);
    const start = side === 'left' ? to : from, end = side === 'left' ? from : to;
    const length = wallLength(floor, side);
    return { length: r(length), a: r((end.x - start.x) / length), b: r((end.y - start.y) / length), e: r(start.x), f: r(start.y - wallHeight) };
  };
  // RoomShell.tsx Rug (97-119): box in floor-plane px.
  const rugs = roomRugs(floor, room, parts).map((g: any) => {
    const def = parts.rugs.get(g.rug);
    return { id: g.id, rug: g.rug, image: def?.image ?? null, left: r((g.v - g.w / 2) * size), top: r((g.u - g.d / 2) * size), width: r(g.w * size), height: r(g.d * size), turned: !!g.turned };
  });
  // RoomShell.tsx WallItem (269-333): box in the wall frame; plate 315-330.
  const wallItems = room.wallItems.flatMap((item: any) => {
    const def = parts.wallItems.get(item.item);
    if (!def || def.mount === 'sprite') return [];
    const len = wallLength(floor, item.wall);
    const { width, height, bottom } = wallItemSize(def, item, wallHeight);
    const mirrored = wallItemMirrored(item, def);
    const x = (item.wall === 'left' ? 1 - item.at : item.at) * len;
    const left0 = x - width / 2, top0 = bottom - height;
    const plate = def.plate && def.image ? {
      left: r(left0 + (mirrored ? width - def.plate.x - def.plate.width : def.plate.x)), top: r(top0 + def.plate.y),
      width: r(def.plate.width), height: r(def.plate.height) } : null;
    return [{ id: item.id, item: item.item, wall: item.wall, image: wallItemImage(item, def) ?? null, mirrored, left: r(left0), top: r(top0), width: r(width), height: r(height), plate }];
  });
  const elevators = built.elevators.map((e: any) => {
    const s = elevatorSpot(floor, e.item, e.def);
    return { id: e.item.id, standAt: { u: r(s.standAt.u * 1000) / 1000, v: r(s.standAt.v * 1000) / 1000 }, facing: s.facing };
  });
  const fixtures = built.fixtures.map((x: any) => ({ id: x.item.id, image: x.image ?? null, mirrored: !!x.mirrored, left: r(x.rect.left), top: r(x.rect.top), width: r(x.rect.width), height: r(x.rect.height), z: x.box.z }));
  const placedDesks = (office.desks[floor.id] ?? []).map((d: any) => ({
    id: d.placement.id, desk: d.placement.desk, image: d.sprite.image, flip: d.placement.flip, rear: d.rear,
    left: r(d.rect.left), top: r(d.rect.top), width: r(d.rect.width), height: r(d.rect.height), z: d.box.z,
    standAt: { u: r(d.spot.standAt.u * 1000) / 1000, v: r(d.spot.standAt.v * 1000) / 1000 }, facing: d.spot.facing }));
  const placedProps = built.props.map((p: any) => ({
    id: p.placement.id, prop: p.placement.prop, image: p.sprite?.image ?? null, mirrored: p.mirrored,
    left: r(p.rect.left), top: r(p.rect.top), width: r(p.rect.width), height: r(p.rect.height), z: p.box.z, companionOf: p.companionOf ?? null,
    spots: p.spots.map((s: any) => ({ id: s.id, kind: s.kind, pose: s.pose ?? null, u: r(s.standAt.u * 1000) / 1000, v: r(s.standAt.v * 1000) / 1000, facing: s.facing, lift: s.lift ?? 0 })) }));
  out.floors.push({ id: floor.id, corners: floor.corners, wallHeight, eu: r(eu), ev: r(ev),
    floorPlane: { size: r(size), a: r((right.x - top.x) / size), b: r((right.y - top.y) / size), c: r((left.x - top.x) / size), d: r((left.y - top.y) / size), e: top.x, f: top.y },
    walls: { left: wall('left'), right: wall('right') }, rugs, wallItems, elevators, fixtures, desks: placedDesks, props: placedProps });
}
writeFileSync(outFile, JSON.stringify(out, null, 1));
console.log(`room-fixtures: ${out.floors.length} floors → ${outFile}`);
```

Note: `PlacedDesk` names its work spot `spot` (desks.ts:37); `PlacedFixture` has `rect`, `box`, `image`, `mirrored`
(room.ts:880-909). If a field name differs in `$CO`, fix the script to match `$CO` and ledger it. Do not change Cat
Office.

- [ ] **Step 2: Copy the inputs and make the edge building**

```bash
cd ~/Documents/projects/claude-bar
CO=~/Documents/projects/cat-ai-office-with-art-20261006-1038
U=Tests/ClaudeBarCoreTests/Fixtures/rooms/user; E=Tests/ClaudeBarCoreTests/Fixtures/rooms/edge
mkdir -p $U $E
cp $CO/public/data/{building,room-parts,props,desks}.json $U/ && cp $CO/src/world/wall-item-art.json $U/
cp $U/{room-parts,props,desks,wall-item-art}.json $E/
```

Write `$E/building.json`: floors 1 and 2 copied from the user building, plus floor 3, a copy of floor 2 with these
changes:
- `"desks": []`
- every prop with `"facing": 1`
- the wide window `window-2-2` with `"width": 700`
- `"wallHeight": 480`

It's a hand-made JSON object, `{ "width": 2752, "height": 1536, "catHeight": 160, "floors": [ … ] }`, produced by this
one-off command, so it stays exact:

```bash
python3 -I - <<'PY'
import json
b = json.load(open("Tests/ClaudeBarCoreTests/Fixtures/rooms/user/building.json"))
f1, f2 = b["floors"][0], b["floors"][1]
f3 = json.loads(json.dumps(f2)); f3["id"] = 3; f3["name"] = "Edge"
f3["room"]["desks"] = []; f3["room"]["wallHeight"] = 480
for p in f3["room"]["props"]: p["facing"] = 1
for w in f3["room"]["wallItems"]:
    if w["id"] == "window-2-2": w["width"] = 700
json.dump({**{k: b[k] for k in ("width", "height", "catHeight")}, "floors": [f1, f2, f3]},
          open("Tests/ClaudeBarCoreTests/Fixtures/rooms/edge/building.json", "w"), indent=1)
PY
```

- [ ] **Step 3: Run the script for both buildings**

```bash
cd ~/Documents/projects/cat-ai-office-with-art-20261006-1038
for b in user edge; do npx tsx ~/Documents/projects/claude-bar/scripts/room-fixtures.ts ~/Documents/projects/claude-bar/Tests/ClaudeBarCoreTests/Fixtures/rooms/$b ~/Documents/projects/claude-bar/Tests/ClaudeBarCoreTests/Fixtures/rooms/$b/expected.json; done
```
Expected: `room-fixtures: 12 floors → …/user/expected.json` and `room-fixtures: 3 floors → …/edge/expected.json`.
Exit code 2 means Cat Office would snap or align these rooms; stop and ledger a ruling (Review Focus 2).

- [ ] **Step 4: Check the fixtures**

Run: `python3 -I -c "import json;e=json.load(open('Tests/ClaudeBarCoreTests/Fixtures/rooms/user/expected.json'));f=e['floors'][1];print(f['id'],len(f['desks']),len(f['props']),len(f['wallItems']),f['elevators'])"`
Expected: `2 11 <≥9> 5 [{'id': 'elevator-2', …}]`.

- [ ] **Step 5: Commit**

```bash
git add scripts/room-fixtures.ts Tests/ClaudeBarCoreTests/Fixtures Package.swift
git commit -m "test: room fixtures from Cat Office's own code

Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"
```

---

### Task 2: Catalogues and room data

**Files:**
- Create: `Sources/ClaudeBarCore/RoomCatalogue.swift`, `Sources/ClaudeBarCore/RoomData.swift`
- Modify: `Sources/ClaudeBarCore/Building.swift`: `Floor` gains `corners: FloorCorners?` and `room: FloorRoom?`, and
  `FloorDesk` gains `u, v`
- Test: `Tests/ClaudeBarCoreTests/RoomCatalogueTests.swift`, plus `TestSupport.swift` (`fixture(_:)`)

**Interfaces:**
- Produces:
  - `public struct WorldPoint: Codable, Equatable, Sendable { public var x, y: Double }` (named so it doesn't clash
    with CGPoint)
  - `public struct FloorPoint: Codable, Equatable, Sendable { public var u, v: Double }`
  - `public struct FloorCorners: Codable, Equatable, Sendable { public var top, left, bottom, right: WorldPoint }`
  - `public struct FloorRoom: Codable, Equatable, Sendable { floor: String; wall: String; wallHeight: Double?; rugs: [RugPlacement]; wallItems: [WallItemPlacement]; props: [PropPlacement]; desks: [DeskPlacement] }`
  - `RugPlacement { id, rug: String; u, v, w, d: Double; turned: Bool? }`
  - `WallItemPlacement { id, item: String; wall: WallSide; at: Double; width, height, bottom, up: Double?; transom: Bool? }`
  - `PropPlacement { id, prop: String; u, v: Double; facing: Int; decor: Bool?; panels: Int?; companionsOff: Bool? }`
  - `DeskPlacement { id, desk: String; u, v: Double; flip: Bool; rear: Bool? }`
  - `public enum WallSide: String, Codable, Sendable { case left, right }`
  - `public struct ArtBounds: Codable, Equatable, Sendable { l, t, r, b: Double }` with `static let whole = ArtBounds(l: 0, t: 0, r: 1, b: 1)`
  - `WallItemDef`: every field `room.ts` and `RoomShell.tsx` read, all optional except `id`, `width`, `height`:
    - `image`, `imageRight`, `mirror`, `drawnFor`, `resizable`, `fullHeight`, `top`, `floorGap`, `art`, `artRight`
    - `plate {x, y, width, height, color}`, `doorway: [Double]`, `standOut`, `seat: [Double]`, `seatDepth`
    - `mount`, `anchor: WorldPoint?`, `reach`
    - `frame`, `mullion`, `slice {left, right, top, bottom}`, `paneWidth`, `mullionWidth`
    - `glassLeft`, `glassRight`, `glassTop`, `glassBottom`, `glass`, `skyline`, `skylineHeight`
    - `transom`, `transomHeight`, `transomAt`, `transomOptional`, `sill`, `color`
  - `PropDef`: `id, image?, width?, height?, anchor?: WorldPoint, length, depth, mirror?, cells?, rear?: PropSprite, panels?: PanelDef, raised?: Double, placeOn?: String, companions?: [CompanionDef], spots?: [PropSpotDef], slots?: [PropSpotDef], cover?: [WorldPoint], facings?: [Int]`
  - `PropSprite { image: String; width, height: Double; anchor: WorldPoint }`
  - `PanelDef { default: Int; step: Double; min: Int?; max: Int?; sizes: [String: PropSprite]? }`
  - `CompanionDef { prop: String?; rug: String?; du, dv: Double; along: Double?; across: Double? }`
  - `PropSpotDef { id?: String; kind: String; pose: String?; stand: SpotOffset; facing: String; capacity: Int?; lift: Double?; optional: Bool? }`
  - `SpotOffset { dx, dy: Double }`
  - `DeskDef { id, image: String; width, height: Double; anchor: WorldPoint; length, depth: Double; stand: SpotOffset; rear: PropSprite? }`
  - `RugDef { id, image: String; shape: String? }`, `SurfaceMaterial { id, image: String; tile: [Double]?; color: String }`,
    `WallMaterial { id, image: String; tile: [Double]?; color: String; slice: SliceDef? }`
  - `public struct RoomCatalogue: Equatable, Sendable { wallHeight: Double; wallHeights: [String: Double]; floors: [String: SurfaceMaterial]; walls: [String: WallMaterial]; rugs: [String: RugDef]; wallItems: [String: WallItemDef]; props: [String: PropDef]; desks: [String: DeskDef] }`
  - `public static func parse(roomParts: Data, props: Data, desks: Data, wallItemArt: Data?) -> RoomCatalogue?`:
    - nil when any of the three required files doesn't parse
    - `wallItemArt` merged as `withArt` does (room.ts:54-65)
    - entries that don't decode are dropped one by one, never the whole file
  - `public func wallHeight(floorId: Int, room: FloorRoom) -> Double`: room.ts:149-160

- [ ] **Step 1: Write the failing tests**

```swift
// Tests/ClaudeBarCoreTests/RoomCatalogueTests.swift
import Foundation
import Testing
@testable import ClaudeBarCore

@Suite struct RoomCatalogueTests {
    func catalogue(_ b: String = "user") throws -> RoomCatalogue {
        try #require(RoomCatalogue.parse(roomParts: fixture("rooms/\(b)/room-parts.json"), props: fixture("rooms/\(b)/props.json"),
                                         desks: fixture("rooms/\(b)/desks.json"), wallItemArt: fixture("rooms/\(b)/wall-item-art.json")))
    }

    @Test func parsesTheUsersCatalogues() throws {
        let c = try catalogue()
        #expect(c.desks["s1-walnut"]?.stand == SpotOffset(dx: -110, dy: -20))
        #expect(c.props["sofa"]?.spots?.filter { $0.pose == "sit" }.count == 3)
        #expect(c.wallItems["elevator"]?.plate != nil)
        #expect(c.wallItems["wall-tv"]?.art != nil, "art bounds merged from wall-item-art.json")
        #expect(c.floors["oak"]?.image == "assets/room/floors/oak.png")
    }

    @Test func wallHeightPerFloor() throws {
        let c = try catalogue()
        let b = try #require(Building.parse(building: fixture("rooms/user/building.json"), parts: fixture("rooms/user/room-parts.json")))
        #expect(c.wallHeight(floorId: 1, room: try #require(b.floor(id: 1)?.room)) == 432)
        #expect(c.wallHeight(floorId: 2, room: try #require(b.floor(id: 2)?.room)) == 399)
    }

    @Test func unknownIdsAreSkipped() throws {
        var props = try JSONSerialization.jsonObject(with: fixture("rooms/user/props.json")) as! [String: Any]
        var list = props["props"] as! [[String: Any]]
        list.append(["id": "hovercraft", "width": "not a number"])
        props["props"] = list
        let c = try #require(RoomCatalogue.parse(roomParts: fixture("rooms/user/room-parts.json"),
                                                 props: JSONSerialization.data(withJSONObject: props),
                                                 desks: fixture("rooms/user/desks.json"), wallItemArt: nil))
        #expect(c.props["hovercraft"] == nil && c.props["sofa"] != nil)
    }

    @Test func brokenRequiredFileGivesNil() throws {
        #expect(RoomCatalogue.parse(roomParts: Data("<html>".utf8), props: try fixture("rooms/user/props.json"),
                                    desks: try fixture("rooms/user/desks.json"), wallItemArt: nil) == nil)
    }

    @Test func floorsKeepCornersRoomAndDeskPositions() throws {
        let b = try #require(Building.parse(building: fixture("rooms/user/building.json"), parts: fixture("rooms/user/room-parts.json")))
        let f2 = try #require(b.floor(id: 2))
        #expect(f2.corners?.top == WorldPoint(x: 1375, y: 271))
        #expect(f2.room?.desks.count == 11 && f2.room?.wallItems.first?.wall == .left)
        #expect(f2.desks.first.map { ($0.u, $0.v) } ?? (0, 0) == (0.1178, 0.4328))
    }
}
```

Add to `TestSupport.swift`:

```swift
/// A file under Tests/ClaudeBarCoreTests/Fixtures.
func fixture(_ path: String) throws -> Data {
    let url = try #require(Bundle.module.url(forResource: "Fixtures/" + path, withExtension: nil))
    return try Data(contentsOf: url)
}
```

(`#require` needs `import Testing` in TestSupport.swift; add it if missing.)

- [ ] **Step 2: Run them to verify they fail**

Run: `swift test --filter RoomCatalogueTests 2>&1 | grep -E "error:" | head -2`
Expected: `cannot find 'RoomCatalogue' in scope`

- [ ] **Step 3: Implement**
  - The types above, as `Codable` structs.
  - `parse` decodes each catalogue's list element by element: decode `[JSONValue]`-style raw objects with
    `JSONSerialization`, then re-encode each and decode it with `JSONDecoder`, keeping the ones that succeed.
  - `withArt` is a literal port of room.ts:54-65.
  - `wallHeight` is a port of room.ts:149-160.
  - In `Building.parse`:
    - read `corners` and `room` per floor with `JSONDecoder` (a failed `room` → nil, which means the fallback)
    - read `u` and `v` into `FloorDesk`
  - Keep every existing `Building` behaviour; `BuildingTests` must stay green.

- [ ] **Step 4: Run them to verify they pass**

Run: `swift test 2>&1 | grep -E "error:|tests passed|failed after" | tail -2`
Expected: all pass.

- [ ] **Step 5: Commit** — `feat: parse Cat Office's room catalogues and each floor's room`

---

### Task 3: Floor math, floor plane, walls

**Files:**
- Create: `Sources/ClaudeBarCore/RoomGeometry/FloorMath.swift`
- Test: `Tests/ClaudeBarCoreTests/RoomGeometryTests.swift` (the shared `expected(_:)` loader lives here)

**Interfaces:**
- Produces:
  - `public struct FloorFrame: Equatable, Sendable { corners: FloorCorners; eu, ev: Double }`, with:
    - `init?(corners:)`: nil when the parallelogram's area is under 1 px²
    - `func px(_ p: FloorPoint) -> WorldPoint`: floor-math.ts:4-10
    - `func uv(_ p: WorldPoint) -> FloorPoint`: floor-math.ts:42-52
    - `var plane: (size: Double, transform: CGAffineTransform)`: RoomShell.tsx:35-40, as the affine transform for the
      size×size box
    - `func wall(_ side: WallSide, height: Double) -> (length: Double, transform: CGAffineTransform)`: RoomShell.tsx:47-57
      plus room.ts:104-113, transforming the length×height box
    - `func wallPoint(_ side: WallSide, at: Double, up: Double) -> WorldPoint`: room.ts:116-119
    - `func outUnit(_ side: WallSide) -> Double`: room.ts:127-130
  - `public static func depthZ(_ uv: Double) -> Int`: occlusion.ts:4, `10 + round(uv * 10000)`, rounding like JS
    `Math.round` (half up: `Int((x + 0.5).rounded(.down))`)
  - `public static func wallFloorPoint(_ side: WallSide, at: Double, out: Double) -> FloorPoint`: room.ts:122-124
  - `public struct Footprint: Equatable, Sendable { u0, u1, v0, v1: Double }`
  - `public struct OccluderBox: Equatable, Sendable { front: FloorPoint; rect: CGRect; back: Double; z: Int }`, with
    `static func make(front: FloorPoint, rect: CGRect, back: Double?) -> OccluderBox`: occlusion.ts:28-30

- [ ] **Step 1: Write the failing tests**

```swift
// Tests/ClaudeBarCoreTests/RoomGeometryTests.swift
import CoreGraphics
import Foundation
import Testing
@testable import ClaudeBarCore

struct Expected: Decodable {
    struct Floor: Decodable {
        struct Plane: Decodable { let size, a, b, c, d, e, f: Double }
        struct Wall: Decodable { let length, a, b, e, f: Double }
        struct UV: Decodable { let u, v: Double }
        struct Rug: Decodable { let id, rug: String; let image: String?; let left, top, width, height: Double; let turned: Bool }
        struct Plate: Decodable { let left, top, width, height: Double }
        struct WallItem: Decodable { let id, item, wall: String; let image: String?; let mirrored: Bool; let left, top, width, height: Double; let plate: Plate? }
        struct Elevator: Decodable { let id: String; let standAt: UV; let facing: String }
        struct Fixture: Decodable { let id: String; let image: String?; let mirrored: Bool; let left, top, width, height: Double; let z: Int }
        struct Desk: Decodable { let id, desk, image: String; let flip, rear: Bool; let left, top, width, height: Double; let z: Int; let standAt: UV; let facing: String }
        struct Spot: Decodable { let id, kind: String; let pose: String?; let u, v: Double; let facing: String; let lift: Double }
        struct Prop: Decodable { let id, prop: String; let image: String?; let mirrored: Bool; let left, top, width, height: Double; let z: Int; let companionOf: String?; let spots: [Spot] }
        let id: Int; let corners: FloorCorners; let wallHeight, eu, ev: Double
        let floorPlane: Plane; let walls: [String: Wall]
        let rugs: [Rug]; let wallItems: [WallItem]; let elevators: [Elevator]; let fixtures: [Fixture]; let desks: [Desk]; let props: [Prop]
    }
    let floors: [Floor]
}

func expected(_ b: String) throws -> Expected { try JSONDecoder().decode(Expected.self, from: fixture("rooms/\(b)/expected.json")) }
func near(_ a: Double, _ b: Double, _ tol: Double = 0.5) -> Bool { abs(a - b) <= tol }

@Suite struct FloorMathTests {
    @Test(arguments: ["user", "edge"]) func planeAndWallsMatchCatOffice(_ b: String) throws {
        for e in try expected(b).floors {
            let f = try #require(FloorFrame(corners: e.corners))
            #expect(near(f.eu, e.eu) && near(f.ev, e.ev))
            let p = f.plane
            #expect(near(p.size, e.floorPlane.size))
            #expect(near(p.transform.a, e.floorPlane.a, 1e-3) && near(p.transform.b, e.floorPlane.b, 1e-3))
            #expect(near(p.transform.c, e.floorPlane.c, 1e-3) && near(p.transform.d, e.floorPlane.d, 1e-3))
            #expect(near(p.transform.tx, e.floorPlane.e) && near(p.transform.ty, e.floorPlane.f))
            for side in [WallSide.left, .right] {
                let w = f.wall(side, height: e.wallHeight), x = try #require(e.walls[side.rawValue])
                #expect(near(w.length, x.length) && near(w.transform.a, x.a, 1e-3) && near(w.transform.b, x.b, 1e-3))
                #expect(near(w.transform.tx, x.e) && near(w.transform.ty, x.f))
            }
        }
    }

    @Test func uvRoundTrips() throws {
        let f = try #require(FloorFrame(corners: try expected("user").floors[1].corners))
        let p = FloorPoint(u: 0.3, v: 0.7)
        let back = f.uv(f.px(p))
        #expect(near(back.u, 0.3, 1e-9) && near(back.v, 0.7, 1e-9))
    }

    @Test func degenerateCornersGiveNoFrame() {
        let z = WorldPoint(x: 5, y: 5)
        #expect(FloorFrame(corners: FloorCorners(top: z, left: z, bottom: z, right: z)) == nil)
    }

    @Test func depthRoundsLikeJavaScript() {
        #expect(FloorFrame.depthZ(0.00005) == 11)
        #expect(FloorFrame.depthZ(1.2345) == 12355)
    }
}
```

- [ ] **Step 2: Run it to verify it fails** — `swift test --filter FloorMathTests`. Expected: `cannot find 'FloorFrame'`.
- [ ] **Step 3: Implement by porting the cited lines.** `CGAffineTransform(a:b:c:d:tx:ty:)` maps the same way as
  CSS `matrix(a,b,c,d,e,f)`.
- [ ] **Step 4: Run them to verify they pass** — `swift test 2>&1 | grep -E "tests passed|failed after" | tail -1`
- [ ] **Step 5: Commit** — `feat: room floor math, floor plane and walls (matches Cat Office)`

---

### Task 4: Wall items, windows, elevator

**Files:**
- Create: `Sources/ClaudeBarCore/RoomGeometry/WallItems.swift`
- Test: append `WallItemTests` to `Tests/ClaudeBarCoreTests/RoomGeometryTests.swift`

**Interfaces:**
- Consumes: `FloorFrame`, `RoomCatalogue`, `WallItemPlacement`, `WallItemDef`
- Produces:
  - `public struct PlacedWallItem: Equatable, Sendable`:
    - `id, item: String; wall: WallSide; image: String?; mirrored: Bool`
    - `box: CGRect` (in the wall frame's local px)
    - `plate: CGRect?`
    - `pieces: [WindowPiece]`
    - `isElevator: Bool`
  - `public enum WindowPiece: Equatable, Sendable { case nineSlice(image: String, rect: CGRect, slice: SliceDef), stretch(image: String, rect: CGRect), repeatX(image: String, rect: CGRect), fill(color: String, rect: CGRect) }`:
    - rects are local to the item box
    - an empty list means "draw `image` over the box"
  - `public struct ElevatorSpot: Equatable, Sendable { id: String; wall: WallSide; standAt: FloorPoint; facing: String }`
  - `public enum WallItems`:
    - `static func place(_ item: WallItemPlacement, frame: FloorFrame, catalogue: RoomCatalogue, wallHeight: Double) -> PlacedWallItem?`:
      nil for an unknown id or `mount == "sprite"`
    - `static func elevatorSpot(_ item: WallItemPlacement, frame: FloorFrame, catalogue: RoomCatalogue) -> ElevatorSpot?`:
      room.ts:340-362
    - `static func fixture(_ item: WallItemPlacement, frame: FloorFrame, catalogue: RoomCatalogue, wallHeight: Double) -> PlacedFixture?`:
      room.ts:886-909 for `mount == "sprite"`
  - `public struct PlacedFixture: Equatable, Sendable { id: String; image: String?; mirrored: Bool; rect: CGRect; box: OccluderBox }`
- Port:
  - room.ts:168-230: `wallItemWidth`, `wallItemSize`, `wallItemRaisable`, `upRange`, `clampUp`, `wallItemUp`, and
    `WHOLE`/`WALL_TOP_MARGIN_PX = 26`
  - room.ts:324-332: `wallItemMirrored`, `wallItemImage`
  - the RoomShell.tsx:269-333 box and plate
  - RoomShell.tsx:122-147 and 182-255 for `pieces`: `glassOf`, `mullionsOf`, `nineSlice`, `WindowArt`, in the drawing
    order there (normal: frame, mullions, decor; full: sky, skyline, mullions, transom, frame)
  - the `sill` clip (RoomShell 282) as a shorter box height

- [ ] **Step 1: Write the failing tests**

```swift
@Suite struct WallItemTests {
    @Test(arguments: ["user", "edge"]) func wallItemsMatchCatOffice(_ b: String) throws {
        let c = try RoomCatalogueTests().catalogue(b)
        let building = try #require(Building.parse(building: fixture("rooms/\(b)/building.json"), parts: fixture("rooms/\(b)/room-parts.json")))
        for e in try expected(b).floors {
            let floor = try #require(building.floor(id: e.id)), room = try #require(floor.room)
            let frame = try #require(FloorFrame(corners: e.corners))
            let placed = room.wallItems.compactMap { WallItems.place($0, frame: frame, catalogue: c, wallHeight: e.wallHeight) }
            #expect(placed.map(\.id) == e.wallItems.map(\.id))
            for (p, x) in zip(placed, e.wallItems) {
                #expect(p.image == x.image && p.mirrored == x.mirrored, "\(x.id)")
                #expect(near(p.box.minX, x.left) && near(p.box.minY, x.top) && near(p.box.width, x.width) && near(p.box.height, x.height), "\(x.id)")
                #expect((p.plate == nil) == (x.plate == nil))
                if let pp = p.plate, let xp = x.plate { #expect(near(pp.minX, xp.left) && near(pp.minY, xp.top)) }
            }
            let spots = room.wallItems.compactMap { WallItems.elevatorSpot($0, frame: frame, catalogue: c) }
            #expect(spots.map(\.id) == e.elevators.map(\.id))
            for (s, x) in zip(spots, e.elevators) {
                #expect(near(s.standAt.u, x.standAt.u, 1e-3) && near(s.standAt.v, x.standAt.v, 1e-3) && s.facing == x.facing)
            }
            let fixtures = room.wallItems.compactMap { WallItems.fixture($0, frame: frame, catalogue: c, wallHeight: e.wallHeight) }
            #expect(fixtures.count == e.fixtures.count)
            for (f, x) in zip(fixtures, e.fixtures) { #expect(near(f.rect.minX, x.left) && near(f.rect.minY, x.top) && f.box.z == x.z) }
        }
    }

    @Test func fullWindowHasSkyMullionsTransomAndFrame() throws {
        let c = try RoomCatalogueTests().catalogue()
        let frame = try #require(FloorFrame(corners: try expected("user").floors[1].corners))
        let w = WallItemPlacement(id: "w", item: "window-lounge-full", wall: .right, at: 0.21, width: 560, height: 127, bottom: 189, up: nil, transom: nil)
        let p = try #require(WallItems.place(w, frame: frame, catalogue: c, wallHeight: 399))
        guard case .stretch = p.pieces.first, case .nineSlice = p.pieces.last else { Issue.record("sky first, frame last: \(p.pieces)"); return }
        #expect(p.pieces.count >= 4)
    }

    @Test func unknownWallItemIsSkipped() throws {
        let c = try RoomCatalogueTests().catalogue()
        let frame = try #require(FloorFrame(corners: try expected("user").floors[1].corners))
        let w = WallItemPlacement(id: "x", item: "portal", wall: .left, at: 0.5, width: nil, height: nil, bottom: nil, up: nil, transom: nil)
        #expect(WallItems.place(w, frame: frame, catalogue: c, wallHeight: 399) == nil)
    }
}
```

- [ ] **Step 2: Run them to verify they fail** — Expected: `cannot find 'WallItems'`
- [ ] **Step 3: Implement by porting the cited lines**
- [ ] **Step 4: Run them to verify they pass**
- [ ] **Step 5: Commit** — `feat: wall items, windows and the elevator, placed like Cat Office`

---

### Task 5: Desks

**Files:**
- Create: `Sources/ClaudeBarCore/RoomGeometry/Desks.swift`
- Test: append `DeskPlacementTests`

**Interfaces:**
- Produces:
  - `Footprint` and `OccluderBox` come from Task 3.
  - `public struct PlacedDesk: Equatable, Sendable { id, design, image: String; flip, rear: Bool; footprint: Footprint; rect: CGRect; box: OccluderBox; standAt: FloorPoint; facing: String }`
  - `public enum DeskPlacer { static func place(_ d: DeskPlacement, frame: FloorFrame, catalogue: RoomCatalogue) -> PlacedDesk? }`:
    - ports desks.ts:59-107
    - nil for an unknown design

- [ ] **Step 1: Write the failing test**

```swift
@Suite struct DeskPlacementTests {
    @Test(arguments: ["user", "edge"]) func desksMatchCatOffice(_ b: String) throws {
        let c = try RoomCatalogueTests().catalogue(b)
        let building = try #require(Building.parse(building: fixture("rooms/\(b)/building.json"), parts: fixture("rooms/\(b)/room-parts.json")))
        for e in try expected(b).floors {
            let room = try #require(building.floor(id: e.id)?.room), frame = try #require(FloorFrame(corners: e.corners))
            let desks = room.desks.compactMap { DeskPlacer.place($0, frame: frame, catalogue: c) }
            #expect(desks.map(\.id) == e.desks.map(\.id))
            for (d, x) in zip(desks, e.desks) {
                #expect(d.image == x.image && d.flip == x.flip && d.rear == x.rear && d.facing == x.facing, "\(x.id)")
                #expect(near(d.rect.minX, x.left) && near(d.rect.minY, x.top) && near(d.rect.width, x.width) && d.box.z == x.z, "\(x.id)")
                #expect(near(d.standAt.u, x.standAt.u, 1e-3) && near(d.standAt.v, x.standAt.v, 1e-3), "\(x.id)")
            }
        }
    }
}
```

- [ ] **Step 2: Run it to verify it fails**
- [ ] **Step 3: Implement**
- [ ] **Step 4: Run it to verify it passes**
- [ ] **Step 5: Commit** — `feat: desks placed like Cat Office, with work spots`

---

### Task 6: Props, rugs, spots, settle orders

**Files:**
- Create: `Sources/ClaudeBarCore/RoomGeometry/Props.swift`
- Test: append `PropPlacementTests`

**Interfaces:**
- Consumes: `FloorFrame`, `OccluderBox`, `Footprint`, `PlacedDesk`, `WallItems` (for wall seats: room.ts:368-397)
- Produces:
  - `public struct RoomSpot: Equatable, Sendable { id, kind: String; pose: String?; standAt: FloorPoint; facing: String; lift: Double; owner: String }`
  - `public struct PlacedProp: Equatable, Sendable { id, prop: String; image: String?; mirrored: Bool; footprint: Footprint; rect: CGRect; box: OccluderBox; spots: [RoomSpot]; companionOf: String?; cover: [WorldPoint]? }`
  - `public struct PlacedRug: Equatable, Sendable { id, rug: String; image: String?; rect: CGRect; turned: Bool }`
    (rect in floor-plane px)
  - `public enum PropPlacer`:
    - `static func place(room: FloorRoom, frame: FloorFrame, catalogue: RoomCatalogue, desks: [PlacedDesk]) -> [PlacedProp]`:
      buildRoomFloor's prop part (room.ts:944-960), then `settleFootprintOrder(settlePanelRows(props, desks), desks)`
      (room-office.ts:40)
    - `static func rugs(room: FloorRoom, frame: FloorFrame, catalogue: RoomCatalogue) -> [PlacedRug]`: room.ts:550-556
      plus RoomShell 97-119
- Port:
  - room.ts:457-493 (`propPanels`, `propSize`, `propFootprint`)
  - 512-539 (`companionParts`)
  - 561-606 (table bits, `tableTops`, `shrunk`, `tableUnder`, `artAnchor`)
  - 609-673 (`MIRRORED`, `TURNED`, `propSpots`, `propSpotId`)
  - 682-700 (`rugSpots`, `footprintCorners`)
  - 703-766 (`placeProp`, `propFacings`)
  - 789-856 (`settlePanelRows`, `settleFootprintOrder`)
  - 1096-1101 (`overlapsFp`, `within`, `TOUCH_EPS`)
  - wall seats 368-397
  - Rug spots become `RoomSpot`s with `owner` = rug id.

- [ ] **Step 1: Write the failing tests**

```swift
@Suite struct PropPlacementTests {
    @Test(arguments: ["user", "edge"]) func propsMatchCatOffice(_ b: String) throws {
        let c = try RoomCatalogueTests().catalogue(b)
        let building = try #require(Building.parse(building: fixture("rooms/\(b)/building.json"), parts: fixture("rooms/\(b)/room-parts.json")))
        for e in try expected(b).floors {
            let room = try #require(building.floor(id: e.id)?.room), frame = try #require(FloorFrame(corners: e.corners))
            let desks = room.desks.compactMap { DeskPlacer.place($0, frame: frame, catalogue: c) }
            let props = PropPlacer.place(room: room, frame: frame, catalogue: c, desks: desks)
            #expect(props.map(\.id) == e.props.map(\.id), "floor \(e.id)")
            for (p, x) in zip(props, e.props) {
                #expect(p.image == x.image && p.mirrored == x.mirrored && p.companionOf == x.companionOf, "\(x.id)")
                #expect(near(p.rect.minX, x.left) && near(p.rect.minY, x.top) && near(p.rect.width, x.width) && near(p.rect.height, x.height), "\(x.id)")
                #expect(p.box.z == x.z, "\(x.id) z")
                #expect(p.spots.map(\.id) == x.spots.map(\.id), "\(x.id) spots")
                for (s, xs) in zip(p.spots, x.spots) {
                    #expect(near(s.standAt.u, xs.u, 1e-3) && near(s.standAt.v, xs.v, 1e-3) && s.facing == xs.facing && near(s.lift, xs.lift), "\(xs.id)")
                }
            }
            let rugs = PropPlacer.rugs(room: room, frame: frame, catalogue: c)
            #expect(rugs.map(\.id) == e.rugs.map(\.id))
            for (r, x) in zip(rugs, e.rugs) { #expect(near(r.rect.minX, x.left) && near(r.rect.minY, x.top) && r.turned == x.turned) }
        }
    }

    @Test func unknownPropSkipped() throws {
        let c = try RoomCatalogueTests().catalogue()
        let building = try #require(Building.parse(building: fixture("rooms/user/building.json"), parts: fixture("rooms/user/room-parts.json")))
        var room = try #require(building.floor(id: 2)?.room)
        room.props.append(PropPlacement(id: "ufo", prop: "ufo", u: 0.5, v: 0.5, facing: 0, decor: nil, panels: nil, companionsOff: nil))
        let frame = try #require(FloorFrame(corners: try #require(building.floor(id: 2)?.corners)))
        let props = PropPlacer.place(room: room, frame: frame, catalogue: c, desks: [])
        #expect(!props.contains { $0.id == "ufo" } && props.contains { $0.prop == "printer" })
    }
}
```

- [ ] **Step 2: Run them to verify they fail**
- [ ] **Step 3: Implement by porting the cited lines**
- [ ] **Step 4: Run them to verify they pass**
- [ ] **Step 5: Commit** — `feat: props, rugs, seat spots and depth settling like Cat Office`

---

### Task 7: The built room and cat depth

**Files:**
- Create: `Sources/ClaudeBarCore/RoomGeometry/RoomGeometry.swift`
- Test: append `BuiltRoomTests`

**Interfaces:**
- Produces:
  - `public struct BuiltRoom: Equatable, Sendable`:
    - `floorId: Int; frame: FloorFrame; wallHeight: Double`
    - `floorTexture: SurfaceMaterial?; wallTexture: WallMaterial?`
    - `rugs: [PlacedRug]; wallItems: [PlacedWallItem]; elevator: ElevatorSpot?`
    - `fixtures: [PlacedFixture]` (Task 4)
    - `desks: [PlacedDesk]; props: [PlacedProp]`
    - `seats: [RoomSpot]`: Lounge seat spots, poses `sleep` then `sit`, in placement order
    - `bounds: CGRect`: the union of the floor parallelogram and both walls' boxes, in world px
  - `public enum RoomGeometry`:
    - `static func build(floor: Floor, catalogue: RoomCatalogue) -> BuiltRoom?`: nil when `floor.room` or
      `floor.corners` is missing, the frame is degenerate, or any number in the result isn't finite
    - `static func catZ(feet: FloorPoint, figure: CGRect, boxes: [OccluderBox], perch: String?) -> Int`:
      occlusion.ts:42-76
    - `static func figure(feet: WorldPoint, catHeight: Double, lift: Double) -> CGRect`: Office.tsx:209
      (`left/right = x ∓ 0.5h`, `top = y - lift - 1.1h`, `bottom = y + 0.1h`)
  - `extension BuiltRoom { var boxes: [OccluderBox] }`: desks, props, fixtures; Office.tsx:329-337

- [ ] **Step 1: Write the failing tests**

```swift
@Suite struct BuiltRoomTests {
    func built(_ id: Int) throws -> BuiltRoom {
        let c = try RoomCatalogueTests().catalogue()
        let b = try #require(Building.parse(building: fixture("rooms/user/building.json"), parts: fixture("rooms/user/room-parts.json")))
        return try #require(RoomGeometry.build(floor: try #require(b.floor(id: id)), catalogue: c))
    }

    @Test func loungeSeatsComeFromItsFurniture() throws {
        let l = try built(1)
        #expect(l.seats.first?.pose == "sleep", "cat beds first")
        #expect(Set(l.seats.map(\.kind)).isSubset(of: ["cat-bed", "sofa", "beanbag", "rug", "window-seat"]))
        #expect(l.seats.count >= 8)
        #expect(l.elevator != nil && l.wallItems.contains { $0.isElevator })
    }

    @Test func catBehindDeskIsOccluded() throws {
        let r = try built(2)
        let desk = try #require(r.desks.first)
        // Feet just behind the desk's back corner, on screen inside its box.
        let feet = FloorPoint(u: desk.footprint.u0 - 0.002, v: desk.footprint.v0 + (desk.footprint.v1 - desk.footprint.v0) / 2)
        let px = r.frame.px(feet)
        let z = RoomGeometry.catZ(feet: feet, figure: RoomGeometry.figure(feet: px, catHeight: 160, lift: 0), boxes: r.boxes, perch: nil)
        #expect(z < desk.box.z)
    }

    @Test func degenerateFloorFallsBack() throws {
        let c = try RoomCatalogueTests().catalogue()
        let b = try #require(Building.parse(building: fixture("rooms/user/building.json"), parts: fixture("rooms/user/room-parts.json")))
        var f = try #require(b.floor(id: 2))
        let z = WorldPoint(x: 1, y: 1)
        f.corners = FloorCorners(top: z, left: z, bottom: z, right: z)
        #expect(RoomGeometry.build(floor: f, catalogue: c) == nil)
        f = try #require(b.floor(id: 2)); f.room = nil
        #expect(RoomGeometry.build(floor: f, catalogue: c) == nil)
    }

    @Test func boundsHoldTheWholeRoom() throws {
        let r = try built(2)
        #expect(r.bounds.minX <= r.frame.corners.left.x && r.bounds.maxX >= r.frame.corners.right.x)
        #expect(r.bounds.minY <= r.frame.corners.top.y - r.wallHeight && r.bounds.maxY >= r.frame.corners.bottom.y)
    }
}
```

- [ ] **Step 2: Run them to verify they fail**
- [ ] **Step 3: Implement**:
  - `build` composes Tasks 3–6.
  - `catZ` and `overZ` are ported from occlusion.ts.
  - Seats are the prop spots plus rug spots whose `pose` is `sleep` or `sit` and whose kind isn't `meeting`; sleep
    first, then the rest in placement order.
- [ ] **Step 4: Run them to verify they pass**
- [ ] **Step 5: Commit** — `feat: one floor fully placed (BuiltRoom) with cat depth`

---

### Task 8: Load the catalogues; seat cats on real desks and seats

**Files:**
- Modify: `Sources/ClaudeBarCore/ArtCache.swift` (add `roomCatalogue()`)
- Modify: `Sources/ClaudeBarCore/FloorPlan.swift`:
  - `seating(on:agents:previous:)` uses world distance for "nearest"
  - the Lounge seat count comes from the room
- Modify: `Sources/ClaudeBar/AppState.swift`:
  - `@Published private(set) var catalogue: RoomCatalogue?`
  - `rooms: [Int: BuiltRoom]`, rebuilt when the building or catalogue changes
  - loaded alongside `loadBuilding()`
- Test: `Tests/ClaudeBarCoreTests/FloorPlanTests.swift`, `ArtCacheTests.swift`

**Interfaces:**
- Produces:
  - `ArtCache.roomCatalogue() async -> RoomCatalogue?`:
    - fetches `data/room-parts.json`, `data/props.json`, `data/desks.json` and `src/world/wall-item-art.json` (optional)
    - saves all four only when `RoomCatalogue.parse` succeeds, else parses the cached copies (same pattern as
      `building()`)
  - `FloorSeating.seating(on: Floor, agents: [OfficeAgent], previous: FloorSeating?, seats: Int? = nil)`:
    - `seats` is the Lounge's seat count (`BuiltRoom.seats.count`); nil keeps `FloorSeating.loungeSpots`
    - "nearest desk" is the world distance between desk `(u, v)` points via `FloorFrame` when `floor.corners` exists,
      else today's grid distance

- [ ] **Step 1: Write the failing tests**

```swift
// FloorPlanTests.swift, in FloorSeatingTests
@Test func helperTakesTheNearestDeskOnTheFloor() {
    // Three desks in a line on the floor; the parent at the far end, so the next desk in list order is NOT the nearest.
    let corners = FloorCorners(top: WorldPoint(x: 1000, y: 0), left: WorldPoint(x: 0, y: 500), bottom: WorldPoint(x: 1000, y: 1000), right: WorldPoint(x: 2000, y: 500))
    let desks = [FloorDesk(id: "a", design: "s1-oak", flip: false, rear: false, u: 0.1, v: 0.1),
                 FloorDesk(id: "b", design: "s1-oak", flip: false, rear: false, u: 0.9, v: 0.9),
                 FloorDesk(id: "c", design: "s1-oak", flip: false, rear: false, u: 0.85, v: 0.8)]
    var f = Floor(id: 12, name: "x", repoRoot: "/w", floorTexture: nil, wallTexture: nil, desks: desks, elevator: nil, hasLoungeSign: false)
    f.corners = corners
    let previous = FloorPlan.seating(on: f, agents: [a("p")], previous: nil)
    var placed = previous; placed.desks = [nil, "p", nil]
    let s = FloorPlan.seating(on: f, agents: [a("p"), a("h", parent: "p")], previous: placed)
    #expect(s.desks == [nil, "p", "h"])
}

@Test func loungeUsesTheRoomsSeatCount() {
    let s = FloorPlan.seating(on: lounge, agents: (0..<9).map { a("c\($0)", .idle) }, previous: nil, seats: 6)
    #expect(s.lounge.count == 6 && s.loungeOverflow == 3)
}
```

```swift
// ArtCacheTests.swift
@Test func aBrokenCatalogueKeepsTheGoodCachedCopy() async throws {
    let dir = makeTempDir()
    for f in ["room-parts", "props", "desks"] {
        try fixture("rooms/user/\(f).json").write(to: dir.appendingPathComponent("data_\(f).json"))
    }
    let config = URLSessionConfiguration.ephemeral
    config.protocolClasses = [BrokenBuildingProtocol.self]
    let cache = ArtCache(dir: dir, baseURL: { URL(string: "http://stub.test")! }, session: URLSession(configuration: config))
    #expect(await cache.roomCatalogue()?.desks["s1-walnut"] != nil)
}
```

(`FloorDesk` gets an `init(id:design:flip:rear:u:v:)` with `u` and `v` defaulting to 0, so existing tests compile.)

- [ ] **Step 2: Run them to verify they fail**
- [ ] **Step 3: Implement**
  - In `AppState`:
    - add `loadCatalogue()`, called next to `loadBuilding()` and by the same 60s timer
    - `rooms` is recomputed in a `didSet`-style helper whenever `building` or `catalogue` changes:
      `rooms = Dictionary(building.floors.compactMap { f in RoomGeometry.build(floor: f, catalogue: c).map { (f.id, $0) } })`
- [ ] **Step 4: Run them to verify they pass**
- [ ] **Step 5: Commit** — `feat: load Cat Office's room catalogues; seat cats by real desk distance`

---

### Task 9: `FloorScene`: the room image

**Files:**
- Create: `Sources/ClaudeBarCore/SceneFit.swift`, `Sources/ClaudeBar/Views/FloorScene.swift`
- Modify: `Sources/ClaudeBar/Views/OfficePeekView.swift`: in `OfficeRoomView`, use
  `FloorScene(room: rooms[floorId])` when present, else today's `RoomBackdrop` + `room()` (the fallback)
- Modify: `Sources/ClaudeBar/RenderPeek.swift`: no change needed beyond what the views do (renders already pick a floor)

**Interfaces:**
- Consumes: `BuiltRoom`, `ArtCache.image(path:maxPixelSize:)`, `Night`, `officeNight`
- Produces:
  - `SceneFit` (Core, `Sources/ClaudeBarCore/SceneFit.swift`, signature below the test), with
    `static func fill(floor: FloorFrame, into size: CGSize) -> SceneFit`:
    - `scale = size.width / (right.x - left.x + 40)`
    - x is centred on the floor
    - y centres the floor parallelogram's middle (`(top.y + bottom.y) / 2`) in the room
    - this is view #2: fill the width, trim the top and bottom
  - `@MainActor final class RoomImageCache`: `func image(for room: BuiltRoom, night: Bool, scale: CGFloat, art: ArtCache) async -> NSImage?`:
    - keyed by `(floorId, room hash, night, scale)`
    - draws, in order:
      1. the floor texture tiled into the plane transform
      2. rugs
      3. walls (texture + 3-slice top trim, per RoomShell 339-349)
      4. wall items with their pieces and the floor-number plate
      5. desks, props and fixtures sorted by `box.z` (ties: desks, then props, then fixtures)
    - mirrored items use `scaleX(-1)` about their box centre
    - the night look multiplies `Night.room` into the floor and walls, and `Night.furniture` into everything else
    - drawn with Core Graphics into an `NSImage` at the room's pixel size (Retina: × 2)
  - `struct FloorScene: View { let room: BuiltRoom }`: the cached image, scaled and offset by `SceneFit`, plus the live
    layer (Task 10)

- [ ] **Step 1: Write the failing test** (pure fit math, in a new `Tests/ClaudeBarCoreTests/SceneFitTests.swift`):

```swift
import CoreGraphics
import Testing
@testable import ClaudeBarCore

@Suite struct SceneFitTests {
    @Test func fillsTheWidthAndCentresTheFloor() throws {
        let f = try #require(FloorFrame(corners: try expected("user").floors[1].corners))
        let fit = SceneFit.fill(floor: f, into: CGSize(width: 472, height: 180))
        let left = fit.point(f.corners.left), right = fit.point(f.corners.right)
        #expect(abs(left.x - 20 * fit.scale) < 0.5, "a 20 world-px margin each side")
        #expect(abs((left.x + right.x) / 2 - 236) < 0.5, "centred across")
        let mid = fit.point(WorldPoint(x: f.corners.top.x, y: (f.corners.top.y + f.corners.bottom.y) / 2))
        #expect(abs(mid.y - 90) < 0.5, "floor centred down")
        #expect(abs(right.x - left.x - (472 - 40 * fit.scale)) < 0.5, "fills the width")
    }
}
```

with `public struct SceneFit { public let scale: CGFloat; public let origin: CGPoint; public func point(_ p: WorldPoint) -> CGPoint; public static func fill(floor: FloorFrame, into: CGSize) -> SceneFit }`.

- [ ] **Step 2: Run it to verify it fails**
- [ ] **Step 3: Implement `SceneFit`, `RoomImageCache`, `FloorScene` (image only) and the fallback switch**
- [ ] **Step 4: Run the tests and renders, and compare with Cat Office**

```bash
swift test 2>&1 | grep -E "tests passed|failed after" | tail -1 && bash scripts/build.sh 2>&1 | grep -E "error:|Built"
B=build/ClaudeBar.app/Contents/MacOS/ClaudeBar
for f in 1 2 6 12; do CLAUDEBAR_RENDER_FLOOR=$f CLAUDEBAR_RENDER_LIGHT=1 $B --render-dropdown /tmp/cb-mock/exact-$f.png office; done
CO_URL=http://localhost:5173; mkdir -p /tmp/cb-layout
for f in 1 2 6 12; do ("/Applications/Google Chrome.app/Contents/MacOS/Google Chrome" --headless=new --hide-scrollbars --user-data-dir=/tmp/cb-layout/profile --window-size=1600,1000 --timeout=10000 --screenshot=/tmp/cb-layout/co-$f.png "$CO_URL/?floor=$f&theme=light" >/dev/null 2>&1 &); sleep 14; pkill -f cb-layout/profile; done
```
Expected: each `exact-N.png` shows the same items in the same places as `co-N.png` (ignoring cats). Open each pair and
compare. A floor whose room failed to build shows the simple room.

- [ ] **Step 5: Commit** — `feat: draw each floor's real layout (room image)`

---

### Task 10: Cats on the real floor

**Files:**
- Modify: `Sources/ClaudeBar/Views/FloorScene.swift`: live layer
- Modify: `Sources/ClaudeBar/Views/OfficePeekView.swift`: feet and frames, walks and rides use scene coordinates when
  a `FloorScene` is shown
- Create: `Sources/ClaudeBarCore/PillLayout.swift`
- Test: `Tests/ClaudeBarCoreTests/PillLayoutTests.swift`

**Interfaces:**
- Consumes: `FloorSeating`, `BuiltRoom.desks/seats/elevator/boxes`, `RoomGeometry.catZ/figure`, `SceneFit`, `CatView`
  art loaders, `WalkersLayer`, `RidersLayer`, `ElevatorTrip`
- Produces:
  - **Desk cats:** each seated agent is drawn at its desk's `standAt`, facing `facing`, in the pose from `DeskScene`
    (typing / standing / waving).
    - The sprite is placed with Cat Office's cat layout: size `360×380 × catHeight/210`, feet at `(180, 300)` in that
      canvas.
    - The feet are at `SceneFit.point(frame.px(standAt))`.
  - **Lounge cats:** seat `i` → `room.seats[i]`, sleeping pose, raised by `lift`. Overflow cats cluster on the first rug
    spot (else the floor centre) in a 3-wide grid with 0.03 u/v spacing, then "+N asleep".
  - **Helpers beside their parent:** at the parent desk's `standAt` offset by `(+0.04, -0.02)` in u, v per helper
    index, at 0.8×.
  - **Queue:** at the elevator's waiting places, `ElevatorTrip.waitingOffset`.
  - **Depth:** each cat gets `catZ`. Every desk, prop or fixture whose rect overlaps a cat's figure and whose z is above
    that cat's z is drawn again in the live layer, sorted together with the cats by z.
  - **`CatFeetKey` / `CatFramesKey`:** report scene points, so walking, rides (from
    `SceneFit.point(frame.px(elevator.standAt))`) and hover keep working. `ElevatorArt.door()` is used only by the
    fallback room.
  - **`PillLayout.visible(_ pills: [String: CGRect]) -> Set<String>`:** greedy in a stable order (needs-you first, then
    by name). A pill is shown only if it overlaps no shown pill. Rects are in view points after zoom.

- [ ] **Step 1: Write the failing test**

```swift
// Tests/ClaudeBarCoreTests/PillLayoutTests.swift
import CoreGraphics
import Testing
@testable import ClaudeBarCore

@Suite struct PillLayoutTests {
    @Test func pillsNeverOverlap() {
        let pills = ["a": CGRect(x: 0, y: 0, width: 60, height: 20), "b": CGRect(x: 30, y: 5, width: 60, height: 20),
                     "c": CGRect(x: 100, y: 0, width: 60, height: 20)]
        let shown = PillLayout.visible(pills, priority: [])
        #expect(shown == ["a", "c"])
        for x in shown { for y in shown where x < y { #expect(!pills[x]!.intersects(pills[y]!)) } }
    }

    @Test func needsYouWinsTheSpot() {
        let pills = ["a": CGRect(x: 0, y: 0, width: 60, height: 20), "b": CGRect(x: 30, y: 5, width: 60, height: 20)]
        #expect(PillLayout.visible(pills, priority: ["b"]) == ["b"])
    }

    @Test func atTwiceTheSizeBothFit() {
        // The same cats at 2×: centres twice as far apart, pills the same size.
        let pills = ["a": CGRect(x: 0, y: 0, width: 60, height: 20), "b": CGRect(x: 70, y: 10, width: 60, height: 20)]
        #expect(PillLayout.visible(pills, priority: []) == ["a", "b"])
    }
}
```

Signature: `public enum PillLayout { public static func visible(_ pills: [String: CGRect], priority: Set<String>) -> Set<String> }`.

- [ ] **Step 2: Run it to verify it fails**
- [ ] **Step 3: Implement `PillLayout` and the live layer as described**
- [ ] **Step 4: Verify**

```bash
swift test 2>&1 | grep -E "tests passed|failed after" | tail -1 && bash scripts/build.sh 2>&1 | grep -E "error:|Built"
B=build/ClaudeBar.app/Contents/MacOS/ClaudeBar
CLAUDEBAR_RENDER_LIGHT=1 CLAUDEBAR_RENDER_SUBAGENT=5 $B --render-dropdown /tmp/cb-mock/exact-cats.png office
CLAUDEBAR_RENDER_FLOOR=1 $B --render-dropdown /tmp/cb-mock/exact-lounge-night.png office
for t in 3.0 4.4; do CLAUDEBAR_RENDER_FLIP_TO=working CLAUDEBAR_RENDER_LIGHT=1 CLAUDEBAR_RENDER_FLIP_AT=5 CLAUDEBAR_RENDER_MIDWALK=$t $B --render-peek /tmp/cb-mock/exact-ride-$t.png; done
(CLAUDEBAR_START_TAB=office $B --test-tabs > /tmp/cb-tabtest.log 2>&1 &); sleep 14; pkill -f build/ClaudeBar.app/Contents/MacOS/ClaudeBar; grep -E "clicked" /tmp/cb-tabtest.log
($B --test-zoom > /tmp/cb-zoom.log 2>&1 &); sleep 14; pkill -f build/ClaudeBar.app/Contents/MacOS/ClaudeBar; tail -6 /tmp/cb-zoom.log
```

Expected:
- cats sit at real desks facing their screens, and sleep on the Lounge's beds and sofas
- a cat behind a desk is partly hidden by it
- helpers stand beside their parent
- pills don't overlap
- the ride starts from the elevator door
- tabs, the floor picker and zoom still work

- [ ] **Step 5: Commit** — `feat: cats at real desks and seats, with depth and non-overlapping names`

---

### Task 11: Clean-up, install, docs

**Files:**
- Modify: `Sources/ClaudeBar/Views/OfficePeekView.swift`: delete `LoungeFloor`'s fixed `props`/`spots` and the old
  `Lounge` view. The simple room stays only as the fallback: `deskGrid`, `RoomBackdrop`, and a lounge that seats cats
  in a row.
- Modify: `README.md` ("Floors": a line on exact layouts and the fixture script)
- Modify: the spec's **Status** to `Implemented`

- [ ] **Step 1:** `grep -n "round-cream.png\|sofa-round.png\|LoungeFloor.spots\|tall-plant.png" Sources/ClaudeBar/Views/*.swift`.
  Expected: only fallback uses remain, and none in the exact path.
- [ ] **Step 2:** Add to README under "Floors":

```markdown
Each floor is drawn from that Cat Office's own layout (`building.json` and its catalogues), so a teammate's ClaudeBar
shows their office. When Cat Office changes how rooms are laid out, re-run the fixtures
(`npx tsx <claude-bar>/scripts/room-fixtures.ts <in-dir> <out.json>` from the Cat Office folder) and `swift test`.
```

- [ ] **Step 3:** Run the full suite, the status line tests, the renders from Tasks 9–10, then install:

```bash
swift test 2>&1 | grep -E "tests passed|failed after" | tail -1; bash scripts/test-statusline.sh 2>&1 | grep -c "^PASS"
pkill -f "MacOS/ClaudeBar"; sleep 1; rm -rf ~/Applications/ClaudeBar.app && cp -R build/ClaudeBar.app ~/Applications/ && open ~/Applications/ClaudeBar.app
```
Expected: all tests pass, and `8`.

- [ ] **Step 4: Commit** — `docs: exact floors in the README; spec implemented`

# ClaudeBar Exact Floors — Design

**Date:** 2026-10-07
**Status:** Draft, awaiting review
**Builds on:** `2026-10-07-claudebar-floors-design.md` (floors, picker, Follow, elevator rides)
**Related:** `2026-10-07-claudebar-sharing-draft.md` (paused; teammates will use this too)

## Goal

Draw each Cat Office floor the way that person's Cat Office lays it out: every desk, prop, rug, window and the elevator in
its real place, with cats at real desks and on real seats. Today ClaudeBar shows a simplified room: desks in rows of 6 and
fixed Lounge furniture.

**Binding requirement:** ClaudeBar draws whatever Cat Office it is connected to. No layout is built in. Each teammate's
ClaudeBar reads their own `building.json`, catalogues and art, and caches only its owner's copy.

**Success criteria**

- On the user's own Cat Office, each floor in ClaudeBar matches the browser's floor: same items in the same places and
  depth order, scaled down (compared against headless Cat Office screenshots).
- A teammate's different layout shows as theirs with no change to ClaudeBar.
- Cats sit at their real desks, sleep on real Lounge seats, and ride from the real elevator door.
- Battery use stays close to today's (only cats animate).

## 1. Room geometry (`RoomGeometry`, Core, pure)

A port of the positioning parts of Cat Office's `src/world/room.ts`, `floor-math.ts`, `desks.ts`, and the wall-item
code. Input: one floor from `building.json` plus `room-parts.json`, `props.json` and `desks.json`. Output, all in
Cat Office world pixels:

- **Floor:** corners, outline, and the floor-point → world-point mapping (`uvToPx`)
- **Walls:** the left and right wall planes and the wall height
- **Wall items:** each item's quad and art (windows built from frame, glass, mullion and transom pieces; pictures,
  clocks, the Lounge sign), and the elevator with its door, plate and **door spot**
- **Rugs:** quad and art
- **Desks and props:** position, size, mirroring, art, and the companion parts Cat Office adds
- **Spots:** every place a cat can be, with its facing: desk seats, prop spots (sofa and bed seats, bean bags, cushions,
  the printer), and the elevator door
- **Depth order:** the sort Cat Office uses (`u + v`, plus its row and footprint settling)

**Not ported:** the room editor, validation and issues, the layout generator, and the walking grid.

**Unknown ids:** an unknown prop, desk or wall item is skipped; the rest of the floor draws.

## 2. Drawing a floor (`FloorScene`, view)

- **Units and fit:** the floor is laid out in world pixels, scaled to fill the room's full width (472pt in the
  dropdown), and trimmed top and bottom to the room's height (180pt). The crop is centred on the floor outline.
  The peek uses the same view, sized to its room.
- **Back to front:**
  1. the floor texture, mapped onto the floor plane with an affine transform
  2. rugs
  3. the walls, with their texture and top edge
  4. wall items, including the elevator with its floor number on the plate
  5. desks, props and cats, sorted by depth
- **Two layers:**
  - **Room image:** steps 1–5 without cats are drawn once into a single image per floor, and rebuilt when the layout,
    the night look or the room size changes.
  - **Live layer:** cats, walkers and riders. Furniture that sits in front of a cat (by depth) is drawn again above it,
    so a cat can be half hidden by a desk.
- **Carried over:** the picker, Follow, the busy strip, zoom, hover cards, the night look (tint, cooled furniture, lamp
  glow), and the peek.

## 3. Cats, names and seats

- **Desks:** cats sit at the floor's real desks, using the current seating rules:
  - the reported desk design first
  - stable seats
  - helpers at the free desk nearest their parent
  - main agents outrank helpers

  The seat point and facing come from the desk's seat spot, composed with `DeskComposition` as today.
- **"Nearest desk":** measured on the floor (world distance between desks), replacing the 6-column grid distance.
- **Lounge:** sleeping cats take the Lounge's real seat spots in stable order. Extra cats sleep in a cluster on the rug
  (else near the centre of the floor), then "+N asleep".
- **Helpers with no free desk:** they stand on the floor beside their parent's desk at 0.8×. Up to 2 show, then "+N".
- **A floor with no desks:** cats stand at the elevator's waiting places.
- **Names:**
  - **Default:** no name pills. Each cat has its status ring; a cat that needs you also has the "!" bubble.
  - **Hover** shows the full card.
  - **Pills appear** when no two would overlap at the current zoom: always at 2× and above, and at 1× on floors with few
    cats.
- **Walking:** today's walks between real spots, as L-shaped paths along the floor's axes (the floor-board diagonals).
  Cats may pass over furniture.
- **Rides:** start and end at the elevator's real door spot.

## 4. Refresh, fallbacks, battery

- **Refresh:** `building.json`, `room-parts.json`, `props.json` and `desks.json` load when Cat Office connects and
  every 60s.
  - Only a set that parses replaces the cached copy.
  - A changed floor rebuilds its room image and re-seats its cats. A cat whose desk is gone walks to its new seat.
- **Fallbacks:**

| Problem | What shows |
|---|---|
| A floor has no room data | Today's simple room for that floor |
| An unknown prop, desk or wall item id | That item is skipped |
| Art fails to load | Its colour; small decorations are left out |
| Cat Office never reached and nothing cached | One Lounge (`Building.fallback`), as today |
| Geometry gives no usable floor (zero size, not a number) | Today's simple room for that floor, and a log line |

- **Battery:** the room image doesn't animate. Floors that aren't shown aren't drawn.

## 5. Units

| Unit | Role |
|---|---|
| `RoomGeometry` (Core, pure) | Section 1 |
| `RoomCatalogue` (Core) | Parses `props.json` and `desks.json`, plus the `room-parts.json` parts the geometry needs |
| `FloorSeating` (Core, changed) | Seats on real desks and spots; nearest desk by floor distance |
| `FloorScene` (view) | Section 2: the room image plus the live layer |
| `ArtCache` (changed) | Also loads `props.json`, `desks.json`, and the wall-item, prop and rug art |

**Replaced, kept only as the per-floor fallback:** `deskGrid`, `LoungeFloor`'s fixed spots, and `RoomBackdrop`'s
hard-coded plant and lamp.

## 6. Testing

- **Fixture tests:**
  - `scripts/room-fixtures.mjs` runs Cat Office's own TypeScript functions in Node on a `building.json` and writes their
    answers to `Tests/.../Fixtures/`.
  - The Swift `RoomGeometry` must match within 0.5 world px for floor corners, wall planes, wall item quads, elevator
    door spots, desk and prop positions with mirroring, every spot, and depth order.
  - Inputs: the user's `building.json`, and a small hand-made one covering mirrored props, a floor with no desks, a wide
    window, and a raised wall.
  - The script needs a Cat Office folder. It's run by hand when Cat Office changes, not in `swift test`.
- **Unit tests:** seating on real spots, nearest desk by floor distance, Lounge overflow, names shown only without
  overlap, every fallback in Section 4, and that no layout is built in.
- **Renders:** the Lounge, Office (floor 2), the Desk pool and a project floor, light and dark. Each is compared with a
  headless Cat Office screenshot of the same floor.
- **Existing tests:** the click test, zoom test and status line tests still pass.

## Out of scope

- Cats walking around furniture (Cat Office's walking grid): a later step
- Unsaved room edits (they live in the browser until saved)
- Matching a teammate's Cat Office version that draws rooms differently: ClaudeBar draws the ported rules, and the
  fixture script shows what changed
- Sharing and setup (Project 1, paused)

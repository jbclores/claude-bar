# ClaudeBar Walking Around Furniture — Design

**Date:** 2026-10-08
**Status:** Draft, awaiting review
**Builds on:** `2026-10-07-claudebar-exact-floors-design.md` (its "Out of scope: cats walking around furniture (Cat
Office's walking grid): a later step")

## Goal

In ClaudeBar, cats walk around furniture the way they do in the user's own Cat Office in the browser: to and from
their desks, the Lounge seats and the elevator, on whatever layout each teammate has. A cat never walks through a desk,
table, plant or sofa. Nothing else about the office changes.

**Success criteria**

- On the user's own Cat Office, ClaudeBar blocks exactly the cells Cat Office blocks, and its routes have the same
  corners as Cat Office's (within 0.5 world px), checked against fixtures from Cat Office's own code.
- No layout is built in: each ClaudeBar walks the grid of the Cat Office it is connected to.
- Walking speed, rides, seats, timing rules and battery use stay as today; a longer route just takes longer.
- A cat is never stuck: when there is no route, it walks today's L route.

## 1. The walking grid (`NavGrid`, Core)

A port of the parts of Cat Office's `src/world/nav-grid.ts`, `desks.ts` (`footprintCells`, `cellIndex`,
`carveGrid`) and `room.ts` (prop carving) that build a floor's grid:

- **Base:** like Cat Office's `buildRoomFloor` for a built room: every cell open except a one-cell band along the edges;
  `building.json`'s `grid` gives only the size (usually 48) and, with valid rows, says the floor has a grid at all (its
  saved `walkable` is stale for built rooms: it differs from what the browser walks by tens to hundreds of cells).
  Cell (ui, vi) has its centre at u = (ui + 0.5) / size, v = (vi + 0.5) / size. Floors without a built room are drawn as
  the simple room and walk the L.
- **Spots:** every floor spot's cells (elevator, prop and rug spots, and their slots) are reopened unless another piece's
  footprint covers them, as `buildRoomFloor` does.
- **Furniture:** every prop on the floor blocks the cells whose centre lies in its footprint grown by half a cell
  (`FOOTPRINT_MARGIN_CELLS`); props that stand on tables (table bits) block nothing; companion parts block like props.
- **Desks:** every placed desk blocks the same way; then each desk's stand-at cell is reopened if the base grid has it
  open, so its cat can always reach it (`carveGrid`).
- **Regions:** 4-connected regions of open cells, as Cat Office labels them.
- Footprints come from `RoomGeometry` (already ported for exact floors).

**Not ported:** hazards and fires (the browser's panic mode), `wouldSeal`, line of sight.

## 2. Routes (`NavGrid.findPath`, Core)

A port of `findPath` and what it uses: `approach`, `nearestOpenCell`, `cellRoute` (A* over open cells, 4-neighbour
along the floor axes, `TURN_COST` 0.5 cells per turn, of equal routes the one with fewest turns), `corners`,
`straighten`, `clearL`, `clearLeg`, `axisLegs`, the end-point sliding, `MIN_LEG_PX` (2 world px) and `dedupe`.

- Input and output are floor points (u, v); `nil` when unreachable.
- A start or end off open floor (a desk seat, a bed, a sofa seat) steps straight onto the open floor in front of it,
  along u or v, as `approach` does.

## 3. Walks (`WalkPath`, Core, changed)

- `WalkPath` gains a way to be built from a route's points (on screen). Leg facing, walking frames by distance and
  constant speed work as today, leg by leg.
- The office views ask for a route between the walk's two floor points: the floor's `NavGrid` route when there is one,
  else today's L (`WalkPath(from:to:)`).
- **Fallbacks (today's L walk):** no route (a spot boxed in), a floor without a grid or with a grid that doesn't parse,
  the simple fallback room (no room data), or a walk between points the view only knows on screen.

## 4. Refresh and battery

- A floor's grid is built when its room is built (the exact-floors refresh: when Cat Office connects and every 60 s;
  only a set that parses replaces the cached one) and cached with it. A changed layout rebuilds the grid; a cat mid-walk
  finishes its current route.
- Routes are found once per walk (a 48 × 48 grid: about a millisecond). Nothing new runs while cats sit.

## 5. Units

| Unit | Role |
|---|---|
| `NavGrid` (Core, new) | Section 1 and 2: the carved grid, regions, `findPath` |
| `WalkPath` (Core, changed) | Built from route points as well as the L |
| Office views (`OfficePeekView` walks and rides) | Ask `NavGrid` for routes, fall back to the L |
| `Building` / room loading (changed) | Keeps each floor's `grid` (`size` and `walkable`) |
| `scripts/room-fixtures.ts` (changed) | Also writes Cat Office's carved grids and routes |

## 6. Testing

- **Fixtures:** `scripts/room-fixtures.ts` runs Cat Office's own `NavGrid` (with the floor's desks and props carved, as
  the app does) on the user's `building.json` and on the hand-made fixture building, and writes:
  - each floor's carved grid (the blocked cells);
  - routes for a fixed set of pairs per floor: each desk's stand-at spot to the elevator door spot and back, the
    elevator to each Lounge seat spot, seat to seat, and a few pairs across the floor.

  The Swift `NavGrid` must block exactly the same cells, and its routes must have the same points within 0.5 world px
  (and both must agree on unreachable). As for exact floors, the script needs a Cat Office folder and is run by hand
  when Cat Office changes, not in `swift test`.
- **Unit tests:** a route goes round a desk and never enters a blocked cell; a cat on a seat steps straight off it
  first; a desk's stand-at cell is reachable though its desk blocks the cells around it; an unreachable spot gives nil
  and the walk falls back to the L; a floor without a grid falls back to the L; legs run only along u or v; facing and
  frames follow each leg.
- **Renders:** a cat mid-walk around furniture on a project floor and in the Lounge, to look at.
- **Existing tests:** the click, zoom, setup and undo tests, and the exact-floors fixtures, still pass.

## Out of scope

- Cats wandering on their own (e.g. to the snack table): a separate Cat Office feature.
- Cats avoiding each other.
- The browser's panic mode (fires and hazards).

# ClaudeBar Floors — Design

**Date:** 2026-10-07
**Status:** Draft, awaiting review
**Builds on:** `2026-10-06-claude-bar-design.md` (the office room, desks, walking)

## Goal

Replace ClaudeBar's single office room with **Cat Office's building**: one floor at a time, each floor drawn with its own art and desks, and cats riding the elevator between floors. This fixes crowding: with 5 or more working agents and helpers, the single room ran out of desks, and helpers took desks ahead of their parents.

**Success criteria**

- Every Cat Office floor can be shown. Floors with nobody on them are dimmed in the menu.
- Each cat is on the same floor as in Cat Office, by the same rules.
- With Follow on (the default), the Office tab shows where things are happening without any clicks.
- A cat that changes floors walks to the elevator, rides it and walks out on the other floor.
- The hover peek keeps working, and always follows.

## 1. Data (read from Cat Office, no token needed)

- **`/data/building.json`**: `floors[]`, each with:
  - `id` (1…n) and `name`
  - `repo.root` (home-relative, e.g. `~/Documents/projects/claude-bar`; absent for shared floors)
  - `room.floor` and `room.wall` (texture ids)
  - `room.desks[]`: `{id, desk, u, v, flip, rear?}`
  - `room.wallItems[]` (the elevator item: `elevator` or `elevator-lounge`; `sign-lounge` on the Lounge)
- **`/data/room-parts.json`**: `floors[]` and `walls[]`, each `{id, image, tile, color}` (e.g. `oak → assets/room/floors/oak.png`, tile 1024×528), plus `wallItems[]` art.
- **Fetching:** both files are fetched when Cat Office connects and when the feed's floors change. A copy is cached like the cat art, so floors still show while Cat Office is offline.

## 2. Who goes to which floor (`FloorPlan`, pure, unit-tested)

The rules follow Cat Office (`floors.ts`, `MissionControl.tsx`):

| Agent | Floor |
|---|---|
| idle | **Lounge** (id 1) |
| working / waiting, with a project | the floor whose `repo.root` (normalized) equals or contains the agent's `repoRoot ?? cwd` |
| working / waiting, no matching floor | **Desk pool**: the floor named "Desk pool", else the first floor without a repo other than the Lounge |
| sub-agent | **its parent's floor** (by `parentName`); the Desk pool if the parent isn't in the office |
| ended | not shown |

- **Which floor exists** comes only from `building.json`. ClaudeBar never creates floors.

## 3. Desks on a floor

- **The floor's own desks:** `room.desks[]` in their stored order, each with its design, `flip` and `rear`. On a floor with none, the room shows "No desks on this floor" and cats stand in a row.
- **Layout:** desks are laid out in **up to 2 rows of 6** across the room, in stored order. This is a simplified view of the isometric layout, not Cat Office's u/v positions.
- **Cats at desks:**
  - A cat's reported desk (`agent.desk`: design, flip, rear) takes the first unused desk on its floor with the same design and orientation.
  - Otherwise it takes a free desk in stable order (`StableSlots`, keyed by floor).
- **Helpers:**
  - A helper takes the free desk nearest its parent's desk.
  - With none free, it stands **beside its parent's desk**, smaller (0.8×), labeled "working nearby". Up to 2 per parent are drawn; more show "+N" on the parent's desk.
- **Free desks:** unused desks are drawn empty (dimmed), as today.
- **More cats than desks:** those cats stand in a short queue at the right edge, then "+N".

## 4. The Lounge (floor 1)

- **The whole room is the lounge.** It has seats from Cat Office's props: round sofa, sofa, cat bed, two bean bags, two floor cushions, and the rug. That's **10 spots** in fixed positions, then "+N asleep".
- The **Lounge sign** (`sign-lounge.png`) is on the back wall.
- There are no desks on the Lounge.

## 5. Floor look

- **Wall and floor:** the textures named by `room.wall` and `room.floor`, tiled at Retina scale as today. If a texture can't load, its `color` is used.
- **The elevator:** the floor's elevator art on the back wall at the left (where Cat Office has it, `at` ≈ 0.51 of the left wall, simplified to the left end of the back wall).
  - The plain `elevator` art shows the **floor number** on its plate (Cat Office: plate at x80 y10, 68×21, `#f4ece6`, font 0.8 × plate height).
  - `elevator-lounge` has no plate.
- **Night:** the night tint and lamp light from today apply to every floor.

## 6. Picker and Follow (option C)

- **Header row** above the room:
  - A **floor menu** button, "12 claude-bar · 3 cats ⌃⌄". It opens a menu of every floor ("1 Lounge · 4", "2 Office", …), with empty floors dimmed and an amber dot on floors with a cat that needs you.
  - **▲ / ▼** to step one floor up or down.
  - **Follow** (a toggle) on the right.
- **Busy-floors strip** under the row: one short bar per floor, left to right. Gray = empty, green = cats working, amber = a cat needs you, dark = the floor shown.
- **Follow:**
  - **What it shows:** the floor with a cat that needs you (newest first), else the floor where a cat most recently started or finished work, else the floor with the most working cats, else the Lounge.
  - **On by default,** and each time the dropdown opens.
  - **Choosing a floor yourself** (menu, ▲▼, or tapping the strip) turns Follow off until you press Follow.
- **The hover peek** has no picker. It always follows, and shows the floor name in its header ("Cat Office · 12 claude-bar").
- **Zoom** (1×–3×) applies to the floor shown and resets when the floor changes.

## 7. Moving between floors (the elevator ride)

This follows Cat Office's sequence at **2× speed**, like the walking:

1. **Walk to the elevator:** an L-shaped walk with walk frames, as today, to a spot in front of the elevator door. Cats arriving together wait side by side, in 3 positions.
2. **Board:** the cat faces back-left and fades out over **0.35s**.
3. **Ride:** **0.7s + 0.35s per floor** traveled, hidden.
4. **Arrive:** on the other floor the cat fades in at that floor's elevator, facing front-right, over **0.35s**.
5. **Walk to its spot**, then the arrival hop.

- **What you see depends on which floor is shown:**
  - Showing the floor it leaves: steps 1–2, then it's gone.
  - Showing the floor it arrives on: steps 4–5. It appears there after the ride time, so its new spot stays empty until then.
  - With Follow on, a cat's move that makes Follow switch floors shows the **arrival** side.
- **Moves within a floor** use today's walking.
- **Reduce Motion:** cats switch floors instantly, with no ride or walk.

## 8. Units

| Unit | Role |
|---|---|
| `Building` (Core) | Parse `building.json` and `room-parts.json` into floors, desks, textures and the elevator kind |
| `FloorPlan` (Core, pure) | The floor for each agent; desk and spot assignment per floor; helper placement; the Follow target |
| `ElevatorTrip` (Core, pure) | Ride timings and phases over time for a move between two floors |
| `FloorPicker` (view) | Menu, ▲▼, Follow, strip |
| `FloorRoomView` (view) | One floor: backdrop, elevator, desks or lounge, cats, walkers and riders |
| `ArtCache` | Also loads floor and wall textures and wall-item art |

`PeekLayout`, the current desk row and `Lounge` are replaced by `FloorPlan` and `FloorRoomView`. Hover cards, zoom, labels, the night look, walking and desk placement carry over.

## 9. Build stages

1. **Floors and picker:** `Building`, `FloorPlan`, the picker with Follow, and the floor view using today's room art. Includes the helper placement fix.
2. **Floor look:** each floor's textures, the elevator with its number, the Lounge sign, and the 10-spot lounge.
3. **The elevator ride:** `ElevatorTrip`, riders on both sides, Follow showing arrivals.

## 10. Testing

- **Unit tests:**
  - parsing (`building.json` and `room-parts.json` excerpts)
  - floor assignment (idle, project match including subfolders, no project, helpers, missing parent)
  - desk assignment (reported design, stable slots, helpers nearest the parent, overflow)
  - the Follow target order
  - elevator ride phases and timings
- **Renders** (as today) of the Lounge, a project floor with helpers, the Desk pool, and a mid-ride capture on both the leaving and the arriving floor.
- **The click test** for the picker: only the menu button, ▲▼ and Follow are clicked.

## Out of scope

- Cat Office's exact isometric desk positions (u/v), and walking around furniture
- Creating, renaming or editing floors from ClaudeBar
- Elevator doors or sound (Cat Office has neither)

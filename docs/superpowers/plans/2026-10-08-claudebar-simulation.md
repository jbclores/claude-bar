# ClaudeBar Office Simulation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** With no Cat Office page visible, idle cats in ClaudeBar get coffee, read, nap and stretch by Cat Office's own rules.

**Architecture:** Faithful Core ports of Cat Office's `Rng`, activity table, needs (decay and gains), `chooseActivity`
and `createRoster`, checked against fixtures produced by Cat Office's own code. A Core `OfficeSim` runs the cycle
(choose → walk → use → gains) for idle session cats and spare cats, and emits an `OfficeMirror` (step 1's type: places
and spares), so the existing layout, walks, rides, hover cards and spare drawing are reused unchanged. `AppState` uses the
live mirror when there is one, else the sim's; it steps the sim only while the office is on screen and catches up (≤ 30
sim minutes) when it opens.

**Tech Stack:** Swift 6 toolchain (language mode 5), SwiftPM, Swift Testing; TypeScript run with `npx tsx` from the Cat
Office folder for fixtures.

**Spec:** `docs/superpowers/specs/2026-10-08-claudebar-simulation-design.md`

## Global Constraints

- The real Cat Office folder `~/Documents/projects/cat-ai-office-with-art-20261006-1038` is READ-ONLY (run `npx tsx`
  from it; write fixtures only into this repo).
- Never touch the real `~/.claude` / `~/.config/claude-bar`; never run the installed app.
- Ports match Cat Office exactly for the same inputs and seed (numbers within 1e-9); doc comments cite the source
  (`/// decision-engine.ts chooseActivity.`).
- Not ported: fires/panic, meetings, directives other than work/wait, inspector/debug tools.
- Nothing runs while the office (Office tab or hover peek) is closed; catch-up on open is capped at 30 sim minutes.
- The live mirror always wins over the sim.
- Spares only when "Show spare cats" is on; never in counts, busy strip, Follow, menu bar cat, "N working", sounds or
  notifications (step 1's rules hold for sim spares too).
- No layout built in: spots, floors and art from the connected Cat Office.
- Swift tools 6.0, language mode 5, macOS 14+; match surrounding style.

## Review Focus

1. A floor with no usable spots, or every spot taken: a cat waits (stands where it is) and tries again, never loops or
   crashes.
2. A spot on another floor: the cat rides the elevator (and the busy strip/Follow ignore spares).
3. A session flipping idle → working mid-walk: it leaves the sim and walks to its desk from where it is.
4. Mirror lost mid-activity: the sim continues the same activity with the minutes left; mirror back: no jump.
5. Opening the office after hours: catch-up is capped (no long freeze) and cats end on real spots.

---

## File Structure

| File | Responsibility |
|---|---|
| `scripts/sim-fixtures.ts` (new) | Cat Office's own Rng, ACTIVITIES, decay, chooseActivity, createRoster with fixed seeds → JSON |
| `Tests/ClaudeBarCoreTests/Fixtures/sim/expected.json` (new) | Fixture data |
| `Sources/ClaudeBarCore/Sim/SimRng.swift`, `SimActivities.swift`, `SimNeeds.swift`, `SimChoice.swift`, `SpareRoster.swift` (new) | Section 1 ports |
| `Sources/ClaudeBarCore/Sim/OfficeSim.swift` (new) | The cycle, claims, stepping, catch-up, seeding, output |
| `Tests/ClaudeBarCoreTests/SimPortTests.swift`, `OfficeSimTests.swift` (new) | Tests |
| `Sources/ClaudeBar/AppState.swift` | Owns the sim; steps it while visible; mirror-or-sim input |

---

### Task 1: Fixtures from Cat Office's own simulation code

- [ ] Read (read-only) `src/simulation/rng.ts`, `activities.ts`, `decision-engine.ts`, `simulation-engine.ts`
  (`decayNeeds`, `DECAY`, `NEED_KEYS`, starting needs, gains application, phase timing / walk speed / `using`
  duration draws), `src/agents/agent.registry.ts` (`createRoster`, names, roles) and `agent.types.ts` (Needs, CatState).
  Write what you found (file:line) for each in the report — later tasks port from it.
- [ ] Write `scripts/sim-fixtures.ts` (same style as `scripts/room-fixtures.ts`; imports Cat Office modules by path from
  the current directory) that writes `{ activities, rng: [{seed, values: 50 nexts and 20 range(0, 0.15)}],
  decay: [{state, needs0, minutes, needs}], choices: [{seed, floorId, position, needs, minutesSinceWork, choice: {floor,
  spotId, kind} | null}], roster: [...] }` for the user's building (`Tests/ClaudeBarCoreTests/Fixtures/rooms/user/`:
  building.json + room-parts/props/desks/cats.json — copy cats.json from the Cat Office folder into the fixture folder
  if missing) and a fixed list of seeds (1, 2, 3, 42, 20261001), needs sets (all 50; one low each; all low) and floors
  (1, 2, 12) × positions (two per floor). Use the floors the browser walks (`buildRoomOffice(...).building`, as
  room-fixtures.ts does) so spots match.
- [ ] Run it from the Cat Office folder: `npx tsx ~/Documents/projects/claude-bar/scripts/sim-fixtures.ts <in-dir> <out.json>`;
  check the JSON (non-empty sections; at least one null choice if a needs set can't be relieved — else note it).
- [ ] Commit `scripts/sim-fixtures.ts` and the fixture: "test: fixtures from Cat Office's simulation code".

### Task 2: The ports (Core)

**Produces** (`public` where the app needs them):
- `struct SimRng { init(seed: UInt32); mutating func next() -> Double; mutating func range(_ a: Double, _ b: Double) -> Double; mutating func int(...) }` (exactly rng.ts's algorithm and API surface used by the engine)
- `struct SimActivity` + `enum SimActivities { static let all: [String: SimActivity] }` (rng.ts/activities.ts field for field)
- `struct SimNeeds` (the need keys as fields or a dictionary), `static func decayed(_:state:minutes:) -> SimNeeds`, `func gained(_ activity:, fraction:) -> SimNeeds`, starting values
- `enum SimChoice { static func choose(floors:, spots:, floorId:, position:, needs:, minutesSinceWork:, rng: inout SimRng, frame/pxDistance inputs) -> (floorId: Int, spotId: String, kind: String)? }`
- `enum SpareRoster { static func roster(building:, catIds:, names:...) -> [SpareCat] }` (`SpareCat`: id, name, catId)

- [ ] Tests first (`SimPortTests`) driven by `Fixtures/sim/expected.json`: every activity field equal; Rng sequences
  equal; decay equal within 1e-9; every recorded choice equal (floor, spot id, kind, or nil); roster equal. Spots for
  the choice tests come from ClaudeBar's `RoomGeometry` on the user fixture building (the same spots the browser
  walks — if ids differ, stop and report NEEDS_CONTEXT with the difference).
- [ ] Implement each port line by line; `swift test`; commit "feat: ports of Cat Office's simulation rules".

### Task 3: `OfficeSim` (Core)

**Produces:**
```swift
public struct SimCat: Equatable, Sendable { public var id: String; public var isSpare: Bool; public var name: String?; public var catId: String? }
public final class OfficeSim {   // or a struct with mutating API
    public init(seed: UInt32)
    /// Cats to simulate now: idle session agents (ids) and, when on, spares. Working/waiting cats are dropped.
    public func setCats(_ cats: [SimCat], building: Building, rooms: [Int: BuiltRoom], grids: [Int: NavGrid])
    /// Starts each listed cat from a mirrored place (activity and minutes left kept).
    public func seed(from mirror: OfficeMirror)
    /// Advances sim time by `minutes` (1 sim minute = 1 real second at ×1).
    public func step(minutes: Double)
    /// Catch-up: steps `min(elapsed, 30)` minutes in small steps without producing walks.
    public func catchUp(minutes: Double)
    /// The layout's input: places for session cats and spares, as step 1's mirror type.
    public func output(showSpares: Bool) -> OfficeMirror
}
```
- [ ] Tests first (`OfficeSimTests`, fixed seeds, the user fixture building): one idle cat completes choose → walk
  (time = route length / Cat Office's walk speed) → use (duration within the activity's range) → needs gained → chooses
  again; a spot on another floor: the cat's place reports `phase` elevator / `ridingTo` before arriving; two cats never
  claim the same spot; a floor with no free spot: the cat waits and retries (no crash, bounded); `setCats` dropping a
  cat mid-walk removes it from the output; `seed(from:)` keeps activity, spot and minutes left; `catchUp(120)` advances
  exactly 30 minutes; `step` is the only thing that advances time; output's spares empty unless `showSpares`.
- [ ] Implement (reuse `NavGrid.findPath` for walk lengths/legs and the ports from Task 2); `swift test`; commit
  "feat: OfficeSim, Cat Office's office life in ClaudeBar".

### Task 4: AppState runs it

- [ ] `AppState` owns an `OfficeSim` (seeded from `UInt32.random` at launch, or `CLAUDEBAR_SIM_SEED` in renders).
  - Cats: idle session agents (status idle; working/waiting excluded) plus the spare roster when the switch is on.
  - While the office is on screen (`officeVisible`), a timer steps it (e.g. every 0.25 s, 0.25 sim min), and
    `mirror = liveMirror ?? sim.output(showSpares:)`.
  - On becoming visible: `catchUp(minutes: seconds since last step)` first.
  - When the live mirror goes away: `sim.seed(from: lastLiveMirror)`.
  - While not visible: no timer.
- [ ] Tests where logic is in Core; for the app glue, a render sequence: `CLAUDEBAR_SIM_SEED=42` with live data, Office
  tab rendered after N simulated seconds (add a render-only `CLAUDEBAR_SIM_ADVANCE=<minutes>` that calls `catchUp`);
  read the PNGs (Lounge and a project floor): cats at coffee / reading / asleep on real spots.
- [ ] Check nothing runs closed: with the office not visible, the step timer is nil (assert in a small test seam or a
  render log line).
- [ ] Guide: "With no Cat Office page open, ClaudeBar's cats keep busy on their own (coffee, books, naps) by Cat Office's
  rules; with a page open they follow it exactly."
- [ ] `swift test`, build, the four click tests; commit "feat: ClaudeBar's office keeps busy on its own".

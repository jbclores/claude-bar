# ClaudeBar's Own Office Simulation — Design

**Date:** 2026-10-08
**Status:** Draft, awaiting review
**Step 2 of 2.** Builds on step 1, `2026-10-08-claudebar-mirror-design.md` (the mirror, spare cats, the switch), and on
exact floors and walking around furniture.

## Goal

With no Cat Office page visible, idle cats in ClaudeBar behave like Cat Office's: they get coffee, read, nap and
stretch at the user's own office's spots, by Cat Office's own rules and timing, instead of all sleeping in the Lounge.

**Success criteria**

- ClaudeBar's port gives the same answers as Cat Office's code for the same inputs and seed: the activity table, need
  decay, and the choice of activity (checked against fixtures from Cat Office's own code).
- Idle session cats (and spare cats when "Show spare cats" is on) choose, walk to, use and leave spots in a cycle;
  working and waiting cats stay at their desks.
- While a Cat Office page is visible, the mirror wins; handing over either way doesn't make cats jump.
- Nothing runs while ClaudeBar's office is closed; opening it catches up at once.
- No layout is built in: spots, floors and art come from the connected Cat Office.

## 1. What's ported (Core)

From Cat Office (`src/simulation/`, `src/agents/agent.registry.ts`), line by line with the same numbers:

- **`Rng`** (`rng.ts`): the same generator, so a seed gives the same sequence.
- **Activities** (`activities.ts`): every activity's kind, label, state, gesture, expression, arrival pose, duration
  range (sim minutes), need gains, lounge flag and `asleep`. This table lives in Cat Office's code, not its data, so
  ClaudeBar carries a copy; the fixture check (section 5) notices when Cat Office's table changes.
- **Needs**: the needs, their starting values and decay per sim minute (the engine's `decayNeeds`), and the gains when
  an activity finishes.
- **Choosing** (`decision-engine.ts` `chooseActivity`): every usable spot on every floor scored by need relief (or time
  since work for desks), minus 0.08 per floor away and a distance term, plus `rng.range(0, 0.15)`; the best wins.
- **The spare roster** (`agent.registry.ts` `createRoster`): which spare cats exist, their names and art, from the
  building and `cats.json`.

**Not ported:** fires and panic, meetings, directives other than work/wait, the inspector and debug tools.

## 2. What a cat does (Core `OfficeSim`)

- **Who:** idle session cats; spare cats when "Show spare cats" is on. Working and waiting session cats are placed by
  today's rules (at their desks). A session that starts working leaves the simulation and walks to its desk; one that
  goes idle joins it from where it stands.
- **The cycle:** choose (section 1) → walk there (the walking grid; Cat Office's walk speed; the elevator for another
  floor) → use the spot for a duration drawn from its range, in its pose, after its arrival pose → apply the gains →
  choose again.
- **Spots** come from the built rooms (`BuiltRoom` props, rugs, seats and their spots), with their kinds; a spot in use
  isn't chosen by another cat.
- **Output** for the layout: per cat, floor, floor point, facing, pose, activity and minutes left — the same shape as a
  mirrored place, so the layout, walks, rides, hover card ("Coffee break · 4 min left") and spare drawing are reused.

## 3. Time, hand-over, battery

- **Clock:** one sim minute per real second (Cat Office at ×1), stepped a few times a second, only while the office
  (Office tab or hover peek) is on screen.
- **Closed:** nothing runs. **Opening:** the elapsed time, capped at 30 sim minutes, is simulated at once without
  animation; cats appear where that leaves them.
- **Launch:** needs start at varied mid values; each launch has a new seed (tests use fixed seeds).
- **Mirror live:** the mirror wins; the simulation pauses. **Mirror lost:** the simulation starts from each cat's last
  mirrored place, activity and minutes left. **Mirror back:** cats walk to the browser's places (step 1's behaviour).

## 4. Units

| Unit | Role |
|---|---|
| `SimRng`, `SimActivities`, `SimNeeds`, `SimChoice` (Core) | Section 1 ports |
| `SpareRoster` (Core) | `createRoster` port |
| `OfficeSim` (Core) | Section 2: cats, cycle, spot claims, stepping, catch-up, seeding from the mirror |
| `AppState` | Owns the sim; steps it while the office is visible; feeds its places into the layout when the mirror isn't live |
| `scripts/sim-fixtures.ts` (new) | Runs Cat Office's own code with fixed seeds and writes fixtures |

## 5. Testing

- **Fixtures** from Cat Office's own code (`scripts/sim-fixtures.ts`, run by hand from a Cat Office folder, like the
  room fixtures): the activity table; `Rng` sequences for fixed seeds; need values after N minutes of decay; and
  `chooseActivity` results for fixed seeds, needs, positions and floors on the user's building. ClaudeBar's port must
  match exactly (numbers within 1e-9).
- **Unit tests:** a cat's full cycle (choose → walk → use → gains → choose); a spot on another floor uses the elevator;
  a claimed spot isn't chosen twice; working/idle hand-offs; seeding from mirrored places; the 30-minute catch-up;
  nothing steps while the office is closed; spares only with the switch, never in counts, Follow, the menu bar cat,
  "N working", sounds or notifications.
- **Renders** of a simulated Lounge and a project floor; all existing tests pass.

## Out of scope

- Fires, panic, meetings.
- Matching the browser's exact moment-to-moment state without a page (impossible: each side chooses at random).
- Running while the office is closed.

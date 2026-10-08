# ClaudeBar Mirrors What Cats Are Doing — Design

**Date:** 2026-10-08
**Status:** Draft, awaiting review
**Builds on:** the Cat Office patch (cat and desk assignments shared through `/__agents/cats`), exact floors, walking
around furniture, name tags.
**Step 1 of 2.** Step 2 (later, its own design): a copy of Cat Office's simulation in ClaudeBar for when no Cat Office
page is open.

## Goal

While a Cat Office page is open in a browser, every cat in ClaudeBar is where the browser has it, doing what the
browser has it doing: same floor, same spot, same activity and pose, idle cats included.

**Success criteria**

- Side by side with an open Cat Office page, each session's cat in ClaudeBar is on the same floor and spot, facing the
  same way, in the same pose, within a couple of seconds.
- With no Cat Office page open, or with an older patch, ClaudeBar behaves exactly as today.
- Spare cats (the browser's office cats with no session) appear only when the user turns them on.
- Nothing new runs while the office isn't on screen; no new connection.

## Background

Cat Office simulates its cats in the browser page (`src/simulation/simulation-engine.ts`): idle cats have needs and
pick activities (coffee, water, printing, meetings, watering plants, napping, lounging, climbing, reading, browsing
books, snacking, stretching), partly at random. That state lives only in the page (`engine.snapshot()`,
`engine.places()`); Cat Office's server never sees it. ClaudeBar today places cats by its own rules (working at a desk,
idle asleep in the Lounge), so the two often disagree.

## 1. What the page shares (Cat Office patch)

- Every 2 s while a Cat Office page is open, the page posts to `/__agents/cats` (as it already does for assignments and
  desks, with the same token): `{ "places": { <cat key>: Place }, "at": <ms> }` where each `Place` is, from
  `engine.snapshot()`:
  - `session`: the Claude session id the cat belongs to, or null for a spare cat; `name`: the cat's own name;
    `catId` (its art)
  - `floor`, `u`, `v` (position on the floor), `direction`
  - `state`, `gesture`, `expression`, `asleep` (from the activity), `activity`: `{ kind, label }` or null,
    `spotId`, `minutesLeft`
  - `phase`: walking / using / elevator (and `ridingTo`)
- The bridge keeps the latest places (per cat, newest `at` wins across several open pages) in memory and adds them,
  with their `at`, to what ClaudeBar already reads. Spare cats are always included, marked `session: null`.
- A new patch version. Setup's upgrade path takes out the older version and applies the new one; Cat Office restarts
  once (the usual warning).

## 2. What ClaudeBar draws

- **Mirror live** (places received within the last 10 s):
  - Each session's cat is drawn at its mirrored floor and spot (`u`, `v` through the floor frame), facing `direction`,
    in the pose from `state` / `gesture` / `asleep` (typing, standing, sitting, asleep), lifted on a seat as today.
  - Floors, the busy strip, Follow and the floor menu count session cats where the browser has them.
  - Between updates a cat that moved walks from where it was to its new place (the walking grid; normal speed). A
    floor change (`phase` elevator, `ridingTo`) is ClaudeBar's elevator ride.
  - The hover card adds the activity: "Coffee break · 4 min left".
  - Unchanged: name tags, status rings, the "!" bubble, sounds, notifications, the menu bar cat, "N working".
- **Mirror not live:** today's rules. When the mirror stops, cats walk from their last mirrored place to their usual one.
- **Spare cats** (`session: null`): shown only when Settings → General → **Show spare cats** is on (off at first) and
  the mirror is live. Their tag shows the cat's name in a lighter style; no status ring and no "!"; the hover card
  shows the name and activity. They don't count in floor counts, Follow, the menu bar cat, "N working", sounds or
  notifications.

## 3. Units

| Unit | Role |
|---|---|
| Patch: `src/agents/live/places-share.ts` (new) + bridge store | Section 1 |
| `MirrorPlaces` (Core) | Parse places; live or not (10 s); session cats and spare cats; pose and floor mapping |
| Office layout (`SceneCast` / seating) | Mirrored places win over the rules for session cats while live |
| Walks | Walk between consecutive mirrored places (WalkRouter) |
| Settings | "Show spare cats" (`office.spareCats`, off) |
| Hover card | Activity line |

## 4. Testing

- **Patch:** the sharing code tested in Cat Office's own test runner on a temporary copy (never the real Cat Office
  folder); the patch applies, upgrades and undoes cleanly (scripts/test-setup-scripts.sh).
- **Core unit tests:** parsing; the 10 s timeout; newest wins; session vs spare cats; pose mapping (typing, standing,
  sitting, asleep); floor mapping; fallback to the rules; walking between two updates.
- **Renders:** a mirrored office with cats at coffee, reading and asleep (from a recorded places sample); spare cats on
  and off.
- **Existing tests** (click, zoom, setup, undo, walking fixtures) still pass.
- **Msys's check** after install: side by side with the browser.

## Out of scope

- Step 2: ClaudeBar's own simulation when no page is open.
- Spare cats while no page is open (they exist only in the browser's simulation until step 2).
- Changing what the browser does.

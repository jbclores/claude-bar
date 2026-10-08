# ClaudeBar Mirror Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** While a Cat Office page is open, ClaudeBar draws each session's cat where the browser has it, doing what it's doing; spare cats on request.

**Architecture:** The Cat Office patch gains a page module that posts each cat's place from `engine.snapshot()` every
2 s to `/__agents/cats`, and the bridge keeps the newest places in memory and attaches them to the agents snapshot
ClaudeBar already streams (`place` on each agent, `spares` and `placesAt` at the top). ClaudeBar parses them
(`MirrorPlaces`, Core), and while they're fresh (≤ 10 s) its office layout puts session cats at their mirrored floor,
spot and pose instead of its own rules; existing walk and ride machinery animates the moves. A Settings switch shows
spare cats.

**Tech Stack:** TypeScript (Cat Office patch: Vite/React page, Node bridge, `npm run test:sim` with tsx); Swift 6
toolchain (language mode 5), SwiftPM, Swift Testing, SwiftUI.

**Spec:** `docs/superpowers/specs/2026-10-08-claudebar-mirror-design.md`

## Global Constraints

- The real Cat Office folder `~/Documents/projects/cat-ai-office-with-art-20261006-1038` is READ-ONLY. Patch work
  happens on temporary copies (`/tmp/co-pristine`, `/tmp/co-patched`), and the result lands only in this repo's
  `patches/cat-office.patch`. Applying it to the real folder is done later by Msys through setup, never by a task.
- Never touch the real `~/.claude` or `~/.config/claude-bar`; never run the installed app.
- Mirror live = places received within 10 s (`placesAt` vs now). Not live → today's behaviour, unchanged.
- Spare cats: only with Settings → General → "Show spare cats" on (config `office.spareCats`, default false) AND the
  mirror live. Never in floor counts, the busy strip, Follow, the menu bar cat, "N working", sounds or notifications.
- No new connection: places arrive in the agents snapshot/stream ClaudeBar already reads.
- An older patch (no `place` / `spares`) must parse exactly as today.
- Swift tools 6.0, language mode 5, macOS 14+; match surrounding style; doc comments cite Cat Office sources.

## Review Focus

1. An older Cat Office (no places) or a page closed for > 10 s: ClaudeBar behaves exactly as today.
2. Two open pages posting different places: the newest `at` per cat wins; no flicker between them.
3. A mirrored place on a floor ClaudeBar has no room for, or a point off the floor: the cat falls back to today's rule
   placement, never disappears or draws off-floor.
4. A session whose cat the page hasn't assigned yet (no place): today's rule placement for that cat only.
5. Spare cats never leak into counts, Follow, sounds, notifications or the menu bar cat, with the switch on.

---

## File Structure

| File | Responsibility |
|---|---|
| Patch (temp copy) `src/agents/live/places-share.ts` (new) | Build places from `engine.snapshot()` + session mapping; post every 2 s |
| Patch `src/agents/live/useAgentCats.ts` or `src/app/App.tsx` (hook) | Start sharing with the engine and mapping |
| Patch `server/agent-bridge/cat-assignments.ts` | Keep newest places in memory; attach `place`, `spares`, `placesAt` |
| Patch `tests/sim/places.test.ts` (new) | Bridge merge/attach and page builder tests |
| `scripts/make-cat-office-patch.sh` | Add the new files to FILES |
| `patches/cat-office.patch` | Regenerated |
| `Sources/ClaudeBarCore/MirrorPlaces.swift` (new) | Types, parsing, liveness, pose mapping |
| `Sources/ClaudeBarCore/OfficeAgent.swift` | `OfficeAgent.place`, `OfficeSnapshot.spares`, `placesAt` |
| Office layout (Core seating/FloorPlan + `SceneCast` in Views) | Mirrored places win while live |
| `Sources/ClaudeBar/Views/*` | Spare cats, hover activity line, Settings switch |
| `Resources/Help/guide.html` | A line on mirroring and spare cats |

---

### Task 1: The patch shares places (Cat Office side, temp copies only)

**Files:** patch files above (in `/tmp/co-patched`), `scripts/make-cat-office-patch.sh`, `patches/cat-office.patch`.

**Interfaces:**
- Produces, in the agents snapshot JSON (GET `/__agents` and the stream):
  - per agent: `"place": { "floor": Int, "u": Double, "v": Double, "direction": String, "state": String,
    "gesture": String, "expression": String, "asleep": Bool, "activity": {"kind": String, "label": String} | null,
    "spotId": String | null, "minutesLeft": Double | null, "phase": "walking"|"using"|"elevator"|"idle",
    "ridingTo": Int | null, "catId": String, "at": Double(ms) }` — present only when the page reported it.
  - top level: `"spares": [ Place & { "key": String, "name": String } ]`, `"placesAt": Double(ms) | null` (newest at).
- Page posts `{ "places": { <live agent id or "spare:<sim id>">: Place & {name} }, "at": ms }` to `/__agents/cats`
  every 2000 ms while the page is visible-or-not (the engine runs), with the existing token header (actions.ts `post`).

- [ ] **Step 1: Temp copies.** `rm -rf /tmp/co-pristine /tmp/co-patched; mkdir -p /tmp/co-pristine /tmp/co-patched`;
  `rsync -a --exclude node_modules --exclude .cat-office ~/Documents/projects/cat-ai-office-with-art-20261006-1038/ /tmp/co-patched/`;
  symlink `node_modules` from the real folder into `/tmp/co-patched` (read-only use). Make the pristine copy by copying
  `/tmp/co-patched` to `/tmp/co-pristine` and reversing the current patch there (`patch -p1 -R < patches/cat-office.patch`,
  with `-E`); check the current patch reverses cleanly on `/tmp/co-patched` too (it's patched already) — the real
  folder is patched, so `/tmp/co-patched` starts patched. Record both checks in the report.
- [ ] **Step 2: Failing tests** `tests/sim/places.test.ts` (in /tmp/co-patched; read `tests/sim/run.ts` and
  `tests/sim/cat-assignments.test.ts` for the runner's conventions): (a) bridge: merging `{places, at}` keeps the newest
  `at` per key; an older post doesn't overwrite a newer place; malformed places are ignored (bad ids by the existing
  `ID` regex, non-finite numbers); the snapshot decorator attaches `place` to the matching agent, lists `spare:` keys in
  `spares`, sets `placesAt`; (b) page builder: from a fake `SimSnapshot` and an `agentOf` map, session cats get their
  live agent id as key, spare cats `spare:<sim id>`, and the fields above are copied (u, v from `position`; `asleep`
  from the activity def; `phase` mapped from the engine's phase label). Run `npm run test:sim` in /tmp/co-patched:
  the new tests fail.
- [ ] **Step 3: Implement** in /tmp/co-patched: the store and decorator in `server/agent-bridge/cat-assignments.ts`
  (in memory only — places aren't persisted; keep at most 500 keys; drop entries older than 60 s when merging); the
  `merge(body)` path accepts `places`; `src/agents/live/places-share.ts` exporting a pure `buildPlaces(snapshot, agentOf)`
  and a `usePlacesShare(engine, agentOf, on)` hook (setInterval 2000 ms; clear on unmount); hook it where
  `useAgentCats`' `agentOf` and the engine are both available (App / RoomSimulator — follow how warm-start is wired).
- [ ] **Step 4:** `npm run test:sim` in /tmp/co-patched: all pass (the existing ones too). Also `npx tsc --noEmit -p .`
  if the project has a tsconfig check script (see package.json); report what you ran.
- [ ] **Step 5: Regenerate the patch.** Add `src/agents/live/places-share.ts` and `tests/sim/places.test.ts` (and any
  other touched file) to FILES in `scripts/make-cat-office-patch.sh`; run
  `bash scripts/make-cat-office-patch.sh /tmp/co-pristine /tmp/co-patched`. Check: the new patch applies cleanly to a
  fresh copy of /tmp/co-pristine and reverses cleanly; then `bash scripts/test-setup-scripts.sh /tmp/co-patched-src`
  where that folder is a copy of the REAL folder (read-only source) — expected all pass, including "upgrades an older
  patch" (the previous patch version is in git history).
- [ ] **Step 6: Commit** (this repo only): `scripts/make-cat-office-patch.sh`, `patches/cat-office.patch`:
  "feat(patch): Cat Office shares where each cat is and what it's doing".

### Task 2: ClaudeBar reads the places (Core)

**Files:** `Sources/ClaudeBarCore/MirrorPlaces.swift` (new), `Sources/ClaudeBarCore/OfficeAgent.swift`,
`Tests/ClaudeBarCoreTests/MirrorPlacesTests.swift` (new).

**Interfaces (produces):**
```swift
public struct MirrorPlace: Equatable, Sendable, Decodable {
    public var floor: Int; public var u: Double; public var v: Double; public var direction: String
    public var state: String; public var gesture: String; public var expression: String; public var asleep: Bool
    public struct Activity: Equatable, Sendable, Decodable { public var kind: String; public var label: String }
    public var activity: Activity?; public var spotId: String?; public var minutesLeft: Double?
    public var phase: String; public var ridingTo: Int?; public var catId: String?; public var at: Double
    public var name: String?; public var key: String?
    /// typing / standing / sitting / asleep, from state, gesture and asleep (Cat Office's CatState values).
    public var pose: MirrorPose { get }
}
public enum MirrorPose: Equatable, Sendable { case typing, standing, sitting, asleep }
public enum MirrorPlaces {
    public static let liveFor: TimeInterval = 10
    /// The mirror is live: newest place within `liveFor` of `now` (placesAt in ms since 1970).
    public static func isLive(placesAt: Double?, now: Date) -> Bool
}
// OfficeAgent: public var place: MirrorPlace?   OfficeSnapshot: public var spares: [MirrorPlace]; public var placesAt: Double?
```
- [ ] Tests first: decoding a snapshot with and without places (old patch → nil/empty, nothing else changes — use an
  existing OfficeAgent decode fixture); `isLive` at 9.9 s / 10.1 s / nil / future `at` (clock skew: treat ≤ 1 s ahead
  as live, more as not); pose mapping for Cat Office's states (read `src/agents/agent.types.ts` CatState and
  `activities.ts` in the real folder, read-only, and cover each: working → typing, asleep/napping → asleep, sitting
  activities (lounging, reading…) → sitting, others → standing); non-finite u/v rejected at decode.
- [ ] Implement, run `swift test`, commit "feat: ClaudeBar reads where Cat Office's cats are".

### Task 3: The office follows the mirror

**Files:** Core seating/floor code (find where `FloorPlan.floorId(for:among:in:)`, `FloorPlan.cats(on:)` and the
scene's seat/desk placement (`SceneCast` / `FloorSeating`) decide each cat's floor and point), the views that build
`SceneCat`s; tests in Core.

- [ ] Tests first (Core): with a live mirror, a session agent's floor is its `place.floor` (when that floor exists),
  its point is `(u, v)` and its pose the mirrored pose; with a stale mirror or no place, today's result exactly; a place
  on an unknown floor or off the floor (u/v outside 0…1) → today's result; spare places never appear in
  `FloorPlan.cats(on:)` / activity / Follow inputs.
- [ ] Implement with a single "mirror" input threaded from AppState (snapshot + now) into the layout, so views stay
  simple. Lift: a mirrored point on a seat spot (`spotId` matching a `RoomSpot.id` in the built room) uses that seat's
  lift, else 0. Facing from `direction`.
- [ ] Walks and rides: confirm the existing machinery animates a mirrored move (feet change → walk; floor change →
  ride). Render a sequence with a recorded places sample (add a render-only env `CLAUDEBAR_RENDER_PLACES=<json file>`
  that injects places into the snapshot, like the other CLAUDEBAR_RENDER_* hooks) and read the PNGs.
- [ ] `swift test`, build, click tests (`--test-tabs`, `--test-zoom`); commit "feat: the office mirrors the browser's cats".

### Task 4: Spare cats, the activity line, the switch, the guide

**Files:** config (`Config.swift` `office.spareCats`), `AppState` setter, `DropdownView` Settings General switch "Show
spare cats", the scene (draw spares: their own `catId` art, lighter name tag with `name`, no ring, no "!"), the cat hover
card (activity line "Coffee break · 4 min left"; spares: name + activity), `Resources/Help/guide.html`.

- [ ] Tests first: config parse/default false; spares filtered out unless the switch is on AND live; spares excluded
  from counts/Follow/menu bar/working/sounds (assert on the Core functions those use); activity line text (minutes
  rounded up; none when no activity).
- [ ] Implement; render with the places sample, switch off and on; read the PNGs.
- [ ] Guide: under Office, "While a Cat Office page is open, ClaudeBar shows each cat where the browser has it, doing
  the same thing. Settings → Show spare cats adds the office's own cats too."
- [ ] `swift test`, build, all click tests; commit "feat: spare cats on request, and what each cat is doing".

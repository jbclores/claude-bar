# ClaudeBar — Design

**Date:** 2026-10-06
**Status:** Draft, awaiting review (revision 2: adds the Cat Office integration)

## Goal

A macOS menu bar app that works like the Claude Code status line, but for several projects at once, and also gives a glance at Cat Office without opening the browser.

- **Projects:** for a fixed list of project folders, show the git branch, the Claude model, context-window usage, and whether a session is working, waiting or idle. Show the account-wide 5-hour and 7-day usage once.
- **Cat Office:** hovering over the menu bar icon shows a tiny visual office: Cat Office's own cat sprites at desks, posed by status. A "View more" link opens Cat Office in the browser.

**Audience:** one user, on this Mac. ClaudeBar reads data and never controls Claude Code sessions or Cat Office agents. Its one action is starting Cat Office's dev server when it isn't running (see §3a).

**Success criteria**

- The menu bar always shows the latest known 5h and 7d percentages, plus a "your turn" dot when a session needs attention.
- Clicking the icon lists every pinned folder with its branch. It also shows the model, context % and status of the folder's newest session, live or last seen (dimmed, with how long ago).
- Hovering over the icon shows the tiny office, and each agent appears as the same cat the browser shows.
- Folders can be added from the app or by editing a config file, and both stay in sync.
- The terminal status line looks exactly as it does today.
- Everything except the office peek keeps working when Cat Office isn't running.

## Architecture

```
Claude Code ──stdin JSON──▶ statusline-command.sh ──▶ terminal status line (unchanged)
                                   └─ writes ─▶ ~/.claude/claude-bar/sessions/<session_id>.json ─┐
~/.config/claude-bar/projects.json ◀──── reads/writes ───────────────────────────────┐         │
~/.claude/sessions/<pid>.json ─────────── reads (fallback status) ─────────────────▶ ClaudeBar.app
<project>/.git ─────────────────────────── git rev-parse ──────────────────────────▶   │
Cat Office (localhost:5173) ── SSE /__agents/stream, /assets/*, /data/*.json ──────▶   │
~/.cat-office/bridge.json ─────────────── port + token + folder ───────────────────▶ ──┘
```

Data comes from three sources, and each covers what the others don't:

| Data | Source |
|---|---|
| context % | status line snapshots (the only source) |
| 5h %, 7d %, reset times | the newer of the status line snapshots and `~/.cat-office/plan-usage.json` (written by the status line and, with the patch, by Cat Office's headless workers from each turn's `rate_limit_event`) |
| model | status line snapshots; also the Cat Office feed when it's running |
| status (working / waiting / idle / ended) | Cat Office feed; otherwise `~/.claude/sessions` |
| branch | `git` for pinned folders; the feed's `branch` for office agents |
| office agents, task, last action, cat | Cat Office feed only |

### 1. Snapshot writer (change to `~/.claude/statusline-command.sh`)

On every status line redraw, the script also writes one JSON file per session:

`~/.claude/claude-bar/sessions/<session_id>.json`

```json
{
  "session_id": "a08f04cc-…",
  "cwd": "/Users/…/pnp-ufdms-base-admin",
  "model": "Opus 5.5",
  "context_pct": 61.2,
  "five_hour_pct": 42.0,
  "five_hour_resets_at": "2026-10-06T14:00:00Z",
  "seven_day_pct": 18.0,
  "seven_day_resets_at": "2026-10-09T01:00:00Z",
  "updated_at": 1791266721
}
```

- The values come from status line input fields the script already reads: `session_id`, `workspace.current_dir`/`cwd`, `model.display_name`, `context_window.used_percentage`, and `rate_limits.{five_hour,seven_day}.used_percentage`.
- Reset times are copied from `rate_limits.*.resets_at` if Claude Code provides them, and are otherwise `null`. Claude Code's real input will be checked during implementation.
- `updated_at` is Unix seconds at the moment of writing.
- The file is written to a temp file in the same directory and then renamed over the target, so the app never reads a half-written file.
- Missing fields are written as `null`. If `session_id` is missing, nothing is written.
- Write failures are ignored, so the status line output is never affected.
- The existing inline `python3` parsing is extended to produce this file. No new dependencies are added.
- Headless sessions (Cat Office workers run `claude -p`) probably never run the status line, so they won't produce snapshots. Their model then comes from the Cat Office feed, and their context % shows as "—".

### 2. Config file

`~/.config/claude-bar/projects.json`

```json
{
  "projects": [
    { "path": "~/Documents/projects/pnp-ufdms-base-admin" },
    { "path": "~/dotfiles", "name": "dotfiles" }
  ],
  "catOffice": { "dir": "~/Downloads/cat-ai-office-with-art-20261006-1038", "url": "http://localhost:5173" },
  "notifications": true
}
```

`catOffice.autoStart` (default `true`) controls starting Cat Office when ClaudeBar launches (§3a).

- `path` is required, and `~` is expanded. `name` is optional and defaults to the folder's base name.
- `catOffice.dir` is an optional override for the folder to start Cat Office from; without it (or when it no longer exists) ClaudeBar uses the folder the patched Cat Office last reported in `~/.cat-office/bridge.json`, remembered in ClaudeBar's preferences. `catOffice.url` is used when no running Cat Office has written `bridge.json`. Both are optional.
- The app creates the file with an empty project list if it doesn't exist.
- The app re-reads the file when its modification time changes, checked on each 5-second poll.
- If the file can't be parsed, the app keeps the last good config and shows a warning row: "Config error — using last good list".
- "Add Folder…" and the remove button rewrite the file atomically, keeping the order and any other keys. Adding a path that's already in the list does nothing.

### 3. Cat Office client

- **Finding the server:** read `~/.cat-office/bridge.json` (`{url, token, dir, pid}`, written by the patch in §5). Each connection made through it records `dir` as the remembered Cat Office folder.
  - The file only counts if its `pid` process is still running.
  - Without a usable `bridge.json` (for example, an unpatched Cat Office), fall back to `GET <url>/` and pull the token out of `window.__CAT_OFFICE_TOKEN__ = "…"` in the page.
- **Live feed:** connect to `GET <url>/__agents/stream` with the `x-cat-office-token` header and parse server-sent events. A `snapshot` event replaces the current agent list; `ping` events are ignored.
  - On disconnect, 401 or 403: get the server details and token again, then reconnect after 2s, 4s, 8s … up to a 30s maximum.
- **No Origin header** is sent. Cat Office's access check allows loopback requests with a local Host header and no Origin.
- **Data used from each `LiveAgent`:** `id`, `name`, `owner`, `status`, `waitReason`, `cwd`, `repo`, `branch`, `model`, `task`, `lastAction`, `waitingSince`, `sessionId`, `cat` (added by the patch). The `claude.hindered` health flag is also used.
- **Down state:** if Cat Office can't be reached, `officeState = .offline`. The peek and the dropdown's Office section show "Cat Office isn't running", and status falls back to `~/.claude/sessions`.

### 3a. Starting Cat Office

- **When:** once, a few seconds after ClaudeBar launches, if `catOffice.autoStart` (default `true`) is on and Cat Office can't be reached. After that, only when the user clicks **Start Cat Office**, which the Office section and the peek show while Cat Office is offline. ClaudeBar never restarts it on its own after it stops.
- **How:** run `npm run dev` as a background process in `catOffice.dir` if that folder exists, else in the folder Cat Office was last seen running from.
  - `PATH` is made terminal-like, because apps opened from Finder don't inherit the shell's `PATH` and Cat Office passes it on to its agents and tools: the folder holding `npm`/`node` (found by checking `/opt/homebrew/bin`, `/usr/local/bin`, `~/.volta/bin` and the newest `~/.nvm/versions/node/*/bin`), then `~/.local/bin`, `/opt/homebrew/bin`, `/opt/homebrew/sbin`, `/usr/local/bin`, then the login shell's `PATH` (read with a 3s timeout), then the app's own.
  - Output is appended to `~/Library/Logs/ClaudeBar/cat-office.log`.
  - stdin is `/dev/null`.
  - Cat Office keeps running when ClaudeBar quits.
- **Guard:** before starting, `GET <url>/` with a 2s timeout. If anything answers, ClaudeBar starts nothing.
- **States:**
  - `starting` shows "Starting Cat Office…".
  - It returns to normal as soon as the feed connects.
  - If the feed hasn't connected 30s after the start, the state becomes `failed`, shown as "Couldn't start Cat Office" with an **Open Log** link.
  - When neither `catOffice.dir` nor a remembered folder exists, clicking the button shows "Cat Office's folder isn't known: set catOffice.dir in the config".
- **"Open Cat Office ↗"** is hidden while Cat Office is offline.

### 4. Art cache

- The app downloads only the PNGs it needs from `<url>/assets/...`; these need no token.
  - Per cat: `cats/{cat}/back-left/type.png` (working), `cats/{cat}/front-left/right-up.png` (waiting), `cats/{cat}/sleep.png` (idle).
  - Desk: `desk-sprites/s1-<style>.png`, using the first desk in `/data/desks.json`.
- The cat list and frame size (360×380, feet at 180,300) come from `/data/cats.json`.
- Images are shrunk to 2× their display size and stored in `~/Library/Caches/ClaudeBar/art/`.
- Each file is downloaded once. Clearing the cache folder makes the app download them again.
- **Picking a cat:** use `agent.cat` if it's present. Otherwise use Cat Office's fallback formula (`portraitCat`): FNV-1a 32-bit over the agent id's UTF-16 code units, then `catIds[hash % count]`.

### 5. Cat Office patch

The patch lives in this repo as `patches/cat-office.patch` and is applied by `scripts/patch-cat-office.sh <cat-office-dir>`.

1. **The browser reports its cat choices.** In `src/agents/live/useAgentCats.ts`, whenever the computed `Map<agentId, catId>` changes, the tab sends it to `POST /__agents/cats` as `{assignments: {[agentId]: catId}}`.
   - Sends are spaced at least 1s apart. The request carries the existing token header.
2. **The server remembers them.** `server/agent-bridge/index.ts` adds the `POST /__agents/cats` route, protected by the same `guard`.
   - The server keeps the map in memory and saves it to `.cat-office/cat-assignments.json`, loading it again on start.
   - The feed adds `cat?: string` to each `LiveAgent` (`types.ts`).
   - Agents whose id isn't in the map have no `cat` field.
3. **The server writes its address, token and folder to a file.** Once the dev server is listening, it writes `~/.cat-office/bridge.json` = `{url, token, dir, pid}`, readable only by the owner (mode `0600`), and deletes the file when the server closes. The file lives in the home folder, not in Cat Office's folder, so ClaudeBar finds it wherever Cat Office is moved. `CAT_OFFICE_BRIDGE_FILE` overrides the path for tests.
4. **Workers save the plan usage.** Headless workers never run a status line, so with only them running the 5h / 7d reading went stale. Each turn's stream-json `rate_limit_event` (`rate_limit_info.unifiedWindows.{five_hour,seven_day}.{utilization 0..1, resetsAt}`) is saved to `~/.cat-office/plan-usage.json` in the status line's format (`used_percentage` = utilization × 100), which Cat Office's own `PlanUsageWatch` and ClaudeBar both read.
- **Tests:** add tests for the new route (valid and invalid body, auth required) and for the `cat` field in snapshots, using Cat Office's existing test setup in `tests/`.
- **The patch script:**
  - checks that the folder looks like Cat Office
  - does a trial run with `patch --dry-run -p1`
  - backs up the files it touches to `.cat-office/patch-backup-<timestamp>/`
  - applies the patch
  - exits without changing anything if the trial run fails
  - says that Cat Office needs a restart
- **Order:** applying the patch requires restarting Cat Office's dev server, which ends any Cat Office sessions that are running. It's therefore the last step, done after ClaudeBar works on its own against an unpatched Cat Office.

### 6. ClaudeBar.app

A SwiftUI and AppKit app for macOS 14+ that runs as an agent app (`LSUIElement`, so there is no Dock icon). The menu bar item is an `NSStatusItem`, chosen over `MenuBarExtra` because the app needs separate click and hover behavior.

**Units**

| Unit | Responsibility | Depends on |
|---|---|---|
| `ConfigStore` | Load, save and watch `projects.json`; add and remove entries | FileManager |
| `SnapshotReader` | Read every snapshot file into `[Snapshot]`; delete files older than 30 days | FileManager |
| `LiveSessionReader` | Read `~/.claude/sessions/*.json` and keep entries whose `pid` is still running (`kill(pid,0)==0`), giving `[sessionId: FallbackStatus]` (`busy`→working, `idle`→idle, `waitingFor` present→waiting) | FileManager, Darwin |
| `GitBranchReader` | Run `git -C <path> --no-optional-locks rev-parse --abbrev-ref HEAD` with a 2s timeout; return the branch, `nil`, or "detached" | Process |
| `CatOfficeClient` | Find the server, follow the feed, reconnect; publish `[OfficeAgent]` + `officeState` | URLSession |
| `ArtCache` | Get, shrink and cache sprites; look up the cat for an agent | URLSession, ImageIO |
| `StatusModel` (pure) | Combine everything into `UsageSummary`, `[ProjectRow]`, `[OfficeRow]`, `attention` | none (unit-tested) |
| `AttentionTracker` (pure) | Track status changes between polls; produce the "your turn" set and the "finished" events | none (unit-tested) |
| `Notifier` | Post a macOS notification for each finished event | UserNotifications |
| `AppState` | `ObservableObject`; a 5s timer reads the files and `git` in the background, combines them with the latest Cat Office feed, runs `StatusModel` and `AttentionTracker`, and publishes the result | the units above |
| `StatusItemController` | Owns the `NSStatusItem`; click shows the dropdown panel, hover shows the peek panel | AppKit |
| Views | `MenuBarLabel`, `UsageHeader`, `ProjectRowView`, `OfficeSectionView`, `OfficePeekView`, `CatView`, `FooterBar` | AppState |

**Matching rules (`StatusModel`)**

- **Snapshot → project:** a snapshot belongs to a project if `snapshot.cwd == project.path` or `snapshot.cwd` starts with `project.path + "/"`. Paths are compared after expanding `~`, standardizing, and resolving symlinks. If pinned paths are nested, the snapshot goes to the longest matching path.
- **Session status:** the Cat Office feed's agent with the same `sessionId` if there is one; otherwise `LiveSessionReader`; otherwise the session isn't live.
- **Project row:**
  - The newest matching snapshot (by `updated_at`) supplies the model and context %.
  - The status shown is the "most urgent" live session, in the order waiting > working > idle.
  - The ×N badge appears when 2 or more matching sessions are live.
  - **Stale** (no live session) means the row is dimmed and shows the age of the newest snapshot: "now", "5m ago", "3h ago", "2d ago".
  - **No sessions yet** means only the branch is shown.
  - **Missing** means the folder doesn't exist.
- **Office rows:** feed agents with `owner == "office"` and `status != "ended"`, sorted by name.
- **Usage summary:**
  - Taken from the snapshot with the highest `updated_at` that has a non-null 5h or 7d value. "as of" is that snapshot's time.
  - `workingCount` is the number of live sessions currently working, from all sources, with duplicates removed by `sessionId`.

**Attention ("your turn") and notifications (`AttentionTracker`)**

- A session **needs attention** when:
  - its status is `waiting`, or
  - it's an office agent that went from `working` to `idle` since an earlier poll.
- Attention clears when the user opens the peek or the dropdown. A cleared session only counts again after another such change.
- A **finished** event is fired when an office agent goes from `working` to `idle` or `ended`. `Notifier` then posts "🐈 <name> finished" with the agent's `task` as the body, if `notifications` is on in the config.
- The first poll after launch only records the starting state, so the app doesn't send a burst of notifications at startup.

## UI

### Menu bar label

`◆ 42% · 18%` (5h · 7d).

- Each percentage is colored green below 60, yellow from 60 to below 85, and red at 85 or more.
- When anything needs attention, a small amber dot follows the icon: `◆• 42% · 18%`.
- With no usage data, the label reads `◆ —`.

### Click: dropdown panel

```
 Usage                                   as of 1m ago
 5h  ████░░░░░░  42%     3 working   resets in 2h 14m
 7d  ██░░░░░░░░  18%                 resets Thu 9:00
 ─────────────────────────────────────────────────
 Projects
 ● pnp-ufdms-base-admin        working          ×2
   feat/invite-expiry · Opus 5.5 · ctx ██████░░░░ 61%
 ○ dotfiles                                  3h ago
   main · Sonnet 5.5 · ctx ███░░░░░░░ 28%     (dimmed)
 ○ old-api
   develop · no sessions yet
 ─────────────────────────────────────────────────
 Office                                 Claude OK
 • office-82eb65   waiting 2m   ~ · designing spec
 • office-9fc8a4   working      turborepo-lab · main
 ─────────────────────────────────────────────────
 + Add Folder…  Edit Config  Open Cat Office ↗  Launch at Login ✓  Quit
```

- Status dots and words use Cat Office's status colors: working #45c486, waiting #f2b53a, idle #6f7a86, ended #6aa5ff (Cat Office's dark-theme values). Rows that need attention show the waiting color.
- The "resets …" text only appears when a reset time exists. It reads "resets in Xh Ym" when the reset is under 24h away, and "resets <Weekday> <h:mm>" otherwise.
- "N working" only appears when N > 0.
- Office header: "Claude OK", or "Claude hindered" in amber when the feed's `claude.hindered` flag is set. When Cat Office can't be reached, the header reads "Cat Office isn't running".
- **Row hover** shows an ✕ button that removes the folder from the config.
- **Clicking a project row** opens the folder in Finder. **Clicking an office row** opens Cat Office in the browser.
- **Add Folder…** opens an `NSOpenPanel` that only allows directories, with multiple selection.
- **Edit Config** opens `projects.json` in the default editor.
- **Launch at Login** is a toggle using `SMAppService.mainApp`.
- With an empty project list, the panel shows "No projects yet — Add Folder…".

### Hover: office peek

- **Opening and closing:** a tracking area on the status item button opens the peek after the pointer has rested there for 300ms.
  - The peek is a borderless `NSPanel` (non-activating, about 380×220pt) anchored under the icon.
  - It closes 250ms after the pointer leaves both the icon and the panel.
  - Clicking the icon closes the peek and opens the dropdown.

```
 Cat Office · 3 cats · Claude OK
 ┌──────────────────────────────────────────────┐
 │   [desk]      [desk]      [desk]  │  lounge  │
 │   cat:type   cat:right-up (!)     │ cat:sleep│
 │   ◯ green     ◯ amber             │ ◯ faded  │
 │  office-9fc8  office-82eb         │  turbo…  │
 └──────────────────────────────────────────────┘
                              Open Cat Office ↗
```

- **What appears:** all non-ended agents from the feed, including terminal sessions, because Cat Office shows them too.
  - **Working and waiting agents** sit at desks, left to right, sorted by name, with at most 6 desks; extra agents become "+N more".
  - **Idle agents** sit in the lounge area, at most 3 shown, with "+N" beyond that.
- **How each status looks:**

  | Status | Pose | Ring at feet | Motion | Extra |
  |---|---|---|---|---|
  | working | `back-left/type` behind the desk | green, pulsing | 1.5pt bob every 0.35s plus a 3s breathe | |
  | waiting | `front-left/right-up` in front of the desk | amber, dashed | | red "!" bubble |
  | idle | `sleep` in the lounge | faded | 4.8s breathing pulse | |

- **Hovering a cat** shows a card with its name, repo · branch, model, status and how long it's been in it ("waiting 2m"), the wait reason if there is one, and `task`, falling back to `lastAction`, cut to 2 lines.
- **Reduce Motion:** when it's on in macOS settings, all animation stops.
- **Cat Office offline:** one sleeping cat from the cache (or a plain icon if nothing is cached) with "Cat Office isn't running", plus the "Open Cat Office ↗" link.
- Opening the peek clears attention (see the Attention rules above).

## Project layout & build

```
~/Documents/projects/claude-bar/
  Package.swift                 # executable ClaudeBar, library ClaudeBarCore, test target
  Sources/ClaudeBarCore/        # ConfigStore, SnapshotReader, LiveSessionReader, GitBranchReader,
                                # CatOfficeClient (+ SSE parser), ArtCache, StatusModel, AttentionTracker
  Sources/ClaudeBar/            # App entry, AppState, StatusItemController, Notifier, Views
  Tests/ClaudeBarCoreTests/
  Resources/Info.plist          # LSUIElement = true, bundle id com.jbclores.claudebar
  scripts/build.sh              # swift build -c release → build/ClaudeBar.app, ad-hoc codesign
  scripts/statusline-command.sh # source of truth for the updated status line script
  scripts/install-statusline.sh # backs up ~/.claude/statusline-command.sh, then copies the new one in
  patches/cat-office.patch
  scripts/patch-cat-office.sh
```

- The app builds with the Command Line Tools only; no Xcode project is needed.
- The user copies `build/ClaudeBar.app` to `/Applications`. Launch at Login (`SMAppService`) and notification permission need an app bundle in a stable location.
- If notifications don't work with ad-hoc signing, see Risks for the fallback.

## Build phases

1. **Core:** snapshot writer, config, readers, `StatusModel`, menu bar label, dropdown (usage + projects), Launch at Login.
2. **Cat Office feed:** `CatOfficeClient` (pulling the token from the page for now), the Office section, status on project rows, the working count, attention, notifications.
3. **Peek:** `ArtCache`, `StatusItemController` hover, `OfficePeekView`, cat hover cards. Cats use the fallback formula for now.
4. **Cat Office patch:** `/__agents/cats`, the `cat` field, `bridge.json`, the patch script, and tests. ClaudeBar then prefers `bridge.json` and `agent.cat`. This phase is applied last, with a planned Cat Office restart.

## Error handling summary

| Condition | Behavior |
|---|---|
| Snapshot or session file unreadable or invalid | Skipped silently |
| `git` fails or takes over 2s | Branch omitted for that poll |
| Config invalid | Keep the last good config and show a warning row |
| Status line write fails | Ignored; terminal output unchanged |
| Cat Office unreachable | Office shown as offline; status falls back to session files; reconnect with backoff |
| Feed returns 401/403 | Get the token again (from `bridge.json`, then the page) and reconnect |
| Sprite download fails | Draw a plain colored circle for that cat; retry on the next peek open |
| Agent has no `cat` | Use the fallback formula |

## Testing

- **Unit (`swift test`):**
  - `StatusModel`: matching rules, nested folders, newest snapshot, combining the three sources with duplicates removed, choosing which status to show, the ×N count, stale/missing/no-sessions states, the usage summary, working count, age and reset-time formatting.
  - `AttentionTracker`: the waiting and working→idle rules, acknowledging, the first poll staying quiet, finished events.
  - `ConfigStore`: `~` expansion, default names, unknown keys kept, an invalid file keeping the last good config, add/remove/dedupe.
  - Readers: null fields, invalid files, dead process ids.
  - `CatOfficeClient`: the event-stream parser (several lines per event, pings, partial chunks), pulling the token out of the page, choosing the server from `bridge.json` vs the URL, decoding `LiveAgent` with and without `cat`.
  - `ArtCache`: the fallback formula, checked against values computed with Cat Office's JS implementation.
- **Status line script:** pipe sample JSON in and check that the terminal output matches the current script byte for byte and that the snapshot file is written. Input with no `session_id` writes nothing.
- **Cat Office patch:** new tests in Cat Office's `tests/` for the route and the `cat` field, plus a trial run of the patch script against a fresh copy of the Cat Office folder.
- **End to end:** run the built app against the real `~/.claude` data and the running Cat Office, and check:
  - Project rows match the open sessions' status lines.
  - The office peek shows the same agents and statuses as the browser, and after phase 4 the same cats.
  - Stopping Cat Office switches the app to offline mode, and restarting it brings the app back.

## Risks

- **Cat Office's internal API can change.** The feed, routes and asset paths aren't a public interface. The parts that depend on them are kept in `CatOfficeClient` and `ArtCache`, and every failure falls back to offline mode.
- **Notifications with an ad-hoc-signed app.** `UNUserNotificationCenter` may refuse to work without proper signing. If it does, the app falls back to `osascript -e 'display notification …'`.
- **Headless sessions have no snapshots**, so their context % is unknown ("—").

## Out of scope

- Controlling Claude Code or Cat Office agents (replying, answering, stopping or launching agents), and stopping or restarting Cat Office itself
- Opening a specific agent in Cat Office (Cat Office has no deep links)
- Rendering the full isometric office, floors, or walking animation
- Fetching usage directly from Anthropic's servers
- Support for other machines or users

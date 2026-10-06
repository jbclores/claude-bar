# ClaudeBar — Design

**Date:** 2026-10-06
**Status:** Draft, awaiting review

## Goal

A macOS menu bar app that works like the Claude Code status line, but for several projects at once. For a fixed list of project folders it shows the git branch, the Claude model, and context-window usage, plus the account-wide 5-hour and 7-day usage limits.

**Audience:** one user, on this Mac. The app only reads data and never controls Claude Code.

**Success criteria**

- The menu bar always shows the latest known 5h and 7d percentages.
- Opening the dropdown lists every pinned folder with its current branch.
- Each folder shows the model and context % of its newest session. A live session is marked live. Otherwise the last values appear dimmed, with how long ago they were seen.
- Folders can be added from the app or by editing a config file, and both stay in sync.
- The terminal status line looks and behaves exactly as it does today.

## Architecture

```
Claude Code ──stdin JSON──▶ statusline-command.sh ──▶ terminal status line (unchanged)
                                   │
                                   └─ writes ─▶ ~/.claude/claude-bar/sessions/<session_id>.json
                                                              │
~/.config/claude-bar/projects.json ◀─ reads/writes ─┐         │ reads
~/.claude/sessions/<pid>.json ─────── reads ───────▶ ClaudeBar.app (polls every 5s)
<project>/.git ─────── `git rev-parse` ────────────▶
```

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

- The values come from the status line input fields the script already reads: `session_id`, `workspace.current_dir`/`cwd`, `model.display_name`, `context_window.used_percentage`, and `rate_limits.{five_hour,seven_day}.used_percentage`. The reset times are read from `rate_limits.*.resets_at` if Claude Code provides them; otherwise the value is `null`.
- `updated_at` is Unix seconds at the moment of writing.
- The file is written to a temp file in the same directory and then renamed over the target, so the app never reads a half-written file.
- Missing fields are written as `null`. If `session_id` is missing, nothing is written.
- Any failure to write is ignored, so the status line output is never affected.
- The JSON parsing that already exists in the script (inline `python3`) is extended to produce this file. No new dependencies are added.

### 2. Config file

`~/.config/claude-bar/projects.json`

```json
{
  "projects": [
    { "path": "~/Documents/projects/pnp-ufdms-base-admin" },
    { "path": "~/dotfiles", "name": "dotfiles" }
  ]
}
```

- `path` is required, and `~` is expanded. `name` is optional and defaults to the folder's base name.
- The app creates the file with an empty list if it doesn't exist.
- The app re-reads the file when its modification time changes, checked on each 5-second poll.
- If the file can't be parsed, the app keeps the last good list and shows a warning row: "Config error — using last good list".
- "Add Folder…" and the remove button rewrite the file atomically, keeping the order. Adding a path that's already in the list does nothing.

### 3. ClaudeBar.app

A SwiftUI app built with `MenuBarExtra` using the `.window` style. It targets macOS 14+ and runs as an agent app (`LSUIElement`, so there is no Dock icon).

**Units**

| Unit | Responsibility | Depends on |
|---|---|---|
| `ConfigStore` | Load, save and watch `projects.json`; add and remove entries | FileManager |
| `SnapshotReader` | Read every snapshot file into `[Snapshot]` | FileManager, JSONDecoder |
| `LiveSessionReader` | Read `~/.claude/sessions/*.json`, keep the entries whose `pid` is still running (`kill(pid, 0) == 0`), and return the set of their `sessionId`s | FileManager, Darwin |
| `GitBranchReader` | Run `git -C <path> --no-optional-locks rev-parse --abbrev-ref HEAD` with a 2s timeout; return the branch, `nil` (not a repo), or `HEAD` → shown as "detached" | Process |
| `StatusModel` (pure) | Combine config, snapshots, live set and branches into `[ProjectRow]` and `UsageSummary` | none (unit-tested) |
| `AppState` | `ObservableObject`; a 5s timer runs the readers (off the main thread) and then `StatusModel`, and publishes the result | the units above |
| Views | `MenuBarLabel`, `UsageHeader`, `ProjectRowView`, `FooterBar` | AppState |

**Matching rules (`StatusModel`)**

- A snapshot belongs to a project if `snapshot.cwd == project.path` or `snapshot.cwd` starts with `project.path + "/"`. Paths are compared after expanding `~`, standardizing, and resolving symlinks.
- If two pinned paths are nested, a snapshot goes to the **longest** matching path.
- A project's displayed snapshot is its matching snapshot with the highest `updated_at`.
- **Live** means at least one of the project's matching snapshots has a `session_id` in the live set. The `×N` badge shows N = the number of live matching sessions, and only when N ≥ 2.
- **Stale** means the project has matching snapshots but none of them is live. The row is dimmed and shows the age of the newest one ("now", "5m ago", "3h ago", "2d ago").
- **No sessions** means no snapshot matches. The row shows the branch only, with "no sessions yet".
- **Missing** means the folder doesn't exist. The row shows "missing" and nothing else.
- **Usage summary:** taken from the snapshot with the highest `updated_at` that has a non-null `five_hour_pct` or `seven_day_pct`, across all snapshots including those not matching any project. "as of" is that snapshot's `updated_at`.

**Housekeeping:** on each poll, snapshot files older than 30 days are deleted.

## UI

**Menu bar label:** `◆ 42% · 18%` (5h · 7d).

- Each percentage is colored by the same thresholds as the status line: green below 60, yellow from 60 to below 85, red at 85 or more.
- With no data, the label reads `◆ —`.

**Dropdown panel**

```
 Usage                                   as of 1m ago
 5h  ████░░░░░░  42%            resets in 2h 14m
 7d  ██░░░░░░░░  18%            resets Thu 9:00
 ─────────────────────────────────────────────────
 ● pnp-ufdms-base-admin                         ×2
   feat/invite-expiry · Opus 5.5 · ctx ██████░░░░ 61%
 ○ dotfiles                                  3h ago
   main · Sonnet 5.5 · ctx ███░░░░░░░ 28%     (dimmed)
 ○ old-api
   develop · no sessions yet
 ─────────────────────────────────────────────────
 + Add Folder…     Edit Config     Launch at Login ✓     Quit
```

- The "resets …" text only appears when a reset time exists. It reads "resets in Xh Ym" when the reset is under 24h away, and "resets <Weekday> <h:mm>" otherwise.
- Usage bars use the same color thresholds as the menu bar label.
- **Row hover** shows an ✕ button that removes the folder from the config.
- **Row click** opens the folder in Finder (`NSWorkspace.open`).
- **Add Folder…** opens an `NSOpenPanel` that only allows choosing a directory, with multiple selection.
- **Edit Config** opens `projects.json` in the default editor.
- **Launch at Login** is a toggle using `SMAppService.mainApp`.
- **Quit** exits the app.
- With an empty project list, the panel shows "No projects yet — Add Folder…".

## Project layout & build

```
~/Documents/projects/claude-bar/
  Package.swift            # executable target ClaudeBar + library ClaudeBarCore + test target
  Sources/ClaudeBarCore/   # ConfigStore, SnapshotReader, LiveSessionReader, GitBranchReader, StatusModel
  Sources/ClaudeBar/       # App entry, AppState, Views
  Tests/ClaudeBarCoreTests/
  Resources/Info.plist     # LSUIElement = true, bundle id com.jbclores.claudebar
  scripts/build.sh         # swift build -c release → assembles ClaudeBar.app, ad-hoc codesign
  scripts/statusline-command.sh       # source of truth for the updated status line script
  scripts/install-statusline.sh       # backs up ~/.claude/statusline-command.sh, then copies the new one in
```

- The app builds with the Command Line Tools only; no Xcode project is needed.
- `build.sh` creates `build/ClaudeBar.app`. The user copies it to `/Applications`, which `SMAppService` needs for Launch at Login to work reliably.

## Error handling summary

| Condition | Behavior |
|---|---|
| Snapshot file unreadable or invalid | Skipped silently |
| `~/.claude/sessions` missing | Live set is empty, so every project with snapshots shows as stale |
| `git` fails or takes over 2s | Branch omitted for that poll |
| Config invalid | Keep the last good list and show a warning row |
| Status line write fails | Ignored; terminal output unchanged |

## Testing

- **Unit (`swift test`), `StatusModel`:**
  - Exact and subfolder matching, and the nested-path tie-break
  - Picking the newest snapshot
  - Live, stale, no-sessions and missing states
  - The ×N count
  - Choosing the usage summary, including the case of no data
  - Age formatting and reset-time formatting
- **Unit, `ConfigStore`:** `~` expansion, default names, an invalid file keeping the last good list, add/remove/dedupe, and atomic save.
- **Unit, `SnapshotReader`:** null fields and invalid files.
- **Status line script:** pipe sample JSON in; check that the terminal output matches the current script exactly and that the snapshot file is written. Pipe input with no `session_id` and check that nothing is written.
- **End to end:** build the app and run it against the real `~/.claude` data. Check that the live/stale state, branch, model and percentages match the status lines of open sessions.

## Out of scope

- Controlling or starting Claude Code sessions
- Notifications or alerts at thresholds
- Fetching usage directly from Anthropic's servers
- Support for other machines or users

# ClaudeBar Undo and "What ClaudeBar changes" — Design

**Date:** 2026-10-07
**Status:** Draft, awaiting review
**Builds on:** `2026-10-07-claudebar-onboarding-design.md` (setup, the patch, the status line, setup state)

## Goal

Teammates can trust ClaudeBar on their own Mac: they can read exactly what it changes before they set it up, and
one action puts their Mac back the way it was.

**Success criteria**

- Before clicking Continue in setup, a teammate can read every place ClaudeBar changes, where each backup goes, and
  how to undo it.
- One window (or one Terminal command) undoes ClaudeBar's changes; the teammate picks which.
- Undo follows setup's safety rules: nothing changes before confirming, every change is backed up first, and nothing
  of the user's is deleted. "Remove" always means the Trash.
- Each change can also be undone by hand, from the page, when ClaudeBar won't run at all.

## 1. The undo window

**Where:** Settings, under the Setup row: **Undo ClaudeBar's changes…**. It opens a small window like the setup
window. It's always there, since "Also remove ClaudeBar" always applies.

**Rows.** Only changes that are in place now are listed:

| Row | Shows when | Starts | What it does |
|---|---|---|---|
| **Unpatch Cat Office** | the remembered Cat Office folder is patched (current or an older version of the patch) | ticked | Trial run first; backs up the touched files to `<cat-office>/.cat-office/patch-backup-<time>/`; then takes the patch out, keeping edits made since in other places. If it doesn't come out cleanly: nothing changes, and the row says so and names the backup folders. |
| **Restore your old status line** | setup changed the status line and its record is live (`StatusLineSetup.restore()` can run) | ticked | The existing restore: their own status line back, or no `statusLine` setting if they had none. |
| (same row, greyed out) | ClaudeBar's status line is in place with no record (set up by `scripts/install-statusline.sh` before setup existed) | — | "ClaudeBar has no record of your earlier status line", with a link to the manual steps. |
| **Also remove ClaudeBar** | always | unticked | Turns Launch at Login off; moves ClaudeBar's settings, usage files, art cache and log to the Trash (section 3); then ClaudeBar quits. The user drags the app to the Trash. |

- **Warning before Undo selected:** with Unpatch ticked and Cat Office running from that folder, the same amber
  warning as setup: unpatching restarts Cat Office, which ends any Claude sessions running inside Cat Office.
- **Order:** unpatch, then the status line, then remove.
- **After:** ✓ or ✗ beside each row with one line on what happened. If Cat Office is running and was unpatched:
  **Restart Cat Office** (setup's restart: stops only Cat Office's dev server). Then **Done**, or **Quit ClaudeBar**
  when "Also remove" ran.
- **Setup state after undo:** unpatched → `reduced`; status line restored → usage off, so `full` becomes
  `reduced`. `seen` stays true: the setup window doesn't open by itself, and the Office tab card ("Some extras are
  off · Fix…") and Settings → Set up ClaudeBar… can redo everything.
- **The window can't close while it's working** (as the setup window).
- **Nothing to undo** (no patch, no status line change): the window shows only "Also remove ClaudeBar".

## 2. The Terminal command

`ClaudeBar --undo` (the binary inside the app: `~/Applications/ClaudeBar.app/Contents/MacOS/ClaudeBar --undo`, or
`build/ClaudeBar.app/…`):

- Lists the same rows with the same defaults, greyed rows as notes, and the same Cat Office warning.
- Asks `Undo these? [y/N]`; anything but `y` changes nothing.
- `--undo --remove` also runs "Also remove ClaudeBar".
- Prints ✓ / ✗ per row; exits 0 when every chosen row worked, 1 otherwise.
- It runs the same code as the window. It doesn't need the menu bar app running; if ClaudeBar is running, it prints
  "Quit ClaudeBar first" for `--remove` and stops.

## 3. What "Also remove ClaudeBar" removes

Moved to the Trash (only if they exist):

- `~/.config/claude-bar/` — settings
- `~/.claude/claude-bar/` — usage files from the status line
- `~/Library/Caches/ClaudeBar/` — the art cache
- `~/Library/Logs/ClaudeBar/` — the log

Plus: Launch at Login turned off.

**Left alone:** the app itself (the user drags it to the Trash), every backup (Cat Office's patch backups, the
`settings.json` and status line backups), and ClaudeBar's scripts in `~/.claude/` when `settings.json` still names
them (so Claude Code's status line keeps working if the status line wasn't undone).

## 4. Unpatching Cat Office

`scripts/patch-cat-office.sh --undo <dir>` (bundled in the app's `Setup/` folder like the patch script):

- Not Cat Office → exit 2.
- The current patch reverses cleanly (trial run) → back up the touched files, reverse it, exit 0.
- Else an older version from the patch history reverses cleanly → same, with that version.
- Not patched (the patch applies cleanly forward) → "Not patched", exit 0, nothing changed.
- Neither → exit 3, nothing changed (e.g. a patched file was edited since).

## 5. The "What ClaudeBar changes" page

In the guide (`Resources/Help/guide.html`, a new section and nav link) and the README. Setup's Welcome step links to
it: **What will ClaudeBar change?** opens the guide at that section.

- **What it changes:** a table of the five places (`~/.config/claude-bar/`, `~/.claude/claude-bar/`,
  `~/.claude/settings.json` (the `statusLine` entry only), `~/.claude/statusline-command.sh`, the Cat Office folder
  (the patch)), with what changes and where each backup goes.
- **What it never does:** it talks only to the Cat Office on this Mac (`localhost`), never the internet; it never
  starts, stops or controls Claude agents, and never touches projects or git; nothing changes before Continue; it
  never deletes the user's files.
- **What can interrupt work:** patching or unpatching restarts Cat Office, which ends the Claude sessions running
  inside Cat Office.
- **How to undo:** the window, the `--undo` command, and by hand for each change: Cat Office (copy the files back from
  the newest `.cat-office/patch-backup-*` folder), the status line (copy back the newest
  `settings.json.claude-bar-backup-*` and, if there is one, `statusline-command.sh.claude-bar-backup-*`), ClaudeBar's
  own files (the four folders in section 3), and Launch at Login (System Settings → General → Login Items).

## 6. Units

| Unit | Role |
|---|---|
| `UndoPlan` (Core) | From the current state (Cat Office folder and its patch check, status line state and record), the rows, whether each shows, is greyed, and starts ticked; the setup state after undo |
| `ClaudeBarRemoval` (Core) | Moves ClaudeBar's own folders to the Trash; injectable home and trash for tests |
| `patch-cat-office.sh --undo` (script) | Section 4 |
| `UndoActions` (app) | Runs the ticked rows in order: the unpatch script, `StatusLineSetup.restore()`, Launch at Login off and `ClaudeBarRemoval` |
| `UndoWindow` / `UndoView` (view) | Section 1 |
| `--undo` (app, `ClaudeBarMain`) | Section 2 |
| Guide section, README section, Welcome link | Section 5 |

## 7. Testing

All against temporary folders and an injected home; never the real `~/.claude`, Cat Office or ClaudeBar config.

- **Unpatch script tests** (in `scripts/test-setup-scripts.sh`): patched → unpatched with a backup; an older version
  → unpatched; not patched → nothing to do; a patched file edited since → exit 3 and nothing changed; patch then
  unpatch → the folder matches the original.
- **Unit tests:** which rows show, greyed and ticked for each state (including the no-record status line); the setup
  state after each combination; removal moves exactly the four folders and nothing else, and skips missing ones;
  `--undo` output, the y/N answer, and the exit code.
- **Renders** of the window (choose, working, done with a ✗, nothing to undo) and a **click test** that clicks only
  the window's own buttons.

## Out of scope

- Removing the app itself (the user drags it to the Trash).
- Deleting backups.
- Undoing changes made by hand outside setup, other than noting them (the greyed row).

# ClaudeBar Onboarding — Design

**Date:** 2026-10-07
**Status:** Draft, awaiting review
**Part of:** sharing ClaudeBar with the team (`2026-10-07-claudebar-sharing-draft.md`). This spec is the onboarding; the
install zip and the unsigned-app warning come later, in their own spec.

## Goal

A teammate who opens ClaudeBar for the first time gets set up in about a minute, without editing files: ClaudeBar finds
their Cat Office, connects it, and turns on usage — asking only what it can't decide itself.

**Success criteria**

- A teammate with Cat Office running, or unzipped in a usual place, finishes setup without typing a path.
- Nothing on their Mac changes until they click Continue; every change is backed up first; nothing is ever deleted.
- Skipping is always possible and never nags: the window doesn't reopen by itself, but setup is one click away.
- Teammates without Cat Office still get usage and Projects.
- Mac only.

## 1. Where it appears

- **The setup window** does the setup. It opens by itself on ClaudeBar's first launch, and stays open while the user
  switches apps.
- **Skipping:** "Skip for now" on any step closes the window. It never opens by itself again.
- **The Office tab card:** while Cat Office isn't set up, the Office tab shows "Cat Office isn't set up yet · Set up…";
  in the reduced state, a smaller "Some extras are off · Fix…". Both open the setup window.
- **Settings:** a Setup row with the state, the Cat Office folder, patched or not, and how the status line is set up, and
  **Set up ClaudeBar…** to reopen the window. With ClaudeBar's status line in place of theirs: **Restore my old status
  line**.

## 2. The steps

1. **Welcome.** "ClaudeBar shows your Claude usage, your projects and your Cat Office in the menu bar." **Set up** /
   **Skip for now**.
2. **Find Cat Office** (automatic):
   - In order: a running Cat Office (its address and `~/.cat-office/bridge.json`), the saved folder, then the usual
     places — `~/Documents`, `~/Documents/projects`, `~/Downloads`, `~/Desktop`, `~/Developer`, `~/Projects`, two levels
     deep.
   - A folder counts only if it is Cat Office: a `package.json` and `server/agent-bridge/`.
   - One found: "✓ Found your Cat Office" with its folder and **Not this one? Choose folder…**. Several: a list, newest
     first. None: **Choose folder…** / **I don't use Cat Office** (skips to step 4).
   - A chosen folder that isn't Cat Office: "That folder isn't Cat Office" — choose again.
3. **Connect.** Three ticked choices, each with one line on what it does; **Continue** runs the ticked ones and shows ✓
   or ✗ beside each:
   - **Patch Cat Office** — "Matching cats, helpers, and usage without a terminal." Trial run first, backup of the
     touched files, nothing changed if it doesn't fit (then: "Your Cat Office version isn't supported for the extras",
     and setup continues in the reduced state). An already patched copy is recognised and not patched twice; an older
     version of the patch is upgraded. If Cat Office is running: "Restart Cat Office to finish" with **Restart**, which
     stops only Cat Office's own dev server.
   - **Usage in the menu bar** — the status line (section 3).
   - **Start Cat Office now** — only if it isn't running. Checks Node first; missing: "Cat Office needs Node.js" with a
     link to nodejs.org (setup still finishes).
4. **Done.** A checklist of what's on (✓ Cat Office, ✓ patched, ✓ usage) and, for anything that failed or was skipped,
   one line on what's missing and how to fix it. "Usage appears after your next message in Claude Code." **Open the
   office**, and a link to the guide.

Reopening setup shows what's already done and lets the user change it (e.g. a new Cat Office folder after a new zip).

## 3. The status line

ClaudeBar's usage and Projects data come from Claude Code's status line. Claude Code runs the command named in
`~/.claude/settings.json` (`"statusLine": {"type": "command", "command": …}`).

| Their Mac | What setup does |
|---|---|
| No status line | Installs ClaudeBar's default status line (`scripts/statusline-command.sh`, the one in use today: model, folder and branch, context bar, 5h/7d usage) and adds the `statusLine` setting, keeping every other setting; `settings.json` backed up first. |
| Their own status line | Asks: **Keep your status line** (default) — ClaudeBar wraps it: its hook saves its data, then runs theirs and passes its output through unchanged — or **Use ClaudeBar's status line** — theirs is backed up and can be restored from Settings. |
| ClaudeBar's already | Nothing to do. |

- A `settings.json` that doesn't parse is left alone; setup explains how to add the line by hand.
- The status line script ships inside the app.

## 4. Setup state

ClaudeBar remembers one of three states (in its config file):

- **Full** — Cat Office found and patched, usage on.
- **Reduced** — Cat Office found, patch skipped or didn't fit. Floors and cats show; cats may not match the browser,
  helpers don't show, usage without a terminal is off.
- **No Cat Office** — skipped, or not used. Usage and Projects work if the status line is set up.

## 5. Safety

- Nothing changes before Continue. Every change is backed up first (patched files, `settings.json`, the old status line).
  Setup never deletes anything.
- The patch (`patches/cat-office.patch`) and the status line script ship inside the app, so an install from a zip needs
  nothing else.
- Setup touches only the Cat Office folder the user confirmed, `~/.claude/settings.json`, `~/.claude/statusline-command.sh`
  and ClaudeBar's own config.

## 6. Units

| Unit | Role |
|---|---|
| `CatOfficeFinder` (Core) | Recognise a Cat Office folder; search the usual places; order several copies |
| `StatusLineSetup` (Core) | Read the `statusLine` setting; plan and apply the three cases; wrap, replace, restore; keep every other key |
| `SetupState` (Core) | The three states, saved in the config |
| `PatchRunner` (app) | Runs the bundled patch with the existing trial-run, backup and upgrade logic |
| `SetupWindow` (view) | The four steps |
| Office card, Settings row (views) | Entry points |

## 7. Testing

- **Unit tests (Core, written first):** recognising a Cat Office folder; the search over made-up folder trees;
  choosing among several copies; the three status line cases, wrapping someone else's line and restoring it; a
  `settings.json` edit that keeps every other key; the setup state; re-running setup on an already patched copy.
- **The patch and status line steps** run against copies in a temporary folder, never the real Cat Office or `~/.claude`.
- **Renders** of each setup screen and of the Office card.
- **Click test:** clicks only the setup window's own buttons.

## Out of scope

- The install zip, the unsigned-app ("unidentified developer") warning, updates (the next spec).
- Windows and Linux.
- Patching a Cat Office version the patch doesn't fit (reduced state instead).

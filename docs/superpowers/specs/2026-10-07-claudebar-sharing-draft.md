# ClaudeBar for the team (setup, no-Cat-Office mode, install or run) — Draft notes

**Date:** 2026-10-07
**Status:** Onboarding (Sections 1–2) now specified in `2026-10-07-claudebar-onboarding-design.md`; install / zip still to design.

## Decisions so far

- Mac only for now; Windows/Linux out of scope (a separate tray app or a page in Cat Office, later).
- Cat Office is shared as a zip, no repo: the patch can't go upstream, so ClaudeBar patches each teammate's copy
  during setup (with permission). Hand the patch to the senior too, for future zips.
- Versions: no per-version patches. The trial run decides; when it doesn't fit, nothing changes and ClaudeBar runs
  in a reduced mode. ClaudeBar records which Cat Office version it patched.
- Distribution: both a git repo (build it yourself) and a release zip with the ready app; one script for both.
- Order: this project is paused; Project 2 (exact floors) first.

## Section 1 — First-run setup inside the app (approved)

1. Find Cat Office: a running one (address + ~/.cat-office/bridge.json), the saved folder, then the usual places
   (~/Documents/projects, ~/Documents, ~/Downloads, ~/Desktop, ~/Developer, ~/Projects; 2 levels; package.json +
   server/agent-bridge). Several found → list them. None → "Choose folder…" / "I don't use Cat Office".
2. Patch, with permission (11 files, backup, nothing changes if it doesn't fit). The patch ships inside the app.
3. Start it if not running (npm run dev); check Node, else point to nodejs.org.
4. Result remembered and shown in Settings: Full / Reduced (lists what's missing) / No Cat Office.
   Handles spaces in paths, already patched, older patch (upgrade), Cat Office running while patching (offer restart).

## Section 2 — What works in each mode (presented, not yet reviewed)

- The status line hook carries most of the value (usage, Projects tab) for everyone, even without Cat Office.
- Setup step 4: install the hook with permission; if a status line already exists, wrap it (save snapshot, then run
  theirs and pass its output through); backup + "Remove status line hook" in Settings.
- No Cat Office: the Office tab shows a calm "Cat Office isn't set up" card with "Set up…" / "Hide Office tab";
  hidden → Projects and Settings only, no peek.
- Reduced mode: Settings lists each missing feature and why (cats match the browser, sub-agents, usage without a
  terminal need the patch).

## Not yet discussed

- Install / run-locally script details, unsigned-app Gatekeeper handling, updates, launch at login.

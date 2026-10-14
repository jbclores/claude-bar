# ClaudeBar Sessions: Jump, Answer, Today's Recap — Design

**Date:** 2026-10-14
**Status:** Approved in chat, awaiting spec review
**Part 3 of 3** of the new features (after Usage and Comfort).

## Goal

From ClaudeBar you can get to any session, answer a waiting one without switching windows (where Cat Office can type
the answer), and see what today added up to.

**Success criteria**

- Hovering a cat shows "Open in Cat Office" (that cat's panel) and, when ClaudeBar can find it, "Show terminal".
- A waiting cat's permission, single question or plan shows in its hover card and in its row, with answer buttons when
  Cat Office can answer it; "Sent" after a click, or the reason in plain words when it can't.
- The top of Projects says what today added up to: "4 sessions finished · 2h 10m working · busiest: claude-bar".
- Nothing changes for sessions ClaudeBar can't answer: the question and the jump links show instead.

## 1. Jump to a session

- **Hover card:** two links at the bottom: **Open in Cat Office** and **Show terminal** (only when found). The card
  stays open while the pointer moves from the cat onto it, and closes when it leaves both.
- **Open in Cat Office:** opens `<cat office>/?agent=<id>`; Cat Office (patch) opens that agent's drawer on load, and
  on the agent's floor. An unknown id opens the office as today.
- **Show terminal:** the session's process (`pid` from the snapshot) → its tty (`ps -o tty=`) → the Terminal or iTerm
  window/tab with that tty, brought forward through AppleScript (`tty of tab` / `tty of session`). Shown only when the
  pid has a tty and Terminal or iTerm is running; Orca, VS Code and others get only "Open in Cat Office". macOS asks
  once to let ClaudeBar control Terminal/iTerm (Automation); declining leaves the link doing nothing but a note.
- **Office list row click:** opens in Cat Office on that agent (`?agent=<id>`), as today but on its panel.

## 2. Answer a waiting cat

- **Source:** the snapshot's `pendingPrompt` (Cat Office: `question` with questions and options, `permission` with tool
  and input summary, `plan` with markdown) and `status == waiting`.
- **Shown** in the hover card and as an unfolded part of the waiting row in the list under the office:
  - permission: "Allow this command?" (or "Allow this edit?" for Edit/Write, "Allow <tool>?" otherwise) and the input
    summary on one line; buttons **Allow**, **Always allow**, **Deny**.
  - question: one single-pick question → its text and one button per option (label; description on hover). Several
    questions or a multi-pick one → the first question's text and "Answer in Cat Office".
  - plan: "Claude proposes a plan" and its first line; **Approve**, **Reject**, and "Open in Cat Office" to read it.
- **Answerable** when the session runs in an Orca terminal (Cat Office answers 409 otherwise). ClaudeBar can't know
  that ahead, so: buttons show for external sessions with a `pendingPrompt`; on a 409 the row says "Cat Office can't
  answer this session: answer it in its terminal" and offers the jump links. Office workers have no dialogs.
- **Sending:** `POST /__agents/<id>/answer` with Cat Office's `AnswerRequest` (`permission` choice `yes` /
  `yes-always` / `no`; `question` `{ optionIndexes: [i] }`; `plan` `approve` / `reject`), with the bridge token.
- **After a click:** the buttons are replaced by "Sent"; the next snapshot shows the cat working (or the next
  question). An error shows its reason in plain words (no terminal, dialog closed, Cat Office not reachable).

## 3. Today's recap

- **Log:** `~/.claude/claude-bar/sessions-today.jsonl` — one line per event: a session started working, stopped
  working (idle, waiting or ended), with time, session key and project name. Kept 2 days. In ClaudeBar's own folder
  (already listed on the changes page and removed by "Also remove ClaudeBar").
- **Recap** (since local midnight): sessions that finished (working → idle or ended), total working time (summed
  working spans, a span still open counts to now, spans across midnight count from midnight), and the busiest
  project (most working time). Office cats and terminal sessions alike; helpers count in their parent's project.
- **Shown** at the top of Projects: "4 sessions finished · 2h 10m working · busiest: claude-bar" ("1 session
  finished", no "busiest" with one project). Hidden when nothing happened today.

## 4. Cat Office patch

- `?agent=<id>` on page load: once agents are loaded, select that agent (open its drawer) and show its floor; then
  remove the parameter from the address (so a reload doesn't reopen it).
- The patch version bumps; setup's upgrade path swaps it in (one restart, ending Claude sessions inside Cat Office).

## Units

| Unit | Role |
|---|---|
| `PendingPrompt` decoding (Core, `OfficeAgent.pendingPrompt`) | The snapshot's pendingPrompt |
| `AnswerChoices` (Core) | Prompt → what to show and the buttons; button → the AnswerRequest JSON |
| `CatOfficeActions` (Core) | POST /answer with the token; error → plain words |
| `TerminalFinder` (app) | pid → tty → Terminal / iTerm window, bring it forward |
| `SessionLog` + `TodayRecap` (Core) | Log working spans and finishes; today's numbers |
| Hover card, office list row, Projects header | The UI |
| Patch: `?agent=` | Open on an agent |

## Testing

- **Core:** pendingPrompt decoding (each kind, missing, unknown); prompt → buttons (permission wording by tool,
  single vs several questions, plan); button → AnswerRequest JSON; error messages; the session log (spans, finishes,
  midnight, open spans, 2-day trim); the recap line.
- **Cat Office:** the `?agent=` behaviour in its own tests on a temp copy; the patch applies, upgrades and undoes
  (scripts/test-setup-scripts.sh).
- **Click test:** a fake Cat Office (a local HTTP server in the test, never the real one) with a waiting session; click
  **Allow** in the list; the fake receives `{ kind: "permission", choice: "yes" }` with the token.
- **Renders:** each waiting kind in the card and the row, "Sent", an error, the recap line.

## Out of scope

- Answering sessions outside Orca (no way to type into Terminal/iTerm/VS Code safely from outside).
- Notification action buttons (maybe later).
- Recaps for days before this ships, or a history of recaps.

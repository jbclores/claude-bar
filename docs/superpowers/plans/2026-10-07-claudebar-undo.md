# ClaudeBar Undo and "What ClaudeBar changes" Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Teammates can read exactly what ClaudeBar changes, and undo any of it from one window (or `ClaudeBar --undo`), safely.

**Architecture:** The patch script gains `--undo [--dry-run]`. Core gains `UndoPlan` (which rows show, greyed or ticked;
the setup state afterwards; the warning), `UndoText` (all wording, shared by the window and Terminal) and
`ClaudeBarRemoval` (moves ClaudeBar's own folders to the Trash). The app gains `UndoActions` (runs ticked rows in
order; used by both the window and the command), `UndoModel`/`UndoView`/`UndoWindow`, a Settings entry, the
`--undo` command, renders and a click test. A bundled `changes.html` page explains every change.

**Tech Stack:** Swift 6 toolchain (language mode 5), SwiftPM targets ClaudeBarCore / ClaudeBar / ClaudeBarCoreTests,
Swift Testing, SwiftUI + AppKit, macOS 14+, bash.

**Spec:** `docs/superpowers/specs/2026-10-07-claudebar-undo-design.md`

## Global Constraints

- Never touch the real `~/.claude`, the real Cat Office folder, or the real `~/.config/claude-bar` in tests, renders or
  click tests: temp folders and injected environments only. `scripts/test-setup-scripts.sh` takes the Cat Office
  folder read-only (it copies files out).
- Nothing changes before the user confirms (Undo selected / `y`). Every change is backed up first. Nothing of the
  user's is deleted. "Remove" always means the Trash (`FileManager.trashItem`), never `removeItem`.
- Order when undoing: unpatch, then the status line, then remove.
- Wording is verbatim from spec section 6 (it lives in `UndoText`, Task 2).
- Swift tools 6.0, language mode 5; macOS 14+. Match surrounding style: short doc comments, no new dependencies.
- Test commands: `swift test` (all Swift tests), `bash scripts/test-setup-scripts.sh ~/Documents/projects/cat-ai-office-with-art-20261006-1038`
  (script tests; read-only use of that folder), `bash scripts/build.sh` (app bundle).
- **Ruling (plan):** the "What ClaudeBar changes" page is its own bundled file, `Resources/Help/changes.html`, linked
  from the guide's nav and a short guide section, instead of an anchor inside `guide.html`: macOS drops `#fragment`
  when opening a local file URL, so a link from the app couldn't land on a section. Cost if wrong: one extra HTML file.

## Review Focus

1. Patch then undo within the same second: the undo's backup must not overwrite the patch's backup (same folder name)
   — Task 1 pins it.
2. A patched file edited since patching: undo must change nothing (exit 3), and the window must show the row greyed
   before anyone clicks — Tasks 1 and 2 pin it.
3. "Also remove ClaudeBar" without undoing the status line: Claude Code's status line must keep working, so removal
   never touches `~/.claude` except `~/.claude/claude-bar` — Task 3 pins it.
4. One folder can't go to the Trash: the others still go, and the failure is reported, not swallowed — Task 3 pins it.
5. Terminal answer other than `y` (including empty input / EOF): nothing changes — Task 5 pins it.
6. A render or click test finding the real Cat Office through the remembered folder (UserDefaults) and unpatching it:
   every test environment injects `rememberedDir = { nil }` and a temp config — Tasks 4 and 5 pin it (the click test
   prints `rows: statusLine, remove`, i.e. no unpatch row).

---

## File Structure

| File | Responsibility |
|---|---|
| `scripts/patch-cat-office.sh` (modify) | `--undo [--dry-run]`; backups never collide |
| `scripts/test-setup-scripts.sh` (modify) | undo tests |
| `Sources/ClaudeBarCore/UndoPlan.swift` (create) | `UnpatchCheck`, `UndoRow`, `UndoPlan`, `UndoText` |
| `Sources/ClaudeBarCore/ClaudeBarRemoval.swift` (create) | the four folders → Trash |
| `Tests/ClaudeBarCoreTests/UndoPlanTests.swift` (create) | rows, setup state, warning, wording output |
| `Tests/ClaudeBarCoreTests/ClaudeBarRemovalTests.swift` (create) | removal |
| `Sources/ClaudeBar/Setup/SetupActions.swift` (modify) | `SetupEnvironment.launchAtLoginOff` |
| `Sources/ClaudeBar/Undo/UndoActions.swift` (create) | check, unpatch, run (shared by window and command) |
| `Sources/ClaudeBar/Undo/UndoModel.swift` (create) | the window's state |
| `Sources/ClaudeBar/Undo/UndoView.swift` (create) | the window's view |
| `Sources/ClaudeBar/Undo/UndoWindow.swift` (create) | the window |
| `Sources/ClaudeBar/Undo/UndoCommand.swift` (create) | `--undo` |
| `Sources/ClaudeBar/Setup/SetupView.swift` (modify) | `setupTarget` usable by UndoView; Welcome line + link |
| `Sources/ClaudeBar/Views/DropdownView.swift` (modify) | Settings entry |
| `Sources/ClaudeBar/AppState.swift` (modify) | `openChangesPage()` |
| `Sources/ClaudeBar/ClaudeBarMain.swift` (modify) | route `--undo` |
| `Sources/ClaudeBar/RenderPeek.swift` (modify) | `--render-undo`, `--test-undo` |
| `scripts/test-undo-command.sh` (create) | `--undo` against a temp root |
| `Resources/Help/changes.html` (create), `Resources/Help/guide.html`, `README.md` (modify) | the page |

---

### Task 1: `patch-cat-office.sh --undo`

**Files:**
- Modify: `scripts/patch-cat-office.sh` (whole file replaced below)
- Test: `scripts/test-setup-scripts.sh`

**Interfaces:**
- Produces: `patch-cat-office.sh --undo [--dry-run] <dir>` with env `CAT_OFFICE_PATCH`, `CAT_OFFICE_PATCH_HISTORY` as
  before. Exit and first output line:
  - `0` + `Unpatched <dir>` (then `Backup of the changed files: <path>`)
  - `0` + `Would unpatch <dir>` (`--dry-run`; nothing changed)
  - `0` + `Not patched: <dir>` (nothing changed)
  - `2` not Cat Office
  - `3` + stderr `Can't take the patch out of this Cat Office cleanly; nothing was changed.`
  - `64` usage error (`--dry-run` without `--undo`, unknown flag)
- Backup folders never collide: `<dir>/.cat-office/patch-backup-<stamp>`, then `-2`, `-3`… if it exists.

- [ ] **Step 1: Write the failing tests.** In `scripts/test-setup-scripts.sh`, insert this block immediately before the
  final cleanup line (`rm -rf "$mini" "$notco" ...`):

```bash
# --- Undo (--undo). An unpatched original to compare against.
orig=$(mktemp -d); cp -R "$mini/." "$orig/"; rm -rf "$orig/.cat-office"
if patch -d "$orig" -p1 -R --dry-run -s -f < "$PATCH" >/dev/null 2>&1; then patch -d "$orig" -p1 -R -s -f < "$PATCH"; fi
tree_sum() { (cd "$1" && find . -type f -not -path './.cat-office/*' | sort | while read -r f; do echo "$f $(md5 -q "$f")"; done | md5 -q); }

u=$(mktemp -d); cp -R "$orig/." "$u/"
CAT_OFFICE_PATCH="$PATCH" bash "$REPO/scripts/patch-cat-office.sh" "$u" >/dev/null 2>&1
out=$(CAT_OFFICE_PATCH="$PATCH" bash "$REPO/scripts/patch-cat-office.sh" --undo --dry-run "$u" 2>&1); code=$?
[ $code = 0 ] && [[ "$out" == "Would unpatch"* ]] && patch -d "$u" -p1 -R --dry-run -s -f < "$PATCH" >/dev/null 2>&1 \
  && ok "undo --dry-run says it would unpatch and changes nothing" || bad "undo --dry-run ($code: $out)"
out=$(CAT_OFFICE_PATCH="$PATCH" bash "$REPO/scripts/patch-cat-office.sh" --undo "$u" 2>&1); code=$?
backups=$(ls -d "$u"/.cat-office/patch-backup-* 2>/dev/null | wc -l | tr -d ' ')
[ $code = 0 ] && [[ "$out" == Unpatched* ]] && [ "$(tree_sum "$u")" = "$(tree_sum "$orig")" ] && [ "$backups" = 2 ] \
  && ok "patch then undo gives the original back, with its own backup (no collision)" || bad "undo ($code, backups $backups: $out)"

out=$(CAT_OFFICE_PATCH="$PATCH" bash "$REPO/scripts/patch-cat-office.sh" --undo "$u" 2>&1); code=$?
[ $code = 0 ] && [[ "$out" == "Not patched"* ]] && [ "$(tree_sum "$u")" = "$(tree_sum "$orig")" ] \
  && ok "undo on an unpatched copy: nothing to do" || bad "undo unpatched ($code: $out)"

e=$(mktemp -d); cp -R "$orig/." "$e/"; CAT_OFFICE_PATCH="$PATCH" bash "$REPO/scripts/patch-cat-office.sh" "$e" >/dev/null 2>&1
printf 'edited after patching\n' > "$e/$first"; before=$(tree_sum "$e")
CAT_OFFICE_PATCH="$PATCH" bash "$REPO/scripts/patch-cat-office.sh" --undo "$e" >/dev/null 2>&1; code=$?
[ $code = 3 ] && [ "$(tree_sum "$e")" = "$before" ] && ok "undo after an edit: exit 3, nothing changed" || bad "undo after an edit (got $code)"

CAT_OFFICE_PATCH="$PATCH" bash "$REPO/scripts/patch-cat-office.sh" --undo "$notco" >/dev/null 2>&1; code=$?
[ $code = 2 ] && ok "undo on a non-Cat Office folder exits 2" || bad "undo non-Cat Office (got $code)"
bash "$REPO/scripts/patch-cat-office.sh" --dry-run "$u" >/dev/null 2>&1; code=$?
[ $code = 64 ] && ok "--dry-run without --undo is a usage error" || bad "--dry-run alone (got $code)"

if [ -s "$hist/01.patch" ] && ! cmp -s "$hist/01.patch" "$PATCH"; then
  o=$(mktemp -d); cp -R "$orig/." "$o/"; patch -d "$o" -p1 -s -f < "$hist/01.patch" >/dev/null 2>&1
  out=$(CAT_OFFICE_PATCH="$PATCH" CAT_OFFICE_PATCH_HISTORY="$hist" bash "$REPO/scripts/patch-cat-office.sh" --undo "$o" 2>&1); code=$?
  [ $code = 0 ] && [[ "$out" == Unpatched* ]] && [ "$(tree_sum "$o")" = "$(tree_sum "$orig")" ] \
    && ok "undo takes out an older version of the patch" || bad "undo older version ($code: $out)"
  rm -rf "$o"
else
  echo "SKIP undo of an older version (no older patch in git)"
fi
rm -rf "$orig" "$u" "$e"
```

- [ ] **Step 2: Run them to see them fail.**
  Run: `bash scripts/test-setup-scripts.sh ~/Documents/projects/cat-ai-office-with-art-20261006-1038`
  Expected: the new undo tests print `FAIL` (the script treats `--undo` as the folder and exits 2); the 13 earlier
  tests still `PASS`.

- [ ] **Step 3: Replace `scripts/patch-cat-office.sh` with:**

```bash
#!/bin/bash
# Applies patches/cat-office.patch to a Cat Office folder: checks it's Cat Office, does a trial run,
# backs up the files it touches to .cat-office/patch-backup-<time>/, then applies. A folder carrying an older
# version of the patch (from this repo's git history) is upgraded: that version is taken out first. Changes
# nothing when the trial run fails (e.g. a newer Cat Office changed the same lines).
# With --undo: takes the patch (or an older version of it) out again, after the same trial run and backup;
# --dry-run only says whether it would.
# Usage: patch-cat-office.sh [--undo [--dry-run]] <cat-office-dir>
# Env: CAT_OFFICE_PATCH (patch file), CAT_OFFICE_PATCH_HISTORY (folder of older NN.patch, newest highest; used instead
# of git). Exit: 0 patched / already patched (undo: unpatched / would unpatch / not patched), 2 not Cat Office,
# 3 the patch doesn't fit (undo: doesn't come out cleanly), 64 usage.
set -euo pipefail
USAGE="usage: patch-cat-office.sh [--undo [--dry-run]] <cat-office-dir>"
UNDO=0; DRY=0
while [ $# -gt 0 ]; do
  case "$1" in
    --undo) UNDO=1; shift ;;
    --dry-run) DRY=1; shift ;;
    -*) echo "$USAGE" >&2; exit 64 ;;
    *) break ;;
  esac
done
if [ $# -ne 1 ] || { [ "$DRY" = 1 ] && [ "$UNDO" = 0 ]; }; then echo "$USAGE" >&2; exit 64; fi
DIR="$1"
REPO="$(cd "$(dirname "$0")/.." && pwd)"
PATCH="${CAT_OFFICE_PATCH:-$REPO/patches/cat-office.patch}"

if ! { [ -f "$DIR/package.json" ] && [ -d "$DIR/server/agent-bridge" ]; }; then
  echo "Not a Cat Office folder: $DIR" >&2; exit 2
fi

# Prints a temp copy of the newest older version of the patch that reverses cleanly in $DIR (nothing if none).
find_older() {
  local revs rev candidate
  if [ -n "${CAT_OFFICE_PATCH_HISTORY:-}" ]; then
    # Names are fixed-width NN.patch, so reverse lexical order = newest first. One path per line (paths may hold spaces).
    revs=$(ls -r "$CAT_OFFICE_PATCH_HISTORY"/*.patch 2>/dev/null || true)
  else
    revs=$(git -C "$REPO" log --format=%h -- patches/cat-office.patch 2>/dev/null || true)
  fi
  while IFS= read -r rev; do
    [ -n "$rev" ] || continue
    candidate=$(mktemp)
    if [ -n "${CAT_OFFICE_PATCH_HISTORY:-}" ]; then
      cp "$rev" "$candidate" 2>/dev/null || { rm -f "$candidate"; continue; }
    else
      git -C "$REPO" show "$rev:patches/cat-office.patch" > "$candidate" 2>/dev/null || { rm -f "$candidate"; continue; }
    fi
    if patch -d "$DIR" -p1 -R --dry-run -s -f < "$candidate" >/dev/null 2>&1; then echo "$candidate"; return; fi
    rm -f "$candidate"
  done <<< "$revs"
}

# Copies the files the given patches touch into a new .cat-office/patch-backup-<time>[-N]/ and sets BACKUP.
back_up() {
  local base n f
  base="$DIR/.cat-office/patch-backup-$(date +%Y%m%d-%H%M%S)"
  BACKUP="$base"; n=2
  while [ -e "$BACKUP" ]; do BACKUP="$base-$n"; n=$((n+1)); done   # patch then undo in the same second
  mkdir -p "$BACKUP"
  cat "$@" | grep '^+++ b/' | sed 's|^+++ b/||' | sort -u | while read -r f; do
    if [ -f "$DIR/$f" ]; then
      mkdir -p "$BACKUP/$(dirname "$f")"
      cp -p "$DIR/$f" "$BACKUP/$f"
    fi
  done
}

if [ "$UNDO" = 1 ]; then
  if patch -d "$DIR" -p1 -R --dry-run -s -f < "$PATCH" >/dev/null 2>&1; then
    REV=$(mktemp); cp "$PATCH" "$REV"
  else
    REV=$(find_older)
  fi
  if [ -z "$REV" ]; then
    if patch -d "$DIR" -p1 --dry-run -s -f < "$PATCH" >/dev/null 2>&1; then echo "Not patched: $DIR"; exit 0; fi
    echo "Can't take the patch out of this Cat Office cleanly; nothing was changed." >&2; exit 3
  fi
  if [ "$DRY" = 1 ]; then rm -f "$REV"; echo "Would unpatch $DIR"; exit 0; fi
  back_up "$REV"
  patch -d "$DIR" -p1 -R -s -f -E < "$REV"
  rm -f "$REV"
  echo "Unpatched $DIR"
  echo "Backup of the changed files: $BACKUP"
  exit 0
fi

if patch -d "$DIR" -p1 -R --dry-run -s -f < "$PATCH" >/dev/null 2>&1; then
  echo "Already patched: $DIR"; exit 0
fi
# An older version already applied? Find it in git history: it reverses cleanly, and the current one then fits.
OLD=""
if ! patch -d "$DIR" -p1 --dry-run -s -f < "$PATCH" >/dev/null 2>&1; then
  OLD=$(find_older)
  if [ -z "$OLD" ]; then
    patch -d "$DIR" -p1 --dry-run -s -f < "$PATCH" || true
    echo "The patch doesn't apply cleanly to this Cat Office; nothing was changed." >&2; exit 3
  fi
  # Trial run of the whole upgrade on a scratch copy of the touched files.
  scratch=$(mktemp -d)
  cat "$OLD" "$PATCH" | grep -E '^\+\+\+ b/' | sed 's|^+++ b/||' | sort -u | while read -r f; do
    if [ -f "$DIR/$f" ]; then mkdir -p "$scratch/$(dirname "$f")"; cp -p "$DIR/$f" "$scratch/$f"; fi
  done
  if ! { patch -d "$scratch" -p1 -R -s -f < "$OLD" && patch -d "$scratch" -p1 -s -f < "$PATCH"; } >/dev/null 2>&1; then
    rm -rf "$scratch" "$OLD"
    echo "Can't upgrade the older patch in this Cat Office cleanly; nothing was changed." >&2; exit 3
  fi
  rm -rf "$scratch"
fi

if [ -n "$OLD" ]; then back_up "$PATCH" "$OLD"; else back_up "$PATCH"; fi
if [ -n "$OLD" ]; then
  patch -d "$DIR" -p1 -R -s -f -E < "$OLD"
  rm -f "$OLD"
  echo "Took out the older version of the patch."
fi
patch -d "$DIR" -p1 -s -f < "$PATCH"
echo "Patched $DIR"
echo "Backup of the changed files: $BACKUP"
echo "Restart Cat Office (stop its dev server, then npm run dev) to load the change."
```

  (Behaviour of the patch path is unchanged except that its backup folder no longer collides; the history loop moved
  into `find_older` verbatim.)

- [ ] **Step 4: Run the tests to see them pass.**
  Run: `bash scripts/test-setup-scripts.sh ~/Documents/projects/cat-ai-office-with-art-20261006-1038`
  Expected: every line `PASS` (or the one `SKIP` when git has no older patch); last line `N passed, 0 failed` with N ≥ 19.

- [ ] **Step 5: Commit.**

```bash
git add scripts/patch-cat-office.sh scripts/test-setup-scripts.sh
git commit -m "feat: patch-cat-office.sh --undo, with backups that never collide"
```

---

### Task 2: `UndoPlan` and `UndoText` (Core)

**Files:**
- Create: `Sources/ClaudeBarCore/UndoPlan.swift`
- Test: `Tests/ClaudeBarCoreTests/UndoPlanTests.swift`

**Interfaces:**
- Consumes: `StatusLineState` (`.none/.claudeBar/.wrapped(original:)/.own(command:)/.unreadable`), `SetupSettings`
  (`seen`, `state: SetupState?`), `SetupState` (`.full/.reduced/.noCatOffice`).
- Produces (all `public`):
  - `enum UnpatchCheck: Equatable, Sendable { case patched, notPatched, cannotUndo, unknown }`
  - `struct UndoRow: Equatable, Sendable, Identifiable` with `enum Kind: String, Sendable, CaseIterable { case unpatch, statusLine, remove }`,
    `kind`, `title`, `detail`, `available: Bool` (false = greyed), `tickedAtStart: Bool`, `id: Kind`
  - `enum UndoPlan` with
    - `static func rows(catOfficeDir: String?, unpatch: UnpatchCheck, statusLine: StatusLineState, canRestore: Bool, home: String) -> [UndoRow]`
    - `static func startTicks(_ rows: [UndoRow]) -> Set<UndoRow.Kind>`
    - `static func setupAfter(_ s: SetupSettings, unpatched: Bool, statusLineRestored: Bool) -> SetupSettings`
    - `static func warning(unpatch: Bool, runningHere: Bool, somethingAnswers: Bool, bridgeNamesAnotherFolder: Bool) -> String?`
  - `enum UndoText` with the static strings below and
    - `static func doneLines(results: [UndoRow.Kind: Bool], leftOut: Bool) -> [String]`
    - `static func terminalList(rows: [UndoRow], ticked: Set<UndoRow.Kind>, warning: String?) -> String`

- [ ] **Step 1: Write the failing tests** in `Tests/ClaudeBarCoreTests/UndoPlanTests.swift`:

```swift
import Foundation
import Testing
@testable import ClaudeBarCore

@Suite struct UndoPlanTests {
    let home = "/Users/cat"
    let dir = "/Users/cat/Documents/cat-office"

    func kinds(_ rows: [UndoRow]) -> [UndoRow.Kind] { rows.map(\.kind) }

    @Test func everythingInPlaceShowsThreeRowsChangesTicked() {
        let rows = UndoPlan.rows(catOfficeDir: dir, unpatch: .patched, statusLine: .claudeBar, canRestore: true, home: home)
        #expect(kinds(rows) == [.unpatch, .statusLine, .remove])
        #expect(rows.allSatisfy(\.available))
        #expect(UndoPlan.startTicks(rows) == [.unpatch, .statusLine])
        #expect(rows[0].title == "Unpatch Cat Office" && rows[0].detail.contains("~/Documents/cat-office"))
        #expect(rows[1].title == "Restore your old status line")
        #expect(rows[2].title == "Also remove ClaudeBar" && !rows[2].tickedAtStart)
    }

    @Test func nothingToUndoShowsOnlyRemove() {
        let rows = UndoPlan.rows(catOfficeDir: dir, unpatch: .notPatched, statusLine: .none, canRestore: false, home: home)
        #expect(kinds(rows) == [.remove])
        #expect(UndoPlan.startTicks(rows).isEmpty)
        #expect(kinds(UndoPlan.rows(catOfficeDir: nil, unpatch: .unknown, statusLine: .own(command: "x"), canRestore: false, home: home)) == [.remove])
    }

    @Test func patchThatCantComeOutIsGreyedBeforeAnyClick() {
        let rows = UndoPlan.rows(catOfficeDir: dir, unpatch: .cannotUndo, statusLine: .none, canRestore: false, home: home)
        #expect(kinds(rows) == [.unpatch, .remove])
        #expect(!rows[0].available && !rows[0].tickedAtStart)
        #expect(rows[0].detail == UndoText.cannotUnpatch)
        #expect(UndoPlan.startTicks(rows).isEmpty)
    }

    @Test func claudeBarsStatusLineWithoutRecordIsGreyed() {
        let rows = UndoPlan.rows(catOfficeDir: nil, unpatch: .unknown, statusLine: .claudeBar, canRestore: false, home: home)
        #expect(kinds(rows) == [.statusLine, .remove])
        #expect(!rows[0].available && rows[0].detail == UndoText.noRecord)
    }

    @Test func statusLineChangedByHandSinceIsNotOffered() {
        // The record is stale (canRestore false) and the line is the user's own: nothing of ClaudeBar's to undo.
        let rows = UndoPlan.rows(catOfficeDir: nil, unpatch: .unknown, statusLine: .own(command: "npx ccstatusline"), canRestore: false, home: home)
        #expect(kinds(rows) == [.remove])
    }

    @Test func wrappedLineNamesTheirCommand() {
        let rows = UndoPlan.rows(catOfficeDir: nil, unpatch: .unknown, statusLine: .wrapped(original: "npx ccstatusline"), canRestore: true, home: home)
        #expect(rows[0].kind == .statusLine && rows[0].available && rows[0].detail.contains("npx ccstatusline"))
    }

    @Test func setupAfterUndo() {
        let full = SetupSettings(seen: true, state: .full)
        #expect(UndoPlan.setupAfter(full, unpatched: true, statusLineRestored: false) == SetupSettings(seen: true, state: .reduced))
        #expect(UndoPlan.setupAfter(full, unpatched: false, statusLineRestored: true) == SetupSettings(seen: true, state: .reduced))
        #expect(UndoPlan.setupAfter(full, unpatched: false, statusLineRestored: false) == full)
        let none = SetupSettings(seen: true, state: .noCatOffice)
        #expect(UndoPlan.setupAfter(none, unpatched: false, statusLineRestored: true) == none)
        #expect(UndoPlan.setupAfter(SetupSettings(seen: true, state: nil), unpatched: true, statusLineRestored: true).state == nil)
    }

    @Test func warningOnlyWhenUnpatchingSomethingThatMayBeRunning() {
        #expect(UndoPlan.warning(unpatch: false, runningHere: true, somethingAnswers: true, bridgeNamesAnotherFolder: false) == nil)
        #expect(UndoPlan.warning(unpatch: true, runningHere: true, somethingAnswers: false, bridgeNamesAnotherFolder: false)
                == "Cat Office is running: unpatching restarts it, which ends any Claude sessions running inside Cat Office.")
        #expect(UndoPlan.warning(unpatch: true, runningHere: false, somethingAnswers: true, bridgeNamesAnotherFolder: false)
                == "If Cat Office is running from this folder, unpatching restarts it, which ends any Claude sessions running inside Cat Office.")
        #expect(UndoPlan.warning(unpatch: true, runningHere: false, somethingAnswers: true, bridgeNamesAnotherFolder: true) == nil)
        #expect(UndoPlan.warning(unpatch: true, runningHere: false, somethingAnswers: false, bridgeNamesAnotherFolder: false) == nil)
    }

    @Test func doneLines() {
        #expect(UndoText.doneLines(results: [.unpatch: true, .statusLine: true], leftOut: false) == [UndoText.allDone, UndoText.extrasBack])
        #expect(UndoText.doneLines(results: [.unpatch: true], leftOut: true) == [UndoText.extrasBack])
        #expect(UndoText.doneLines(results: [.unpatch: false, .statusLine: true], leftOut: false) == [UndoText.extrasBack])
        #expect(UndoText.doneLines(results: [.statusLine: true, .remove: true], leftOut: false) == [UndoText.removed])
    }

    @Test func wordingIsTheSpecs() {
        #expect(UndoText.title == "Undo ClaudeBar's changes")
        #expect(UndoText.intro == "Pick what to undo. Everything is backed up first, and nothing of yours is deleted.")
        #expect(UndoText.allDone == "All done. Your Mac is back the way it was before ClaudeBar.")
        #expect(UndoText.extrasBack == "Want the extras back later? Settings → Set up ClaudeBar… puts them back in a minute.")
        #expect(UndoText.removed == "ClaudeBar is removed. Thanks for trying it! Come back anytime. ClaudeBar will be right here.")
        #expect(UndoText.failedSafe == "Nothing was changed here, so your setup is safe.")
        #expect(UndoText.nothingChanged == "Nothing was changed.")
    }

    @Test func terminalList() {
        let rows = UndoPlan.rows(catOfficeDir: dir, unpatch: .patched, statusLine: .claudeBar, canRestore: true, home: home)
        let text = UndoText.terminalList(rows: rows, ticked: [.unpatch], warning: "careful")
        #expect(text.hasPrefix("Undo ClaudeBar's changes\nEverything is backed up first, and nothing of yours is deleted.\n"))
        #expect(text.contains("[x] Unpatch Cat Office"))
        #expect(text.contains("[ ] Restore your old status line"))
        #expect(text.contains("[ ] Also remove ClaudeBar"))
        #expect(text.hasSuffix("⚠ careful"))
        let greyed = UndoPlan.rows(catOfficeDir: nil, unpatch: .unknown, statusLine: .claudeBar, canRestore: false, home: home)
        #expect(UndoText.terminalList(rows: greyed, ticked: [], warning: nil).contains("( ) Restore your old status line (not available)"))
    }
}
```

- [ ] **Step 2: Run them to see them fail.**
  Run: `swift test --filter UndoPlanTests 2>&1 | tail -5`
  Expected: build error, `cannot find 'UndoPlan' in scope`.

- [ ] **Step 3: Create `Sources/ClaudeBarCore/UndoPlan.swift`:**

```swift
import Foundation

/// Whether Cat Office's patch can come out (`patch-cat-office.sh --undo --dry-run`).
public enum UnpatchCheck: Equatable, Sendable {
    /// "Would unpatch": the patch (or an older version of it) comes out cleanly.
    case patched
    case notPatched
    /// Exit 3: a patched file changed since, or a version ClaudeBar doesn't know.
    case cannotUndo
    /// No Cat Office folder, not Cat Office, or the check couldn't run.
    case unknown
}

/// One line of the undo window (and of `ClaudeBar --undo`).
public struct UndoRow: Equatable, Sendable, Identifiable {
    public enum Kind: String, Sendable, CaseIterable { case unpatch, statusLine, remove }
    public var kind: Kind
    public var title: String
    public var detail: String
    /// False: shown greyed, `detail` says why and points to the manual steps.
    public var available: Bool
    public var tickedAtStart: Bool
    public var id: Kind { kind }

    public init(kind: Kind, title: String, detail: String, available: Bool, tickedAtStart: Bool) {
        self.kind = kind; self.title = title; self.detail = detail; self.available = available; self.tickedAtStart = tickedAtStart
    }
}

/// What undo offers, from what's on the Mac now; and what's true after it.
public enum UndoPlan {
    /// Only changes that are in place now, in undo order; "Also remove ClaudeBar" always, unticked.
    public static func rows(catOfficeDir: String?, unpatch: UnpatchCheck, statusLine: StatusLineState, canRestore: Bool,
                            home: String) -> [UndoRow] {
        var rows: [UndoRow] = []
        let shown = catOfficeDir.map { $0.hasPrefix(home + "/") ? "~" + $0.dropFirst(home.count) : $0 } ?? "Cat Office"
        switch unpatch {
        case .patched:
            rows.append(UndoRow(kind: .unpatch, title: "Unpatch Cat Office",
                                detail: "\(shown) · its changed files are backed up first.", available: true, tickedAtStart: true))
        case .cannotUndo:
            rows.append(UndoRow(kind: .unpatch, title: "Unpatch Cat Office", detail: UndoText.cannotUnpatch,
                                available: false, tickedAtStart: false))
        case .notPatched, .unknown:
            break
        }
        if canRestore {
            let detail: String
            if case .wrapped(let original) = statusLine {
                detail = "Back to your own status line (\(original))."
            } else {
                detail = "Back to how it was before ClaudeBar set it up."
            }
            rows.append(UndoRow(kind: .statusLine, title: "Restore your old status line", detail: detail,
                                available: true, tickedAtStart: true))
        } else if statusLine == .claudeBar {
            rows.append(UndoRow(kind: .statusLine, title: "Restore your old status line", detail: UndoText.noRecord,
                                available: false, tickedAtStart: false))
        }
        rows.append(UndoRow(kind: .remove, title: "Also remove ClaudeBar", detail: UndoText.removeDetail,
                            available: true, tickedAtStart: false))
        return rows
    }

    public static func startTicks(_ rows: [UndoRow]) -> Set<UndoRow.Kind> {
        Set(rows.filter { $0.available && $0.tickedAtStart }.map(\.kind))
    }

    /// Unpatched or usage off: a full setup is now reduced. `seen` stays, so the window never opens by itself.
    public static func setupAfter(_ s: SetupSettings, unpatched: Bool, statusLineRestored: Bool) -> SetupSettings {
        (unpatched || statusLineRestored) && s.state == .full ? SetupSettings(seen: s.seen, state: .reduced) : s
    }

    /// Unpatching makes Vite reload, which ends Claude sessions running inside Cat Office (as patching does).
    public static func warning(unpatch: Bool, runningHere: Bool, somethingAnswers: Bool, bridgeNamesAnotherFolder: Bool) -> String? {
        guard unpatch else { return nil }
        if runningHere {
            return "Cat Office is running: unpatching restarts it, which ends any Claude sessions running inside Cat Office."
        }
        if somethingAnswers, !bridgeNamesAnotherFolder {
            return "If Cat Office is running from this folder, unpatching restarts it, which ends any Claude sessions running inside Cat Office."
        }
        return nil
    }
}

/// Undo's wording (spec section 6), shared by the window and `ClaudeBar --undo`.
public enum UndoText {
    public static let title = "Undo ClaudeBar's changes"
    public static let intro = "Pick what to undo. Everything is backed up first, and nothing of yours is deleted."
    public static let promise = "Everything is backed up first, and nothing of yours is deleted."
    public static let removeDetail = "Turns off Launch at Login, then ClaudeBar quits (drag the app to the Trash yourself). "
        + "Its own files go to the Trash, so you can still get them back."
    public static let noRecord = "ClaudeBar has no record of your earlier status line, so it won't guess. Here's how to change it by hand."
    public static let cannotUnpatch = "ClaudeBar can't take its patch out cleanly (a patched file changed since), so it won't guess. "
        + "Here's how to do it by hand."
    public static let allDone = "All done. Your Mac is back the way it was before ClaudeBar."
    public static let extrasBack = "Want the extras back later? Settings → Set up ClaudeBar… puts them back in a minute."
    public static let removed = "ClaudeBar is removed. Thanks for trying it! Come back anytime. ClaudeBar will be right here."
    public static let failedSafe = "Nothing was changed here, so your setup is safe."
    public static let nothingChanged = "Nothing was changed."
    public static let question = "Undo these? [y/N] "

    /// The closing lines: removed; or all done (every change undone and worked) and the way back; or just the way back.
    public static func doneLines(results: [UndoRow.Kind: Bool], leftOut: Bool) -> [String] {
        if results[.remove] == true { return [removed] }
        if !leftOut, !results.isEmpty, results.values.allSatisfy({ $0 }) { return [allDone, extrasBack] }
        return [extrasBack]
    }

    /// The Terminal listing: `[x]` ticked, `[ ]` not, `( )` greyed; then the warning.
    public static func terminalList(rows: [UndoRow], ticked: Set<UndoRow.Kind>, warning: String?) -> String {
        var lines = [title, promise, ""]
        for row in rows {
            if row.available {
                lines.append("  \(ticked.contains(row.kind) ? "[x]" : "[ ]") \(row.title) — \(row.detail)")
            } else {
                lines.append("  ( ) \(row.title) (not available) — \(row.detail)")
            }
        }
        if let warning { lines.append(""); lines.append("⚠ \(warning)") }
        return lines.joined(separator: "\n")
    }
}
```

- [ ] **Step 4: Run them to see them pass.**
  Run: `swift test --filter UndoPlanTests 2>&1 | tail -3`
  Expected: `Test run with 11 tests passed`.

- [ ] **Step 5: Commit.**

```bash
git add Sources/ClaudeBarCore/UndoPlan.swift Tests/ClaudeBarCoreTests/UndoPlanTests.swift
git commit -m "feat: UndoPlan and UndoText — what undo offers, and its wording"
```

---

### Task 3: `ClaudeBarRemoval` (Core)

**Files:**
- Create: `Sources/ClaudeBarCore/ClaudeBarRemoval.swift`
- Test: `Tests/ClaudeBarCoreTests/ClaudeBarRemovalTests.swift`

**Interfaces:**
- Produces: `public struct ClaudeBarRemoval: Sendable` with
  - `public init(home: URL, trash: @escaping @Sendable (URL) throws -> Void = ClaudeBarRemoval.moveToTrash)`
  - `public var folders: [URL]` — `home/.config/claude-bar`, `home/.claude/claude-bar`, `home/Library/Caches/ClaudeBar`, `home/Library/Logs/ClaudeBar`
  - `public func remove() -> Result` where `public struct Result: Equatable, Sendable { public var trashed: [URL]; public var failures: [String] }`
  - `public static func moveToTrash(_ url: URL) throws`

- [ ] **Step 1: Write the failing tests** in `Tests/ClaudeBarCoreTests/ClaudeBarRemovalTests.swift`:

```swift
import Foundation
import Testing
@testable import ClaudeBarCore

@Suite struct ClaudeBarRemovalTests {
    /// A temp home with all four folders, plus things that must stay.
    func home() -> URL {
        let h = makeTempDir()
        for f in [".config/claude-bar/projects.json", ".claude/claude-bar/sessions/a.json", "Library/Caches/ClaudeBar/art/x.png",
                  "Library/Logs/ClaudeBar/cat-office.log", ".claude/settings.json", ".claude/statusline-command.sh",
                  ".claude/claude-bar-statusline.sh", ".config/other/keep.json", "Library/Caches/Other/keep"] {
            write("x", to: h.appendingPathComponent(f))
        }
        return h
    }

    /// Moves into a temp "Trash" instead of the real one.
    func fakeTrash() -> (URL, @Sendable (URL) throws -> Void) {
        let bin = makeTempDir()
        return (bin, { url in try FileManager.default.moveItem(at: url, to: bin.appendingPathComponent(UUID().uuidString)) })
    }

    func exists(_ h: URL, _ p: String) -> Bool { FileManager.default.fileExists(atPath: h.appendingPathComponent(p).path) }

    @Test func movesExactlyClaudeBarsFourFolders() {
        let h = home(); let (_, trash) = fakeTrash()
        let result = ClaudeBarRemoval(home: h, trash: trash).remove()
        #expect(result.failures.isEmpty)
        #expect(result.trashed.count == 4)
        for p in [".config/claude-bar", ".claude/claude-bar", "Library/Caches/ClaudeBar", "Library/Logs/ClaudeBar"] { #expect(!exists(h, p)) }
        // Claude Code's status line keeps working, and nothing else is touched.
        for p in [".claude/settings.json", ".claude/statusline-command.sh", ".claude/claude-bar-statusline.sh",
                  ".config/other/keep.json", "Library/Caches/Other/keep"] { #expect(exists(h, p)) }
    }

    @Test func skipsMissingFolders() {
        let h = makeTempDir(); write("x", to: h.appendingPathComponent(".config/claude-bar/projects.json"))
        let (_, trash) = fakeTrash()
        let result = ClaudeBarRemoval(home: h, trash: trash).remove()
        #expect(result.trashed == [h.appendingPathComponent(".config/claude-bar")])
        #expect(result.failures.isEmpty)
    }

    @Test func oneFailureDoesNotStopTheOthers() {
        let h = home(); let (bin, _) = fakeTrash()
        let result = ClaudeBarRemoval(home: h, trash: { url in
            if url.lastPathComponent == "Logs" || url.path.hasSuffix("Logs/ClaudeBar") { throw CocoaError(.fileWriteNoPermission) }
            try FileManager.default.moveItem(at: url, to: bin.appendingPathComponent(UUID().uuidString))
        }).remove()
        #expect(result.trashed.count == 3)
        #expect(result.failures.count == 1 && result.failures[0].contains("Library/Logs/ClaudeBar"))
        #expect(exists(h, "Library/Logs/ClaudeBar"))
    }
}
```

- [ ] **Step 2: Run them to see them fail.**
  Run: `swift test --filter ClaudeBarRemovalTests 2>&1 | tail -5`
  Expected: build error, `cannot find 'ClaudeBarRemoval' in scope`.

- [ ] **Step 3: Create `Sources/ClaudeBarCore/ClaudeBarRemoval.swift`:**

```swift
import Foundation

/// "Also remove ClaudeBar": moves ClaudeBar's own folders to the Trash (never deletes), skipping missing ones. Leaves
/// everything else, including its scripts in ~/.claude (settings.json may still run them) and every backup.
public struct ClaudeBarRemoval: Sendable {
    public struct Result: Equatable, Sendable {
        public var trashed: [URL] = []
        public var failures: [String] = []
    }

    let home: URL
    let trash: @Sendable (URL) throws -> Void

    public init(home: URL, trash: @escaping @Sendable (URL) throws -> Void = ClaudeBarRemoval.moveToTrash) {
        self.home = home
        self.trash = trash
    }

    /// Settings, usage files from the status line, the art cache, the log.
    public var folders: [URL] {
        [".config/claude-bar", ".claude/claude-bar", "Library/Caches/ClaudeBar", "Library/Logs/ClaudeBar"]
            .map { home.appendingPathComponent($0, isDirectory: true) }
    }

    public func remove() -> Result {
        var result = Result()
        for folder in folders where FileManager.default.fileExists(atPath: folder.path) {
            do {
                try trash(folder)
                result.trashed.append(folder)
            } catch {
                result.failures.append("\(folder.path): \(error.localizedDescription)")
            }
        }
        return result
    }

    public static func moveToTrash(_ url: URL) throws {
        try FileManager.default.trashItem(at: url, resultingItemURL: nil)
    }
}
```

- [ ] **Step 4: Run them to see them pass.**
  Run: `swift test --filter ClaudeBarRemovalTests 2>&1 | tail -3`
  Expected: `Test run with 3 tests passed`.

- [ ] **Step 5: Commit.**

```bash
git add Sources/ClaudeBarCore/ClaudeBarRemoval.swift Tests/ClaudeBarCoreTests/ClaudeBarRemovalTests.swift
git commit -m "feat: ClaudeBarRemoval — ClaudeBar's own folders to the Trash"
```

---

### Task 4: The undo window (app)

**Files:**
- Modify: `Sources/ClaudeBar/Setup/SetupActions.swift` (add `launchAtLoginOff` to `SetupEnvironment`)
- Create: `Sources/ClaudeBar/Undo/UndoActions.swift`, `UndoModel.swift`, `UndoView.swift`, `UndoWindow.swift`
- Modify: `Sources/ClaudeBar/Setup/SetupView.swift` (make `setupTarget` internal)
- Modify: `Sources/ClaudeBar/Views/DropdownView.swift` (Settings entry)
- Modify: `Sources/ClaudeBar/AppState.swift` (`openChangesPage()`)
- Modify: `Sources/ClaudeBar/RenderPeek.swift` (`--render-undo`, `--test-undo`)

**Interfaces:**
- Consumes: Task 1's script contract; Task 2's `UndoPlan`, `UndoRow`, `UnpatchCheck`, `UndoText`; Task 3's
  `ClaudeBarRemoval`; existing `SetupEnvironment`, `SetupActions.run/statusLine/runningDir/restartCatOffice`,
  `StepResult`, `CatOfficeDiscovery.folderToStart`, `AppState.setSetup`, `AppState.rememberedDirKey`, `SetupTargets.frames`.
- Produces:
  - `SetupEnvironment.launchAtLoginOff: @Sendable () -> Void` (default: unregister `SMAppService.mainApp` if enabled)
  - `SetupEnvironment.rememberedDir: @Sendable () -> String?` (default: `UserDefaults` `AppState.rememberedDirKey`;
    every test environment sets `{ nil }`, so no test can reach the real Cat Office)
  - `@MainActor enum UndoActions` with
    - `static func check(_ dir: String?, env: SetupEnvironment) async -> UnpatchCheck`
    - `static func rows(dir: String?, env: SetupEnvironment) async -> [UndoRow]`
    - `static func run(_ ticked: Set<UndoRow.Kind>, dir: String?, env: SetupEnvironment) async -> [UndoRow.Kind: StepResult]`
  - `UndoWindow.shared.open(state:env:offscreen:)`, `UndoWindow.shared.model`
  - `AppState.openChangesPage()`, `AppState.changesPage: URL?`
  - `ClaudeBar --render-undo <choose|choose-running|choose-greyed|done|done-failed|done-removed> <out.png>` and `ClaudeBar --test-undo`

- [ ] **Step 1: Add `launchAtLoginOff` and `rememberedDir` to `SetupEnvironment`** in `Sources/ClaudeBar/Setup/SetupActions.swift`. Add
  `import ServiceManagement` at the top, and after the `answers` property:

```swift
    /// "Also remove ClaudeBar" turns Launch at Login off (injected so tests never touch the real login item).
    var launchAtLoginOff: @Sendable () -> Void = {
        if SMAppService.mainApp.status == .enabled { try? SMAppService.mainApp.unregister() }
    }
    /// The Cat Office folder last seen running (injected so tests never find the real one and unpatch it).
    var rememberedDir: @Sendable () -> String? = { UserDefaults.standard.string(forKey: AppState.rememberedDirKey) }
```

- [ ] **Step 2: Create `Sources/ClaudeBar/Undo/UndoActions.swift`:**

```swift
import ClaudeBarCore
import Foundation

/// What undo does on disk, shared by the window and `ClaudeBar --undo`: in order, unpatch, the status line, remove.
@MainActor
enum UndoActions {
    static func script(_ env: SetupEnvironment) -> String { env.resources.appendingPathComponent("patch-cat-office.sh").path }

    static func scriptEnv(_ env: SetupEnvironment) -> [String: String] {
        ["CAT_OFFICE_PATCH": env.resources.appendingPathComponent("cat-office.patch").path,
         "CAT_OFFICE_PATCH_HISTORY": env.resources.appendingPathComponent("patch-history").path]
    }

    /// A dry run of the bundled script's --undo; changes nothing.
    static func check(_ dir: String?, env: SetupEnvironment) async -> UnpatchCheck {
        guard let dir else { return .unknown }
        let r = await SetupActions.run("/bin/bash", [script(env), "--undo", "--dry-run", dir], env: scriptEnv(env))
        switch r.code {
        case 0: return r.output.hasPrefix("Would unpatch") ? .patched : .notPatched
        case 3: return .cannotUndo
        default: return .unknown
        }
    }

    static func rows(dir: String?, env: SetupEnvironment) async -> [UndoRow] {
        let line = SetupActions.statusLine(env: env)
        return UndoPlan.rows(catOfficeDir: dir, unpatch: await check(dir, env: env), statusLine: line.state(),
                             canRestore: line.canRestore, home: env.home.path)
    }

    /// Runs the ticked rows in order; each result's text is what the window and Terminal show.
    static func run(_ ticked: Set<UndoRow.Kind>, dir: String?, env: SetupEnvironment) async -> [UndoRow.Kind: StepResult] {
        var results: [UndoRow.Kind: StepResult] = [:]
        if ticked.contains(.unpatch), let dir {
            let r = await SetupActions.run("/bin/bash", [script(env), "--undo", dir], env: scriptEnv(env))
            switch r.code {
            case 0 where r.output.hasPrefix("Unpatched"):
                results[.unpatch] = StepResult(ok: true, text: "Cat Office is unpatched (a backup of the changed files is in .cat-office/).")
            case 0:
                results[.unpatch] = StepResult(ok: true, text: "Cat Office wasn't patched, so there was nothing to undo.")
            case 3:
                results[.unpatch] = StepResult(ok: false, text: UndoText.failedSafe
                    + " ClaudeBar couldn't take its patch out cleanly; your backups are in \(dir)/.cat-office/.")
            default:
                results[.unpatch] = StepResult(ok: false, text: UndoText.failedSafe + " " + r.output)
            }
        }
        if ticked.contains(.statusLine) {
            do {
                try SetupActions.statusLine(env: env).restore()
                results[.statusLine] = StepResult(ok: true, text: "Your old status line is back.")
            } catch {
                let message = (error as? StatusLineError)?.message ?? error.localizedDescription
                results[.statusLine] = StepResult(ok: false, text: UndoText.failedSafe + " " + message)
            }
        }
        if ticked.contains(.remove) {
            env.launchAtLoginOff()
            let removal = ClaudeBarRemoval(home: env.home).remove()
            results[.remove] = removal.failures.isEmpty
                ? StepResult(ok: true, text: "Launch at Login is off, and ClaudeBar's files are in the Trash.")
                : StepResult(ok: false, text: "Some of ClaudeBar's files couldn't go to the Trash: " + removal.failures.joined(separator: "; "))
        }
        return results
    }
}
```

- [ ] **Step 3: Create `Sources/ClaudeBar/Undo/UndoModel.swift`:**

```swift
import AppKit
import ClaudeBarCore

/// The undo window's state. Nothing on disk changes before `undo()` (Undo selected).
@MainActor
final class UndoModel: ObservableObject {
    enum Phase { case loading, choose, done }

    @Published var phase: Phase = .loading
    @Published var rows: [UndoRow] = []
    @Published var ticked: Set<UndoRow.Kind> = []
    @Published var working = false
    @Published var results: [UndoRow.Kind: StepResult] = [:]
    @Published var doneLines: [String] = []
    /// Cat Office was running from the unpatched folder: Done offers Restart.
    @Published var needsRestart = false
    @Published var somethingAnswers = false

    let state: AppState
    let env: SetupEnvironment
    /// The Cat Office folder ClaudeBar knows (configured, else the one last seen running).
    let dir: String?
    var onClose: (() -> Void)?

    init(state: AppState, env: SetupEnvironment) {
        self.state = state
        self.env = env
        dir = CatOfficeDiscovery.folderToStart(configured: state.settings.catOffice.dir, remembered: env.rememberedDir())
    }

    /// Reads what's in place (off the main thread's way: the script runs detached).
    func load() async {
        rows = await UndoActions.rows(dir: dir, env: env)
        ticked = UndoPlan.startTicks(rows)
        somethingAnswers = await env.answers(state.settings.catOffice.url)
        phase = .choose
    }

    var runningHere: Bool {
        guard let dir, let running = SetupActions.runningDir(env: env) else { return false }
        return Paths.normalize(running) == Paths.normalize(dir)
    }

    var bridgeNamesAnotherFolder: Bool {
        guard let dir, let running = SetupActions.runningDir(env: env) else { return false }
        return Paths.normalize(running) != Paths.normalize(dir)
    }

    var warning: String? {
        UndoPlan.warning(unpatch: ticked.contains(.unpatch), runningHere: runningHere, somethingAnswers: somethingAnswers,
                         bridgeNamesAnotherFolder: bridgeNamesAnotherFolder)
    }

    func binding(_ kind: UndoRow.Kind) -> Bool { ticked.contains(kind) }
    func set(_ kind: UndoRow.Kind, _ on: Bool) { if on { ticked.insert(kind) } else { ticked.remove(kind) } }

    func undo() async {
        guard !working, !ticked.isEmpty else { return }
        working = true
        defer { working = false }
        let wasRunning = runningHere || (somethingAnswers && !bridgeNamesAnotherFolder)
        results = await UndoActions.run(ticked, dir: dir, env: env)
        if results[.remove] == nil {
            // After "Also remove", ClaudeBar's settings are in the Trash: writing them would make a new file.
            state.setSetup(UndoPlan.setupAfter(state.settings.setup, unpatched: results[.unpatch]?.ok == true,
                                               statusLineRestored: results[.statusLine]?.ok == true))
        }
        needsRestart = results[.unpatch]?.ok == true && wasRunning && results[.remove] == nil
        let leftOut = rows.contains { $0.available && $0.kind != .remove && !ticked.contains($0.kind) }
        doneLines = UndoText.doneLines(results: results.mapValues(\.ok), leftOut: leftOut)
        phase = .done
    }

    func restart() async {
        guard let dir else { return }
        working = true
        defer { working = false }
        if case .failed(let message) = await SetupActions.restartCatOffice(dir, env: env, settings: state.settings.catOffice) {
            results[.unpatch] = StepResult(ok: true, text: "Cat Office is unpatched. Restarting it didn't work: \(message)")
        } else {
            needsRestart = false
        }
    }

    var removed: Bool { results[.remove] != nil }

    func close() { onClose?() }
    func quit() { NSApp.terminate(nil) }
}
```

- [ ] **Step 4: Make `setupTarget` usable from UndoView.** In `Sources/ClaudeBar/Setup/SetupView.swift`, change
  `private extension View {` (above `func setupTarget`) to `extension View {`.

- [ ] **Step 5: Create `Sources/ClaudeBar/Undo/UndoView.swift`:**

```swift
import ClaudeBarCore
import SwiftUI

/// The undo window: pick, Undo selected, then what happened.
struct UndoView: View {
    static let size = CGSize(width: 460, height: 380)
    @ObservedObject var model: UndoModel
    @EnvironmentObject var state: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(model.phase == .done ? "Done" : UndoText.title).font(.title3.weight(.semibold))
            switch model.phase {
            case .loading:
                HStack(spacing: 8) { ProgressView().controlSize(.small); Text("Checking what ClaudeBar changed…").foregroundStyle(.secondary) }
                Spacer()
            case .choose: choose
            case .done: done
            }
        }
        .padding(20)
        .frame(width: Self.size.width, height: Self.size.height, alignment: .topLeading)
        .task { if model.phase == .loading { await model.load() } }
    }

    private var choose: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(UndoText.intro).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            ForEach(model.rows) { row in rowView(row) }
            if let warning = model.warning {
                Text(warning).font(.caption).foregroundStyle(Theme.waiting).fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
            HStack {
                Button("Cancel") { model.close() }
                    .disabled(model.working)
                    .setupTarget("undo-cancel")
                Spacer()
                Button {
                    Task { await model.undo() }
                } label: {
                    HStack(spacing: 6) {
                        if model.working { ProgressView().controlSize(.small) }
                        Text("Undo selected")
                    }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(model.working || model.ticked.isEmpty)
                .setupTarget("undo-run")
            }
        }
        .disabled(model.working)
    }

    @ViewBuilder private func rowView(_ row: UndoRow) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Toggle(isOn: Binding(get: { model.binding(row.kind) }, set: { model.set(row.kind, $0) })) {
                Text(row.title).font(.body.weight(.medium))
            }
            .toggleStyle(.checkbox)
            .disabled(!row.available)
            Text(row.detail).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                .padding(.leading, 20)
            if !row.available {
                Button("How to do it by hand ↗") { state.openChangesPage() }
                    .buttonStyle(.link).font(.caption).padding(.leading, 20)
            }
        }
        .opacity(row.available ? 1 : 0.6)
    }

    private var done: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(UndoRow.Kind.allCases, id: \.self) { kind in
                if let r = model.results[kind] {
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: r.ok ? "checkmark.circle.fill" : "xmark.circle.fill")
                            .foregroundStyle(r.ok ? Theme.working : Theme.waiting)
                        Text(r.text).font(.callout).fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            ForEach(model.doneLines, id: \.self) { line in
                Text(line).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            if model.needsRestart {
                Button {
                    Task { await model.restart() }
                } label: {
                    HStack(spacing: 6) {
                        if model.working { ProgressView().controlSize(.small) }
                        Text("Restart Cat Office")
                    }
                }
                .disabled(model.working)
                .setupTarget("undo-restart")
            }
            Spacer()
            HStack {
                Button("What ClaudeBar changes ↗") { state.openChangesPage() }.buttonStyle(.link)
                Spacer()
                if model.removed {
                    Button("Quit ClaudeBar") { model.quit() }.keyboardShortcut(.defaultAction).setupTarget("undo-quit")
                } else {
                    Button("Done") { model.close() }.keyboardShortcut(.defaultAction).disabled(model.working).setupTarget("undo-done")
                }
            }
        }
    }
}
```

- [ ] **Step 6: Create `Sources/ClaudeBar/Undo/UndoWindow.swift`:**

```swift
import AppKit
import ClaudeBarCore
import Combine
import SwiftUI

/// The undo window, from Settings → Undo ClaudeBar's changes….
@MainActor
final class UndoWindow {
    static let shared = UndoWindow()
    private var window: NSWindow?
    private var closeObserver: NSObjectProtocol?
    private var delegate: UndoWindowDelegate?
    private var workingWatch: AnyCancellable?
    /// The open window's model (the click test drives it; nil while closed).
    private(set) var model: UndoModel?

    /// `offscreen`: the click test's window, far off any screen and without activating the app.
    func open(state: AppState, env: SetupEnvironment = .real, offscreen: Bool = false) {
        if let window { window.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true); return }
        let model = UndoModel(state: state, env: env)
        self.model = model
        let w = NSWindow(contentRect: NSRect(origin: .zero, size: UndoView.size), styleMask: [.titled, .closable],
                         backing: .buffered, defer: false)
        w.title = UndoText.title
        w.isReleasedWhenClosed = false
        w.hidesOnDeactivate = false
        w.contentView = NSHostingView(rootView: UndoView(model: model).environmentObject(state))
        w.center()
        // While undo works the window can't close: its results would be lost, and reopening could start a second run.
        let delegate = UndoWindowDelegate(model: model)
        self.delegate = delegate
        w.delegate = delegate
        workingWatch = model.$working.sink { [weak w] working in w?.standardWindowButton(.closeButton)?.isEnabled = !working }
        model.onClose = { [weak self] in self?.window?.close() }
        closeObserver = NotificationCenter.default.addObserver(forName: NSWindow.willCloseNotification, object: w, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.window = nil
                self?.model = nil
                self?.delegate = nil
                self?.workingWatch = nil
                if let token = self?.closeObserver { NotificationCenter.default.removeObserver(token) }
                self?.closeObserver = nil
            }
        }
        window = w
        if offscreen {
            w.setFrameOrigin(NSPoint(x: -10_000, y: -10_000))
            w.orderFrontRegardless()
            return
        }
        w.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}

/// Keeps the undo window open while undo works.
@MainActor
final class UndoWindowDelegate: NSObject, NSWindowDelegate {
    weak var model: UndoModel?
    init(model: UndoModel) { self.model = model }
    func windowShouldClose(_ sender: NSWindow) -> Bool { !(model?.working ?? false) }
}
```

- [ ] **Step 7: `AppState.openChangesPage()`.** In `Sources/ClaudeBar/AppState.swift`, next to `helpGuide`
  (line ~86) add:

```swift
    /// "What ClaudeBar changes" (its own page: macOS drops #anchors when opening a local file).
    var changesPage: URL? { Bundle.main.url(forResource: "changes", withExtension: "html", subdirectory: "Help") }

    func openChangesPage() {
        guard let url = changesPage else { return }
        NSWorkspace.shared.open(url)
    }
```

- [ ] **Step 8: Settings entry.** In `Sources/ClaudeBar/Views/DropdownView.swift`, in `SettingsTabView`, directly after
  the `if let restoreMessage { … }` block and before the following `Divider()`, add:

```swift
            Button("Undo ClaudeBar's changes…") { UndoWindow.shared.open(state: state) }
                .buttonStyle(.link).font(.caption)
```

- [ ] **Step 9: Renders and the click test.** In `Sources/ClaudeBar/RenderPeek.swift`:

  (a) In `RenderPeek.runIfRequested`, after `if TestSetup.runIfRequested() { return true }` add
  `if TestUndo.runIfRequested() { return true }`, and after the `--render-setup` block add:

```swift
        // `--render-undo <choose|choose-running|choose-greyed|done|done-failed|done-removed> <out.png>`: the undo window
        // over a temp environment (never the real Mac).
        if let i = CommandLine.arguments.firstIndex(of: "--render-undo"), i + 2 < CommandLine.arguments.count {
            let args = CommandLine.arguments
            guard let model = undoModel(mode: args[i + 1], state: state) else { print("unknown undo mode \(args[i + 1])"); exit(1) }
            renderWindow(UndoView(model: model).environmentObject(state), width: UndoView.size.width,
                         to: URL(fileURLWithPath: args[i + 2]))
            return true
        }
```

  (b) After the `setupModel(step:state:)` function, add:

```swift
/// A temp environment for undo renders and the click test: never the real home, Cat Office, login item or address.
private func undoEnvironment() -> (SetupEnvironment, URL) {
    let fm = FileManager.default
    let root = fm.temporaryDirectory.appendingPathComponent("claudebar-undo-\(UUID().uuidString)").resolvingSymlinksInPath()
    let home = root.appendingPathComponent("home")
    let claude = home.appendingPathComponent(".claude")
    try? fm.createDirectory(at: claude, withIntermediateDirectories: true)
    var env = SetupEnvironment(home: home, claudeDir: claude, resources: SetupEnvironment.real.resources,
                               bridgeFile: root.appendingPathComponent("bridge.json"))
    env.answers = { _ in false }
    env.launchAtLoginOff = {}
    env.rememberedDir = { nil }
    return (env, root)
}

/// The undo window in a fixed state (rows and results set directly; `load()` never runs).
private func undoModel(mode: String, state: AppState) -> UndoModel? {
    let (env, _) = undoEnvironment()
    let model = UndoModel(state: state, env: env)
    let dir = env.home.appendingPathComponent("Documents/projects/cat-office").path
    let all = UndoPlan.rows(catOfficeDir: dir, unpatch: .patched, statusLine: .wrapped(original: "npx ccstatusline"),
                            canRestore: true, home: env.home.path)
    model.rows = all
    model.ticked = UndoPlan.startTicks(all)
    switch mode {
    case "choose": model.phase = .choose
    case "choose-running": model.phase = .choose; model.somethingAnswers = true
    case "choose-greyed":
        model.rows = UndoPlan.rows(catOfficeDir: dir, unpatch: .cannotUndo, statusLine: .claudeBar, canRestore: false, home: env.home.path)
        model.ticked = UndoPlan.startTicks(model.rows)
        model.phase = .choose
    case "done":
        model.results = [.unpatch: StepResult(ok: true, text: "Cat Office is unpatched (a backup of the changed files is in .cat-office/)."),
                         .statusLine: StepResult(ok: true, text: "Your old status line is back.")]
        model.doneLines = UndoText.doneLines(results: [.unpatch: true, .statusLine: true], leftOut: false)
        model.needsRestart = true
        model.phase = .done
    case "done-failed":
        model.results = [.unpatch: StepResult(ok: false, text: UndoText.failedSafe + " ClaudeBar couldn't take its patch out cleanly; your backups are in \(dir)/.cat-office/."),
                         .statusLine: StepResult(ok: true, text: "Your old status line is back.")]
        model.doneLines = UndoText.doneLines(results: [.unpatch: false, .statusLine: true], leftOut: false)
        model.phase = .done
    case "done-removed":
        model.results = [.statusLine: StepResult(ok: true, text: "Your old status line is back."),
                         .remove: StepResult(ok: true, text: "Launch at Login is off, and ClaudeBar's files are in the Trash.")]
        model.doneLines = UndoText.doneLines(results: [.statusLine: true, .remove: true], leftOut: false)
        model.phase = .done
    default: return nil
    }
    return model
}
```

  (c) At the end of the file add the click test:

```swift
/// `ClaudeBar --test-undo`: the undo window over a temp home only (ClaudeBar's status line installed there with a
/// record, and ClaudeBar's four folders), offscreen. Clicks only the recorded target undo-run, then prints the results,
/// the temp statusLine, and which temp folders are left. "Also remove" stays unticked, so all four must remain.
@MainActor
enum TestUndo {
    static func runIfRequested() -> Bool {
        guard CommandLine.arguments.contains("--test-undo") else { return false }
        setvbuf(stdout, nil, _IOLBF, 0)
        let (env, root) = undoEnvironment()
        let fm = FileManager.default
        try? Data(#"{"model":"opus"}"#.utf8).write(to: env.claudeDir.appendingPathComponent("settings.json"))
        do { try SetupActions.statusLine(env: env).useClaudeBar() } catch { print("couldn't install the temp status line: \(error)"); exit(1) }
        let removal = ClaudeBarRemoval(home: env.home)
        for f in removal.folders { try? fm.createDirectory(at: f, withIntermediateDirectories: true) }
        let state = AppState(config: ConfigStore(file: root.appendingPathComponent("projects.json")))
        state.sideEffects = false
        print("temp root:", root.path)

        UndoWindow.shared.open(state: state, env: env, offscreen: true)
        guard let model = UndoWindow.shared.model,
              let window = NSApp.windows.first(where: { $0.title == UndoText.title }) else { print("undo window didn't open"); exit(1) }
        DispatchQueue.main.asyncAfter(deadline: .now() + 12) { print("timed out in phase \(model.phase)"); exit(1) }

        func click(_ id: String) -> Bool {
            guard let frame = SetupTargets.frames[id], let content = window.contentView else { print("target \(id) not found"); return false }
            let target = NSRect(x: frame.minX, y: window.frame.height - frame.maxY, width: frame.width, height: frame.height)
            let point = NSPoint(x: target.midX, y: target.midY)
            guard let frameView = content.superview else { print("undo window has no frame view"); exit(1) }
            guard let hit = content.hitTest(frameView.convert(point, from: nil)) else { print("nothing under \(id)"); return false }
            let hitFrame = hit.convert(hit.bounds, to: nil)
            guard abs(hitFrame.midX - target.midX) < 4, abs(hitFrame.midY - target.midY) < 4 else {
                print("refusing to click \(id): \(type(of: hit)) at \(hitFrame) isn't the target at \(target)"); return false
            }
            print("click \(id) at window \(point) (hits \(type(of: hit)))")
            NSApp.postEvent(NSEvent.mouseEvent(with: .leftMouseUp, location: point, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                                               windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 0)!, atStart: false)
            window.sendEvent(NSEvent.mouseEvent(with: .leftMouseDown, location: point, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                                                windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1)!)
            return true
        }
        func when(_ done: @escaping @MainActor () -> Bool, _ then: @escaping @MainActor () -> Void) {
            let deadline = Date().addingTimeInterval(8)
            func poll() {
                if done() { then(); return }
                guard Date() < deadline else { print("gave up waiting in phase \(model.phase)"); exit(1) }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { MainActor.assumeIsolated { poll() } }
            }
            poll()
        }

        when({ model.phase == .choose && SetupTargets.frames["undo-run"] != nil }) {
            print("rows:", model.rows.map { "\($0.kind.rawValue)\($0.available ? "" : "(greyed)")" }.joined(separator: ", "),
                  "· ticked:", model.ticked.map(\.rawValue).sorted().joined(separator: ", "))
            guard click("undo-run") else { exit(1) }
            when({ model.phase == .done && !model.working }) {
                for kind in UndoRow.Kind.allCases { if let r = model.results[kind] { print("result \(kind.rawValue): \(r.ok ? "✓" : "✗") \(r.text)") } }
                print("done lines:", model.doneLines.joined(separator: " | "))
                let settings = (try? Data(contentsOf: env.claudeDir.appendingPathComponent("settings.json")))
                    .flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }
                print("temp settings.json statusLine:", settings?["statusLine"].map { "\($0)" } ?? "none")
                print("temp folders left:", removal.folders.filter { fm.fileExists(atPath: $0.path) }.count, "of 4")
                exit(0)
            }
        }
        return true
    }
}
```

- [ ] **Step 10: Build and run the click test.**
  Run: `bash scripts/build.sh 2>&1 | grep -E "error:|Built" ; build/ClaudeBar.app/Contents/MacOS/ClaudeBar --test-undo`
  Expected: `Built build/ClaudeBar.app`, then `rows: statusLine, remove · ticked: statusLine`, a `click undo-run …` line,
  `result statusLine: ✓ Your old status line is back.`, `done lines: All done. … | Want the extras back later? …`,
  `temp settings.json statusLine: none`, `temp folders left: 4 of 4`. Exit 0.

- [ ] **Step 11: Render each mode and look at them.**
  Run: `mkdir -p /tmp/cb-mock && for m in choose choose-running choose-greyed done done-failed done-removed; do build/ClaudeBar.app/Contents/MacOS/ClaudeBar --render-undo $m /tmp/cb-mock/undo-$m.png; done; ls /tmp/cb-mock/undo-*.png`
  Expected: six PNGs. Open each with the Read tool: text not clipped; `choose-running` shows the amber warning;
  `choose-greyed` shows both change rows dimmed with "How to do it by hand ↗"; `done-removed` shows "Quit ClaudeBar".
  If the content is clipped, raise `UndoView.size.height` (and note it in the report).

- [ ] **Step 12: Run all Swift tests.**
  Run: `swift test 2>&1 | grep -E "tests passed|failed after" | tail -1`
  Expected: `Test run with N tests passed` (N = previous count + 14).

- [ ] **Step 13: Commit.**

```bash
git add Sources/ClaudeBar/Undo Sources/ClaudeBar/Setup/SetupActions.swift Sources/ClaudeBar/Setup/SetupView.swift \
  Sources/ClaudeBar/Views/DropdownView.swift Sources/ClaudeBar/AppState.swift Sources/ClaudeBar/RenderPeek.swift
git commit -m "feat: Undo ClaudeBar's changes window, with renders and a click test"
```

---

### Task 5: `ClaudeBar --undo` (Terminal)

**Files:**
- Create: `Sources/ClaudeBar/Undo/UndoCommand.swift`
- Modify: `Sources/ClaudeBar/ClaudeBarMain.swift`
- Create: `scripts/test-undo-command.sh`

**Interfaces:**
- Consumes: `UndoActions.rows/run`, `UndoPlan`, `UndoText`, `SetupActions.runningDir`, `ConfigStore`, `AppState.rememberedDirKey`.
- Produces: `ClaudeBar --undo [--remove]`. Exit 0 when every chosen row worked or nothing was chosen/confirmed; 1
  otherwise. Test hook: env `CLAUDEBAR_UNDO_ROOT=<dir>` uses `<dir>/home` as home (`<dir>/home/.claude`),
  `<dir>/bridge.json`, `<dir>/projects.json`; nothing answers; Launch at Login and the running-ClaudeBar check are
  skipped; the remembered Cat Office folder is ignored.

- [ ] **Step 1: Write the failing test** `scripts/test-undo-command.sh`:

```bash
#!/bin/bash
# scripts/test-undo-command.sh — ClaudeBar --undo against a temp root only (CLAUDEBAR_UNDO_ROOT). Needs build/ClaudeBar.app.
set -uo pipefail
REPO="$(cd "$(dirname "$0")/.." && pwd)"
BIN="$REPO/build/ClaudeBar.app/Contents/MacOS/ClaudeBar"
pass=0; fail=0
ok() { echo "PASS $1"; pass=$((pass+1)); }
bad() { echo "FAIL $1"; fail=$((fail+1)); }

# A temp home where setup installed ClaudeBar's status line (no status line before), with its record, and
# ClaudeBar's four folders.
fresh() {
  root=$(mktemp -d); c="$root/home/.claude"; mkdir -p "$c" "$root/home/.config/claude-bar" "$root/home/.claude/claude-bar" \
    "$root/home/Library/Caches/ClaudeBar" "$root/home/Library/Logs/ClaudeBar"
  printf '{"model":"opus","statusLine":{"type":"command","command":"bash ~/.claude/statusline-command.sh"}}' > "$c/settings.json"
  cp "$REPO/scripts/statusline-command.sh" "$c/statusline-command.sh"
  printf '{}' > "$c/claude-bar-statusline-original.json"
}

fresh; before=$(md5 -q "$c/settings.json")
out=$(echo n | CLAUDEBAR_UNDO_ROOT="$root" "$BIN" --undo 2>&1); code=$?
[ $code = 0 ] && [[ "$out" == *"[x] Restore your old status line"* ]] && [[ "$out" == *"Nothing was changed."* ]] \
  && [ "$(md5 -q "$c/settings.json")" = "$before" ] && ok "answering n changes nothing" || bad "n ($code): $out"
out=$(CLAUDEBAR_UNDO_ROOT="$root" "$BIN" --undo < /dev/null 2>&1); code=$?
[ $code = 0 ] && [[ "$out" == *"Nothing was changed."* ]] && [ "$(md5 -q "$c/settings.json")" = "$before" ] \
  && ok "no answer (EOF) changes nothing" || bad "EOF ($code): $out"

out=$(echo y | CLAUDEBAR_UNDO_ROOT="$root" "$BIN" --undo 2>&1); code=$?
has=$(plutil -extract statusLine raw "$c/settings.json" >/dev/null 2>&1 && echo yes || echo no)
[ $code = 0 ] && [[ "$out" == *"✓ Your old status line is back."* ]] && [[ "$out" == *"All done."* ]] && [ "$has" = no ] \
  && [ "$(plutil -extract model raw "$c/settings.json")" = opus ] && [ -d "$root/home/.config/claude-bar" ] \
  && ok "y restores the status line and keeps ClaudeBar's folders" || bad "y ($code, statusLine $has): $out"
rm -rf "$root"

fresh
out=$(echo y | CLAUDEBAR_UNDO_ROOT="$root" "$BIN" --undo --remove 2>&1); code=$?
left=0; for f in .config/claude-bar .claude/claude-bar Library/Caches/ClaudeBar Library/Logs/ClaudeBar; do [ -e "$root/home/$f" ] && left=$((left+1)); done
[ $code = 0 ] && [[ "$out" == *"[x] Also remove ClaudeBar"* ]] && [[ "$out" == *"Come back anytime."* ]] && [ $left = 0 ] \
  && [ -f "$c/statusline-command.sh" ] && ok "--remove moves the four folders to the Trash, keeps the script" || bad "--remove ($code, left $left): $out"
rm -rf "$root"

echo "$pass passed, $fail failed"; [ $fail = 0 ]
```

  Note: the `--remove` case moves four empty temp folders to the user's Trash (named `claude-bar`, `ClaudeBar`…); that
  is the real `trashItem` path being tested, on temp folders only.

- [ ] **Step 2: Run it to see it fail.**
  Run: `bash scripts/build.sh >/dev/null && bash scripts/test-undo-command.sh`
  Expected: `FAIL` lines (ClaudeBar starts as a menu bar app instead; kill it with `pkill -f build/ClaudeBar.app` if
  it stays running), `0 passed, 4 failed`.

- [ ] **Step 3: Create `Sources/ClaudeBar/Undo/UndoCommand.swift`:**

```swift
import AppKit
import ClaudeBarCore
import Foundation

/// `ClaudeBar --undo [--remove]`: the undo window's rows in Terminal, a y/N question, then the same undo.
@MainActor
enum UndoCommand {
    static func run(remove: Bool) -> Never {
        setvbuf(stdout, nil, _IOLBF, 0)
        Task { @MainActor in exit(await main(remove: remove)) }
        dispatchMain()
    }

    static func main(remove: Bool) async -> Int32 {
        let testRoot = ProcessInfo.processInfo.environment["CLAUDEBAR_UNDO_ROOT"].map { URL(fileURLWithPath: $0) }
        var env = SetupEnvironment.real
        let config: ConfigStore
        if let root = testRoot {
            let home = root.appendingPathComponent("home")
            env.home = home
            env.claudeDir = home.appendingPathComponent(".claude")
            env.bridgeFile = root.appendingPathComponent("bridge.json")
            env.answers = { _ in false }
            env.launchAtLoginOff = {}
            env.rememberedDir = { nil }
            config = ConfigStore(file: root.appendingPathComponent("projects.json"))
        } else {
            config = ConfigStore()
        }
        let settings = config.config
        let dir = CatOfficeDiscovery.folderToStart(configured: settings.catOffice.dir, remembered: env.rememberedDir())

        let rows = await UndoActions.rows(dir: dir, env: env)
        var ticked = UndoPlan.startTicks(rows)
        if remove { ticked.insert(.remove) }
        let running = SetupActions.runningDir(env: env)
        let runningHere = dir != nil && running.map(Paths.normalize) == dir.map(Paths.normalize)
        let another = dir != nil && running != nil && !runningHere
        let answers = await env.answers(settings.catOffice.url)
        let warning = UndoPlan.warning(unpatch: ticked.contains(.unpatch), runningHere: runningHere,
                                       somethingAnswers: answers, bridgeNamesAnotherFolder: another)
        print(UndoText.terminalList(rows: rows, ticked: ticked, warning: warning))
        print("")

        if remove, testRoot == nil, otherClaudeBarRunning() {
            print("Quit ClaudeBar first (click the cat in the menu bar, then Quit), then run this again.")
            print(UndoText.nothingChanged)
            return 1
        }
        guard !ticked.isEmpty else { print(UndoText.nothingChanged); return 0 }
        print(UndoText.question, terminator: "")
        let answer = readLine()?.trimmingCharacters(in: .whitespaces).lowercased()
        guard answer == "y" || answer == "yes" else { print(""); print(UndoText.nothingChanged); return 0 }

        let results = await UndoActions.run(ticked, dir: dir, env: env)
        if results[.remove] == nil {
            let after = UndoPlan.setupAfter(settings.setup, unpatched: results[.unpatch]?.ok == true,
                                            statusLineRestored: results[.statusLine]?.ok == true)
            if let state = after.state, after != settings.setup { try? config.set(state.rawValue, at: ["setup", "state"]) }
        }
        print("")
        for kind in UndoRow.Kind.allCases {
            if let r = results[kind] { print("\(r.ok ? "✓" : "✗") \(r.text)") }
        }
        let leftOut = rows.contains { $0.available && $0.kind != .remove && !ticked.contains($0.kind) }
        for line in UndoText.doneLines(results: results.mapValues(\.ok), leftOut: leftOut) { print(line) }
        if results[.unpatch]?.ok == true, runningHere || (answers && !another) {
            print("Cat Office was running: if it looks stuck, stop its dev server and run npm run dev again.")
        }
        return results.values.allSatisfy(\.ok) ? 0 : 1
    }

    /// Another ClaudeBar (the menu bar app) is running.
    static func otherClaudeBarRunning() -> Bool {
        guard let id = Bundle.main.bundleIdentifier else { return false }
        return NSRunningApplication.runningApplications(withBundleIdentifier: id)
            .contains { $0.processIdentifier != ProcessInfo.processInfo.processIdentifier }
    }
}
```

- [ ] **Step 4: Route `--undo`** in `Sources/ClaudeBar/ClaudeBarMain.swift`: in `main()`, right after
  `let args = CommandLine.arguments` add:

```swift
        // `ClaudeBar --undo [--remove]`: undo ClaudeBar's changes from Terminal (see UndoCommand).
        if args.contains("--undo") { UndoCommand.run(remove: args.contains("--remove")) }
```

- [ ] **Step 5: Run the test to see it pass.**
  Run: `bash scripts/build.sh 2>&1 | grep -E "error:|Built" && bash scripts/test-undo-command.sh`
  Expected: `Built build/ClaudeBar.app`, four `PASS` lines, `4 passed, 0 failed`.

- [ ] **Step 6: Run all Swift tests and the script tests.**
  Run: `swift test 2>&1 | grep -E "tests passed|failed after" | tail -1; bash scripts/test-setup-scripts.sh ~/Documents/projects/cat-ai-office-with-art-20261006-1038 | tail -1`
  Expected: all Swift tests pass; `… passed, 0 failed`.

- [ ] **Step 7: Commit.**

```bash
chmod +x scripts/test-undo-command.sh
git add Sources/ClaudeBar/Undo/UndoCommand.swift Sources/ClaudeBar/ClaudeBarMain.swift scripts/test-undo-command.sh
git commit -m "feat: ClaudeBar --undo [--remove] for Terminal"
```

---

### Task 6: "What ClaudeBar changes" page, guide, README, Welcome link

**Files:**
- Create: `Resources/Help/changes.html`
- Modify: `Resources/Help/guide.html`, `README.md`, `Sources/ClaudeBar/Setup/SetupView.swift` (Welcome step)

**Interfaces:**
- Consumes: `AppState.openChangesPage()` (Task 4). `scripts/build.sh` already copies `Resources/Help/` whole.

- [ ] **Step 1: Create `Resources/Help/changes.html`** (same look as the guide):

```html
<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>What ClaudeBar changes</title>
<style>
  :root { color-scheme: light dark; --muted: #6b6b70; --line: #e3e0dc; --card: #f6f3ef; --accent: #3d9a6a; }
  @media (prefers-color-scheme: dark) { :root { --muted: #a3a3aa; --line: #3a3836; --card: #242220; --accent: #6cc797; } }
  body { font: 16px/1.55 -apple-system, BlinkMacSystemFont, "SF Pro Text", sans-serif; max-width: 760px; margin: 40px auto; padding: 0 22px; }
  h1 { font-size: 30px; margin-bottom: 4px; }
  h2 { font-size: 21px; margin-top: 34px; padding-top: 14px; border-top: 1px solid var(--line); }
  h3 { font-size: 16px; margin: 18px 0 4px; }
  p, li { margin: 6px 0; }
  .lead { color: var(--muted); margin-top: 0; }
  table { border-collapse: collapse; width: 100%; margin: 10px 0; font-size: 15px; }
  td, th { text-align: left; padding: 7px 10px; border-bottom: 1px solid var(--line); vertical-align: top; }
  th { color: var(--muted); font-weight: 600; }
  code { background: var(--card); padding: 1px 5px; border-radius: 5px; font-size: 14px; }
  .tip { background: var(--card); border-left: 3px solid var(--accent); padding: 10px 14px; border-radius: 6px; }
  a { color: var(--accent); }
</style>
</head>
<body>

<h1>🐈 What ClaudeBar changes</h1>
<p class="lead">ClaudeBar is built to be safe to try. Here's exactly what it changes, and how to undo each change.</p>

<h2>What it changes</h2>
<p>Nothing changes until you click <b>Continue</b> in setup. Everything ClaudeBar changes is in these five places:</p>
<table>
  <tr><th>Place</th><th>What changes</th><th>Backup</th></tr>
  <tr><td><code>~/.config/claude-bar/</code></td><td>ClaudeBar's own settings.</td><td>Not needed: it's ClaudeBar's own.</td></tr>
  <tr><td><code>~/.claude/claude-bar/</code></td><td>ClaudeBar's own usage files, written by the status line.</td><td>Not needed: it's ClaudeBar's own.</td></tr>
  <tr><td><code>~/.claude/settings.json</code></td><td>Only the <code>statusLine</code> entry, so Claude Code shows usage. Every other setting stays.</td><td><code>~/.claude/settings.json.claude-bar-backup-&lt;time&gt;</code></td></tr>
  <tr><td><code>~/.claude/statusline-command.sh</code></td><td>ClaudeBar's status line script, only if you chose ClaudeBar's status line. If you kept yours, it's untouched and ClaudeBar adds <code>claude-bar-statusline.sh</code> next to it.</td><td><code>~/.claude/statusline-command.sh.claude-bar-backup-&lt;time&gt;</code></td></tr>
  <tr><td>Your Cat Office folder</td><td>A small patch, so cats match the browser, helpers show and usage works without a terminal.</td><td><code>&lt;Cat Office&gt;/.cat-office/patch-backup-&lt;time&gt;/</code></td></tr>
</table>
<p>Launch at Login is only on if you turn it on in Settings.</p>

<h2>What it never does</h2>
<ul>
  <li>It talks only to the Cat Office on your own Mac (<code>localhost</code>), never the internet.</li>
  <li>It never starts, stops or controls your Claude agents, and never touches your projects or git.</li>
  <li>Nothing changes before you click Continue.</li>
  <li>It never deletes your files. Removing ClaudeBar moves its own files to the Trash.</li>
</ul>

<h2>What can interrupt your work</h2>
<p class="tip">Patching or unpatching Cat Office restarts it, which ends the Claude sessions running inside Cat Office.
ClaudeBar warns you before it does. Claude Code sessions in your own terminal aren't affected.</p>

<h2>How to undo</h2>
<h3>The easy way</h3>
<p><b>Settings → Undo ClaudeBar's changes…</b> lists what ClaudeBar changed on your Mac. Pick what to undo; everything
is backed up first. Tick <b>Also remove ClaudeBar</b> to remove it too.</p>
<p>From Terminal: <code>~/Applications/ClaudeBar.app/Contents/MacOS/ClaudeBar --undo</code> (add <code>--remove</code>
to remove ClaudeBar too). If you run ClaudeBar from its project folder, use
<code>build/ClaudeBar.app/Contents/MacOS/ClaudeBar --undo</code>.</p>
<h3>By hand (if ClaudeBar won't run)</h3>
<ul>
  <li><b>Cat Office:</b> stop Cat Office, then copy the files from the newest <code>.cat-office/patch-backup-*</code>
    folder back into your Cat Office folder (same paths), and start it again.</li>
  <li><b>Status line:</b> copy the newest <code>~/.claude/settings.json.claude-bar-backup-*</code> back to
    <code>~/.claude/settings.json</code>; if there's a <code>statusline-command.sh.claude-bar-backup-*</code>, copy it back
    to <code>~/.claude/statusline-command.sh</code>. No backup? Remove the <code>statusLine</code> entry from
    <code>settings.json</code>.</li>
  <li><b>ClaudeBar's own files:</b> move <code>~/.config/claude-bar</code>, <code>~/.claude/claude-bar</code>,
    <code>~/Library/Caches/ClaudeBar</code> and <code>~/Library/Logs/ClaudeBar</code> to the Trash.</li>
  <li><b>Launch at Login:</b> System Settings → General → Login Items, remove ClaudeBar.</li>
  <li><b>The app:</b> quit ClaudeBar and drag it to the Trash.</li>
</ul>

<p class="lead" style="margin-top:40px">Changed your mind? You can undo everything in a minute, and set it up again
whenever you like. Questions? Ask the teammate who shared ClaudeBar with you.</p>
</body>
</html>
```

- [ ] **Step 2: Link it from the guide.** In `Resources/Help/guide.html`:
  - In `<nav>`, after `<a href="#problems">If something's wrong</a>` add `<a href="changes.html">What ClaudeBar changes</a>`.
  - Directly before `<h2 id="problems">`, add:

```html
<h2 id="changes">What ClaudeBar changes</h2>
<p>ClaudeBar is built to be safe to try: nothing changes until you click Continue, everything is backed up first,
and you can undo it all from <b>Settings → Undo ClaudeBar's changes…</b>. See
<a href="changes.html">What ClaudeBar changes</a> for every place it touches and how to undo each one.</p>
```

- [ ] **Step 3: README.** In `README.md`, directly before `## Setting up ClaudeBar`, add:

```markdown
## What ClaudeBar changes (and how to undo it)

ClaudeBar is built to be safe to try. Nothing changes until you click Continue in setup, every change is backed up
first, and nothing of yours is deleted. It talks only to the Cat Office on your own Mac (`localhost`), and never
controls your Claude agents, projects or git.

| Place | What changes | Backup |
|---|---|---|
| `~/.config/claude-bar/` | ClaudeBar's settings | — (its own) |
| `~/.claude/claude-bar/` | ClaudeBar's usage files | — (its own) |
| `~/.claude/settings.json` | only the `statusLine` entry | `settings.json.claude-bar-backup-<time>` |
| `~/.claude/statusline-command.sh` | ClaudeBar's script, only if you chose it | `statusline-command.sh.claude-bar-backup-<time>` |
| your Cat Office folder | the patch | `.cat-office/patch-backup-<time>/` |

Patching or unpatching Cat Office restarts it, which ends the Claude sessions running inside Cat Office (you're warned
first).

**Undo:** Settings → **Undo ClaudeBar's changes…**, or `ClaudeBar --undo` (`--remove` to remove ClaudeBar too) from the
binary inside the app. The full page, with the by-hand steps: `Resources/Help/changes.html` (also in the app's guide).
Changed your mind? You can undo everything in a minute, and set it up again whenever you like.

`scripts/test-undo-command.sh` tests `--undo` against a temp folder (after `scripts/build.sh`).
```

- [ ] **Step 4: Welcome step line and link.** In `Sources/ClaudeBar/Setup/SetupView.swift`, in `welcome`, directly after
  `.setupTarget("setup-skip-welcome")` (the Skip button), add:

```swift
            VStack(spacing: 2) {
                Text("Nothing changes until you say so, and you can undo everything later.")
                    .font(.caption).foregroundStyle(.secondary)
                Button("What will ClaudeBar change?") { state.openChangesPage() }
                    .buttonStyle(.link).font(.caption)
                    .setupTarget("setup-changes")
            }
            .padding(.top, 4)
```

  (`SetupView` already has `@EnvironmentObject var state: AppState`; its Done step calls `state.openHelpGuide()`.)

- [ ] **Step 5: Build, check the bundle, render the Welcome step.**
  Run: `bash scripts/build.sh 2>&1 | grep -E "error:|Built"; ls build/ClaudeBar.app/Contents/Resources/Help/changes.html; build/ClaudeBar.app/Contents/MacOS/ClaudeBar --render-setup welcome /tmp/cb-mock/setup-welcome-changes.png`
  Expected: `Built …`, the path printed, and the PNG written. Read the PNG: the new line and link sit under "Skip for
  now" without clipping. If clipped, reduce the top `Spacer()` use (e.g. replace the first `Spacer()` in `welcome`
  with `Spacer(minLength: 8)`) and re-render.

- [ ] **Step 6: Run the setup click test (the Welcome step changed).**
  Run: `build/ClaudeBar.app/Contents/MacOS/ClaudeBar --test-setup | tail -4`
  Expected: as before: the run reaches `step done`, `setup state: …`, `chosen is the temp Cat Office: true`, exit 0.

- [ ] **Step 7: Commit.**

```bash
git add Resources/Help/changes.html Resources/Help/guide.html README.md Sources/ClaudeBar/Setup/SetupView.swift
git commit -m "docs: What ClaudeBar changes page, linked from the guide, README and setup's Welcome"
```

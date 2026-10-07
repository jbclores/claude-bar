# ClaudeBar Onboarding Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A first-run setup window that finds the user's Cat Office, patches it, sets up the status line and starts Cat
Office, with an Office-tab card and a Settings row to reopen it.

**Architecture:**
- **Shell scripts (existing logic):** the patch and dev-server-stop scripts already in the repo, made usable from inside
  the app. They read bundled files and a bundled patch history instead of git.
- **Pure Core units, tested in temp folders:** finding Cat Office (`CatOfficeFinder`), the status line
  (`StatusLineSetup`), and the setup state (`SetupSettings`).
- **App layer:**
  - `SetupActions`: runs the scripts and the launcher, against an injectable environment, so tests never touch the real
    home folder
  - `SetupModel`: the steps' state
  - SwiftUI views in an `NSWindow`, plus the Office card and the Settings row

**Tech Stack:** Swift 6 toolchain (language mode 5), SwiftPM, SwiftUI + AppKit, Swift Testing, macOS 14+, bash, BSD
`patch`.

**Spec:** `docs/superpowers/specs/2026-10-07-claudebar-onboarding-design.md`

## Global Constraints

- Nothing changes on the user's Mac until they click Continue. Every change is backed up first. Setup never deletes
  anything.
- Setup only touches:
  - the Cat Office folder the user confirmed
  - `~/.claude/settings.json`
  - `~/.claude/statusline-command.sh`
  - ClaudeBar's own files in `~/.claude` (`claude-bar-hook.sh`, `claude-bar-statusline.sh`,
    `claude-bar-statusline-original.json`)
  - ClaudeBar's config
- The patch and the scripts ship inside the app (`Contents/Resources/Setup/`). A zip install needs nothing else, and no
  git.
- **Skipping:**
  - "Skip for now" closes the window, and it never opens by itself again (`setup.seen = true`).
  - The Office card and **Settings → Set up ClaudeBar…** reopen it.
- **Searched places** (two levels deep), in this order: `~/Documents`, `~/Documents/projects`, `~/Downloads`,
  `~/Desktop`, `~/Developer`, `~/Projects`.
- A folder is Cat Office if it has a `package.json` file and a `server/agent-bridge/` folder.
- **Status line:**

  | The user has | Setup does |
  |---|---|
  | No status line | Install ClaudeBar's |
  | Their own | Ask "Keep your status line" (default: wrap it) or "Use ClaudeBar's status line" (back theirs up; restorable) |
  | ClaudeBar's | Nothing |

- **Restart:** "Restart Cat Office" stops only Cat Office's own dev server, and the button says that this ends any Claude
  sessions running inside Cat Office.
- Tests and the click test never touch the real `~/.claude`, the real Cat Office, or the real ClaudeBar config. They use
  temp folders through `SetupEnvironment`.
- Commit messages end with `Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>`.

## Review Focus

1. **Existing users updating ClaudeBar** (the user's own Mac, already patched, with ClaudeBar's status line): the setup
   window must not pop up. The state is inferred as Full and `seen` is set quietly. Pinned in Task 4
   (`anExistingSetupIsNotAskedAgain`).
2. **An older ClaudeBar status line** (the script differs byte-for-byte from the bundled one) is recognised as
   ClaudeBar's, not as "their own". Pinned in Task 3 (`anOlderClaudeBarScriptIsStillClaudeBars`).
3. **A user's own status line command with quotes, pipes or `~`** keeps working, byte-for-byte, when wrapped. Pinned in
   Task 3 (`wrappingKeepsTheirOutputExactly`), which runs the wrapper with bash.
4. **`settings.json` with other keys, or one that doesn't parse:** other keys survive an edit, and a broken file is left
   untouched with the state `unreadable`. Pinned in Task 3 (`otherSettingsSurvive`, `aBrokenSettingsFileIsLeftAlone`).
5. **Several Cat Office copies, including one inside another and a symlink to the same folder:** each real folder is
   listed once, newest first, and none is searched inside another. Pinned in Task 2 (`eachCopyOnceNewestFirst`).

---

## File Structure

| File | Responsibility |
|---|---|
| `scripts/patch-cat-office.sh` (modify) | Reads `CAT_OFFICE_PATCH` / `CAT_OFFICE_PATCH_HISTORY` when set (the app); exit codes 0 patched or already, 2 not Cat Office, 3 doesn't fit |
| `scripts/stop-cat-office.sh` (create) | Stops a Cat Office folder's dev server (moved out of `move-cat-office.sh`) |
| `scripts/move-cat-office.sh` (modify) | Uses `stop-cat-office.sh` |
| `scripts/statusline-command.sh` (modify) | `CLAUDEBAR_STATUSLINE_QUIET=1`: save the data, print nothing |
| `scripts/test-setup-scripts.sh` (create) | Tests for the three scripts, in temp folders |
| `scripts/build.sh` (modify) | Bundles `Setup/`: the patch, its history from git, and the scripts |
| `Sources/ClaudeBarCore/CatOfficeFinder.swift` | Recognise, search and order Cat Office copies |
| `Sources/ClaudeBarCore/StatusLineSetup.swift` | Read, install, wrap and restore the status line |
| `Sources/ClaudeBarCore/SetupSettings.swift` | The setup state and `seen`, the config keys, inference for existing setups |
| `Sources/ClaudeBar/Setup/SetupActions.swift` | Runs the patch, stop and start; `SetupEnvironment` |
| `Sources/ClaudeBar/Setup/SetupModel.swift` | The steps' state and the Continue logic |
| `Sources/ClaudeBar/Setup/SetupView.swift` | The four steps (SwiftUI) |
| `Sources/ClaudeBar/Setup/SetupWindow.swift` | The `NSWindow` and its opening rules |
| `Sources/ClaudeBar/Views/DropdownView.swift`, `OfficePeekView.swift` (modify) | The Office card and the Settings row |
| `Sources/ClaudeBar/RenderPeek.swift` (modify) | `--render-setup` and `--test-setup` |

---

### Task 1: Make the scripts usable from the app

**Files:**
- Modify: `scripts/patch-cat-office.sh`, `scripts/move-cat-office.sh`, `scripts/statusline-command.sh`
- Create: `scripts/stop-cat-office.sh`, `scripts/test-setup-scripts.sh`

**Interfaces:**
- Produces:
  - `patch-cat-office.sh <dir>`:
    - env `CAT_OFFICE_PATCH`: the patch file (default `$REPO/patches/cat-office.patch`)
    - env `CAT_OFFICE_PATCH_HISTORY`: a folder of older versions named `NN.patch`, newest highest; used instead of
      git when set
    - exit codes: 0 patched or already patched (stdout's first line starts with `Patched` or `Already patched`);
      2 not Cat Office; 3 doesn't fit
  - `stop-cat-office.sh <dir> [--check]`:
    - exit 0: stopped, or nothing running
    - exit 1: it didn't stop, or the script runs inside Cat Office
    - prints `Would stop:` lines with `--check`
  - `statusline-command.sh`: with `CLAUDEBAR_STATUSLINE_QUIET=1` it writes the data and prints nothing

- [ ] **Step 1: Write the failing tests**

```bash
#!/bin/bash
# scripts/test-setup-scripts.sh — tests for the setup scripts, in temp folders only.
# Usage: scripts/test-setup-scripts.sh <cat-office-dir>   (read-only: only the patched files are copied out)
set -uo pipefail
CO="${1:?usage: test-setup-scripts.sh <cat-office-dir>}"
REPO="$(cd "$(dirname "$0")/.." && pwd)"
PATCH="$REPO/patches/cat-office.patch"
pass=0; fail=0
ok() { echo "PASS $1"; pass=$((pass+1)); }
bad() { echo "FAIL $1"; fail=$((fail+1)); }

# A mini Cat Office: package.json, server/agent-bridge, and the files the patch touches, unpatched.
mini=$(mktemp -d)
mkdir -p "$mini/server/agent-bridge"; echo '{"name":"cat-office"}' > "$mini/package.json"
grep '^+++ b/' "$PATCH" | sed 's|^+++ b/||' | while read -r f; do
  if [ -f "$CO/$f" ]; then mkdir -p "$mini/$(dirname "$f")"; cp "$CO/$f" "$mini/$f"; fi
done
if patch -d "$mini" -p1 -R --dry-run -s -f < "$PATCH" >/dev/null 2>&1; then patch -d "$mini" -p1 -R -s -f < "$PATCH"; fi
# Files the patch creates must not exist in an unpatched copy.
grep -B1 '^+++ b/' "$PATCH" | grep -A1 '^--- /dev/null' | grep '^+++ b/' | sed 's|^+++ b/||' | while read -r f; do rm -f "$mini/$f"; done

out=$(CAT_OFFICE_PATCH="$PATCH" bash "$REPO/scripts/patch-cat-office.sh" "$mini"); code=$?
[ $code = 0 ] && [[ "$out" == Patched* ]] && ok "patches a fresh copy" || bad "patches a fresh copy ($code: $out)"
out=$(CAT_OFFICE_PATCH="$PATCH" bash "$REPO/scripts/patch-cat-office.sh" "$mini"); code=$?
[ $code = 0 ] && [[ "$out" == Already* ]] && ok "already patched is not patched twice" || bad "already patched ($code: $out)"

notco=$(mktemp -d)
CAT_OFFICE_PATCH="$PATCH" bash "$REPO/scripts/patch-cat-office.sh" "$notco" >/dev/null 2>&1; code=$?
[ $code = 2 ] && ok "not Cat Office exits 2" || bad "not Cat Office exits 2 (got $code)"

broken=$(mktemp -d); cp -R "$mini/." "$broken/"; patch -d "$broken" -p1 -R -s -f < "$PATCH"
first=$(grep '^+++ b/' "$PATCH" | sed 's|^+++ b/||' | while read -r f; do [ -f "$broken/$f" ] && { echo "$f"; break; }; done)
printf 'changed by a newer Cat Office\n' > "$broken/$first"; before=$(cd "$broken" && find . -type f -exec md5 -q {} \; | sort | md5 -q)
CAT_OFFICE_PATCH="$PATCH" bash "$REPO/scripts/patch-cat-office.sh" "$broken" >/dev/null 2>&1; code=$?
after=$(cd "$broken" && find . -type f -not -path './.cat-office/*' -exec md5 -q {} \; | sort | md5 -q)
[ $code = 3 ] && [ "$before" = "$after" ] && ok "doesn't fit: exit 3, nothing changed" || bad "doesn't fit (got $code)"

# An older version (from a history folder, no git) is upgraded.
hist=$(mktemp -d); git -C "$REPO" log --format=%h -- patches/cat-office.patch | sed -n '2p' | while read -r rev; do
  git -C "$REPO" show "$rev:patches/cat-office.patch" > "$hist/01.patch"; done
if [ -s "$hist/01.patch" ] && ! cmp -s "$hist/01.patch" "$PATCH"; then
  old=$(mktemp -d); cp -R "$mini/." "$old/"; patch -d "$old" -p1 -R -s -f < "$PATCH"; patch -d "$old" -p1 -s -f < "$hist/01.patch" 2>/dev/null
  out=$(CAT_OFFICE_PATCH="$PATCH" CAT_OFFICE_PATCH_HISTORY="$hist" bash "$REPO/scripts/patch-cat-office.sh" "$old" 2>&1); code=$?
  [ $code = 0 ] && patch -d "$old" -p1 -R --dry-run -s -f < "$PATCH" >/dev/null 2>&1 && ok "upgrades an older patch from the history folder" || bad "upgrade ($code: $out)"
fi

# stop-cat-office.sh --check on a folder with nothing running.
out=$(bash "$REPO/scripts/stop-cat-office.sh" "$mini" --check); code=$?
[ $code = 0 ] && [[ "$out" == *"nothing running"* ]] && ok "stop --check with nothing running" || bad "stop --check ($code: $out)"

# Quiet status line: writes the snapshot, prints nothing.
home=$(mktemp -d)
json='{"session_id":"t1","workspace":{"current_dir":"/tmp"},"model":{"display_name":"Opus"},"context_window":{"used_percentage":12}}'
out=$(printf '%s' "$json" | HOME="$home" CLAUDE_BAR_DIR="$home/cb" CLAUDEBAR_STATUSLINE_QUIET=1 bash "$REPO/scripts/statusline-command.sh")
[ -z "$out" ] && [ -f "$home/cb/sessions/t1.json" ] && ok "quiet status line: data saved, nothing printed" || bad "quiet status line (out: $out)"
out=$(printf '%s' "$json" | HOME="$home" CLAUDE_BAR_DIR="$home/cb" bash "$REPO/scripts/statusline-command.sh")
[ -n "$out" ] && ok "normal status line still prints" || bad "normal status line"

rm -rf "$mini" "$notco" "$broken" "$hist" "${old:-/nonexistent}" "$home"
echo "$pass passed, $fail failed"; [ $fail = 0 ]
```

- [ ] **Step 2: Run it to verify it fails**

Run: `bash scripts/test-setup-scripts.sh ~/Documents/projects/cat-ai-office-with-art-20261006-1038`
Expected: FAIL lines for "not Cat Office exits 2", "doesn't fit: exit 3", "upgrades… from the history folder",
"stop --check" (no such script), and "quiet status line".

- [ ] **Step 3: Implement**
  - **`patch-cat-office.sh`:**
    - `PATCH="${CAT_OFFICE_PATCH:-$REPO/patches/cat-office.patch}"`
    - the "not a Cat Office folder" check becomes
      `[ -f "$DIR/package.json" ] && [ -d "$DIR/server/agent-bridge" ]`, with `exit 2`
    - both "doesn't apply" and "can't upgrade" exits become `exit 3`
    - the older-version search loops over `"$CAT_OFFICE_PATCH_HISTORY"/*.patch` (sorted with `ls -r`) when that
      variable is set, else over the git log as now
  - **`stop-cat-office.sh`:**
    - move the block from `move-cat-office.sh` that runs from `# This script and the shells above it are never stopped.`
      through the kill-and-wait loop
    - inputs: `FROM="$1"`, plus an optional `--check`
    - `--check` prints `Would stop:` and either the process lines or `  (nothing running)`, then exits 0
  - **`move-cat-office.sh`:**
    - its `--check` calls `bash "$REPO/scripts/stop-cat-office.sh" "$FROM" --check`, then prints the move line
    - otherwise it calls the script without `--check` before `mv`, and stops (nothing moved) if that fails
  - **`statusline-command.sh`:** right after the `fields=$(…)` python block, add:

```bash
# ClaudeBar's wrapper runs this quietly before the user's own status line: data saved, nothing printed.
[ "${CLAUDEBAR_STATUSLINE_QUIET:-}" = 1 ] && exit 0
```

- [ ] **Step 4: Run them to verify they pass**

Run: `bash scripts/test-setup-scripts.sh ~/Documents/projects/cat-ai-office-with-art-20261006-1038 && bash scripts/test-statusline.sh | grep -c '^PASS'`
Expected: `N passed, 0 failed`, and `8`.

- [ ] **Step 5: Commit** — `feat: setup scripts usable from the app (bundled patch history, stop script, quiet status line)`

---

### Task 2: Find Cat Office (Core)

**Files:**
- Create: `Sources/ClaudeBarCore/CatOfficeFinder.swift`
- Test: `Tests/ClaudeBarCoreTests/CatOfficeFinderTests.swift`

**Interfaces:**
- Produces:

```swift
public struct CatOfficeCandidate: Equatable, Sendable {
    public var path: String        // resolved absolute path (symlinks resolved)
    public var modified: Date      // its package.json's modification date
    public var running: Bool       // the running Cat Office (bridge.json named it)
}
public enum CatOfficeFinder {
    public static func isCatOffice(_ path: String) -> Bool
    public static func defaultRoots(home: String) -> [String]
    public static func search(roots: [String], depth: Int = 2) -> [String]
    public static func candidates(running: String?, saved: String?, roots: [String]) -> [CatOfficeCandidate]
}
```

- [ ] **Step 1: Write the failing tests**

```swift
import Foundation
import Testing
@testable import ClaudeBarCore

@Suite struct CatOfficeFinderTests {
    func makeCatOffice(_ dir: URL, modified: Date) throws {
        try FileManager.default.createDirectory(at: dir.appendingPathComponent("server/agent-bridge"), withIntermediateDirectories: true)
        let pkg = dir.appendingPathComponent("package.json")
        try Data("{}".utf8).write(to: pkg)
        try FileManager.default.setAttributes([.modificationDate: modified], ofItemAtPath: pkg.path)
    }

    @Test func recognisesOnlyCatOffice() throws {
        let root = makeTempDir()
        try makeCatOffice(root.appendingPathComponent("co"), modified: Date())
        try FileManager.default.createDirectory(at: root.appendingPathComponent("web/server"), withIntermediateDirectories: true)
        try Data("{}".utf8).write(to: root.appendingPathComponent("web/package.json"))
        #expect(CatOfficeFinder.isCatOffice(root.appendingPathComponent("co").path))
        #expect(!CatOfficeFinder.isCatOffice(root.appendingPathComponent("web").path), "a package.json alone isn't Cat Office")
    }

    @Test func searchesTwoLevelsDeep() throws {
        let root = makeTempDir()
        try makeCatOffice(root.appendingPathComponent("a/cat-office"), modified: Date())
        try makeCatOffice(root.appendingPathComponent("a/b/c/too-deep"), modified: Date())
        let found = CatOfficeFinder.search(roots: [root.path])
        #expect(found.map { URL(fileURLWithPath: $0).lastPathComponent } == ["cat-office"])
    }

    @Test func eachCopyOnceNewestFirst() throws {
        let root = makeTempDir()
        let old = root.appendingPathComponent("old-zip"), new = root.appendingPathComponent("new-zip")
        try makeCatOffice(old, modified: Date(timeIntervalSince1970: 1_700_000_000))
        try makeCatOffice(new, modified: Date(timeIntervalSince1970: 1_790_000_000))
        try makeCatOffice(new.appendingPathComponent("examples/copy"), modified: Date())   // inside another: not searched
        try FileManager.default.createSymbolicLink(at: root.appendingPathComponent("link"), withDestinationURL: new)
        let c = CatOfficeFinder.candidates(running: nil, saved: nil, roots: [root.path])
        #expect(c.map { URL(fileURLWithPath: $0.path).lastPathComponent } == ["new-zip", "old-zip"])
    }

    @Test func runningThenSavedThenSearched() throws {
        let root = makeTempDir()
        let a = root.appendingPathComponent("x/a"), b = root.appendingPathComponent("x/b"), r = root.appendingPathComponent("elsewhere/r")
        try makeCatOffice(a, modified: Date(timeIntervalSince1970: 1_790_000_000))
        try makeCatOffice(b, modified: Date(timeIntervalSince1970: 1_700_000_000))
        try makeCatOffice(r, modified: Date(timeIntervalSince1970: 1_600_000_000))
        let c = CatOfficeFinder.candidates(running: r.path, saved: b.path, roots: [root.appendingPathComponent("x").path])
        #expect(c.map { URL(fileURLWithPath: $0.path).lastPathComponent } == ["r", "b", "a"])
        #expect(c.first?.running == true && c.dropFirst().allSatisfy { !$0.running })
    }

    @Test func aStaleSavedFolderIsIgnored() throws {
        let root = makeTempDir()
        #expect(CatOfficeFinder.candidates(running: nil, saved: root.appendingPathComponent("gone").path, roots: [root.path]).isEmpty)
    }

    @Test func usualPlaces() {
        #expect(CatOfficeFinder.defaultRoots(home: "/Users/x") == ["/Users/x/Documents", "/Users/x/Documents/projects", "/Users/x/Downloads",
                                                                   "/Users/x/Desktop", "/Users/x/Developer", "/Users/x/Projects"])
    }
}
```

- [ ] **Step 2: Run them to verify they fail** — `swift test --filter CatOfficeFinderTests`. Expected:
  `cannot find 'CatOfficeFinder'`.
- [ ] **Step 3: Implement**

```swift
import Foundation

/// A Cat Office folder found on this Mac.
public struct CatOfficeCandidate: Equatable, Sendable {
    public var path: String
    public var modified: Date
    public var running: Bool

    public init(path: String, modified: Date, running: Bool) {
        self.path = path
        self.modified = modified
        self.running = running
    }
}

/// Finds Cat Office copies: the running one, the saved one, then the usual places (two levels deep).
public enum CatOfficeFinder {
    /// Cat Office: a package.json and its server/agent-bridge folder.
    public static func isCatOffice(_ path: String) -> Bool {
        var dir: ObjCBool = false
        return FileManager.default.fileExists(atPath: path + "/package.json")
            && FileManager.default.fileExists(atPath: path + "/server/agent-bridge", isDirectory: &dir) && dir.boolValue
    }

    public static func defaultRoots(home: String) -> [String] {
        ["Documents", "Documents/projects", "Downloads", "Desktop", "Developer", "Projects"].map { home + "/" + $0 }
    }

    /// Cat Office folders under `roots`, up to `depth` levels down; never inside one already found, never hidden or
    /// node_modules folders.
    public static func search(roots: [String], depth: Int = 2) -> [String] {
        var found: [String] = []
        func walk(_ dir: String, _ level: Int) {
            guard level <= depth, let names = try? FileManager.default.contentsOfDirectory(atPath: dir) else { return }
            for name in names.sorted() where !name.hasPrefix(".") && name != "node_modules" {
                let path = dir + "/" + name
                var isDir: ObjCBool = false
                guard FileManager.default.fileExists(atPath: path, isDirectory: &isDir), isDir.boolValue else { continue }
                if isCatOffice(path) { found.append(path) } else { walk(path, level + 1) }
            }
        }
        for root in roots { walk(root, 1) }
        return found
    }

    /// The running copy first, then the saved one, then the rest newest first; each real folder once.
    public static func candidates(running: String?, saved: String?, roots: [String]) -> [CatOfficeCandidate] {
        var seen = Set<String>()
        var out: [CatOfficeCandidate] = []
        func add(_ path: String, running: Bool) {
            let real = URL(fileURLWithPath: path).resolvingSymlinksInPath().path
            guard isCatOffice(real), seen.insert(real).inserted else { return }
            out.append(CatOfficeCandidate(path: real, modified: modified(real), running: running))
        }
        if let running { add(running, running: true) }
        if let saved { add(saved, running: false) }
        let head = out.count
        for path in search(roots: roots) { add(path, running: false) }
        out[head...].sort { $0.modified > $1.modified }
        return out
    }

    static func modified(_ path: String) -> Date {
        ((try? FileManager.default.attributesOfItem(atPath: path + "/package.json"))?[.modificationDate] as? Date) ?? .distantPast
    }
}
```

- [ ] **Step 4: Run them to verify they pass** — the full `swift test`.
- [ ] **Step 5: Commit** — `feat: find Cat Office copies (running, saved, usual places)`

---

### Task 3: The status line (Core)

**Files:**
- Create: `Sources/ClaudeBarCore/StatusLineSetup.swift`
- Test: `Tests/ClaudeBarCoreTests/StatusLineSetupTests.swift`

**Interfaces:**
- Produces:

```swift
public enum StatusLineState: Equatable, Sendable {
    case none                         // no statusLine setting
    case claudeBar                    // runs ClaudeBar's script (any version: it writes ~/.claude/claude-bar)
    case wrapped(original: String)    // ClaudeBar's wrapper around the user's own command
    case own(command: String)
    case unreadable                   // settings.json exists but doesn't parse
}
public struct StatusLineSetup: Sendable {
    public init(claudeDir: URL, script: String, now: @escaping @Sendable () -> Date = Date.init)
    public func state() -> StatusLineState
    public func useClaudeBar() throws     // .none or .own → ClaudeBar's script; backups; original recorded
    public func wrap() throws             // .own → ClaudeBar's wrapper; original recorded
    public func restore() throws          // back to the recorded original
    public var canRestore: Bool { get }
    public static let marker = "~/.claude/claude-bar"
}
```

- [ ] **Step 1: Write the failing tests**

```swift
import Foundation
import Testing
@testable import ClaudeBarCore

@Suite struct StatusLineSetupTests {
    let ours = try! String(contentsOfFile: #filePath.replacingOccurrences(of: "Tests/ClaudeBarCoreTests/StatusLineSetupTests.swift", with: "scripts/statusline-command.sh"), encoding: .utf8)

    func setup(_ settings: String?) throws -> (StatusLineSetup, URL) {
        let dir = makeTempDir()
        if let settings { try Data(settings.utf8).write(to: dir.appendingPathComponent("settings.json")) }
        return (StatusLineSetup(claudeDir: dir, script: ours, now: { Date(timeIntervalSince1970: 1_791_300_000) }), dir)
    }
    func settings(_ dir: URL) throws -> [String: Any] {
        try JSONSerialization.jsonObject(with: Data(contentsOf: dir.appendingPathComponent("settings.json"))) as! [String: Any]
    }

    @Test func noStatusLineGetsClaudeBars() throws {
        let (s, dir) = try setup(#"{"model":"opus"}"#)
        #expect(s.state() == .none)
        try s.useClaudeBar()
        #expect(s.state() == .claudeBar)
        let line = try settings(dir)["statusLine"] as? [String: String]
        #expect(line?["command"] == "bash ~/.claude/statusline-command.sh" && line?["type"] == "command")
        #expect(try String(contentsOf: dir.appendingPathComponent("statusline-command.sh"), encoding: .utf8) == ours)
    }

    @Test func noSettingsFileAtAll() throws {
        let (s, _) = try setup(nil)
        #expect(s.state() == .none)
        try s.useClaudeBar()
        #expect(s.state() == .claudeBar)
    }

    @Test func otherSettingsSurvive() throws {
        let (s, dir) = try setup(#"{"model":"opus","permissions":{"allow":["Bash(ls:*)"]},"env":{"A":"1"}}"#)
        try s.useClaudeBar()
        let d = try settings(dir)
        #expect(d["model"] as? String == "opus" && (d["env"] as? [String: String])?["A"] == "1")
        #expect(((d["permissions"] as? [String: Any])?["allow"] as? [String]) == ["Bash(ls:*)"])
        let backups = try FileManager.default.contentsOfDirectory(atPath: dir.path).filter { $0.hasPrefix("settings.json.claude-bar-backup-") }
        #expect(backups.count == 1, "settings.json backed up before the change")
    }

    @Test func aBrokenSettingsFileIsLeftAlone() throws {
        let (s, dir) = try setup("{ not json")
        #expect(s.state() == .unreadable)
        #expect(throws: (any Error).self) { try s.useClaudeBar() }
        #expect(try String(contentsOf: dir.appendingPathComponent("settings.json"), encoding: .utf8) == "{ not json")
    }

    @Test func anOlderClaudeBarScriptIsStillClaudeBars() throws {
        let (s, dir) = try setup(#"{"statusLine":{"type":"command","command":"bash ~/.claude/statusline-command.sh"}}"#)
        try Data("#!/bin/bash\n# older ClaudeBar\n# writes ~/.claude/claude-bar/sessions\n".utf8).write(to: dir.appendingPathComponent("statusline-command.sh"))
        #expect(s.state() == .claudeBar)
    }

    @Test func theirOwnIsDetected() throws {
        let (s, _) = try setup(#"{"statusLine":{"type":"command","command":"npx ccstatusline"}}"#)
        #expect(s.state() == .own(command: "npx ccstatusline"))
    }

    @Test func wrappingKeepsTheirOutputExactly() throws {
        let theirs = #"echo "it's $(echo 'mine') | ok" | tr a-z A-Z"#
        let (s, dir) = try setup(#"{"statusLine":{"type":"command","command":"# placeholder"}}"#)
        var d = try settings(dir); d["statusLine"] = ["type": "command", "command": theirs]
        try JSONSerialization.data(withJSONObject: d).write(to: dir.appendingPathComponent("settings.json"))
        try s.wrap()
        #expect(s.state() == .wrapped(original: theirs))
        // Run the wrapper as Claude Code would: their output, byte for byte; ClaudeBar's data saved quietly.
        let home = dir.deletingLastPathComponent()
        let wrapper = dir.appendingPathComponent(StatusLineSetup.wrapperName).path
        let p = Process(); p.executableURL = URL(fileURLWithPath: "/bin/bash"); p.arguments = [wrapper]
        p.environment = ["HOME": home.path, "PATH": "/usr/bin:/bin", "CLAUDE_BAR_DIR": home.appendingPathComponent("cb").path,
                         "CLAUDEBAR_HOOK": dir.appendingPathComponent(StatusLineSetup.hookName).path]
        let input = Pipe(), output = Pipe(); p.standardInput = input; p.standardOutput = output
        try p.run(); input.fileHandleForWriting.write(Data(#"{"session_id":"w1","model":{"display_name":"Opus"}}"#.utf8)); try input.fileHandleForWriting.close()
        p.waitUntilExit()
        let printed = String(data: output.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)
        #expect(printed == "IT'S MINE | OK\n")
        #expect(FileManager.default.fileExists(atPath: home.appendingPathComponent("cb/sessions/w1.json").path))
    }

    @Test func switchingToClaudeBarsCanBeRestored() throws {
        let (s, dir) = try setup(#"{"statusLine":{"type":"command","command":"bash ~/.claude/statusline-command.sh"}}"#)
        try Data("#!/bin/bash\necho theirs\n".utf8).write(to: dir.appendingPathComponent("statusline-command.sh"))
        #expect(s.state() == .own(command: "bash ~/.claude/statusline-command.sh"))
        try s.useClaudeBar()
        #expect(s.state() == .claudeBar && s.canRestore)
        try s.restore()
        #expect(s.state() == .own(command: "bash ~/.claude/statusline-command.sh"))
        #expect(try String(contentsOf: dir.appendingPathComponent("statusline-command.sh"), encoding: .utf8) == "#!/bin/bash\necho theirs\n")
    }

    @Test func restoringAWrapPutsTheirCommandBack() throws {
        let (s, _) = try setup(#"{"statusLine":{"type":"command","command":"npx ccstatusline"}}"#)
        try s.wrap(); try s.restore()
        #expect(s.state() == .own(command: "npx ccstatusline") && !s.canRestore)
    }
}
```

- [ ] **Step 2: Run them to verify they fail** — Expected: `cannot find 'StatusLineSetup'`.
- [ ] **Step 3: Implement**

```swift
import Foundation

public enum StatusLineState: Equatable, Sendable {
    case none
    case claudeBar
    case wrapped(original: String)
    case own(command: String)
    case unreadable
}

public struct StatusLineError: Error, Equatable { public let message: String }

/// Claude Code's status line (~/.claude/settings.json "statusLine") as ClaudeBar sets it up: install ClaudeBar's script,
/// or wrap the user's own command so ClaudeBar's data is saved quietly and their output is unchanged; every change
/// backed up and restorable.
public struct StatusLineSetup: Sendable {
    public static let scriptName = "statusline-command.sh"
    public static let hookName = "claude-bar-hook.sh"
    public static let wrapperName = "claude-bar-statusline.sh"
    public static let originalName = "claude-bar-statusline-original.json"
    /// Every ClaudeBar status line script (any version) writes here.
    public static let marker = "~/.claude/claude-bar"
    static let claudeBarCommand = "bash ~/.claude/statusline-command.sh"

    let claudeDir: URL
    let script: String
    let now: @Sendable () -> Date

    public init(claudeDir: URL, script: String, now: @escaping @Sendable () -> Date = Date.init) {
        self.claudeDir = claudeDir
        self.script = script
        self.now = now
    }

    var settingsFile: URL { claudeDir.appendingPathComponent("settings.json") }
    func file(_ name: String) -> URL { claudeDir.appendingPathComponent(name) }
    var stamp: String {
        let f = DateFormatter(); f.dateFormat = "yyyyMMdd-HHmmss"; f.timeZone = TimeZone(identifier: "UTC")
        return f.string(from: now())
    }

    func readSettings() throws -> [String: Any] {
        guard let data = try? Data(contentsOf: settingsFile) else { return [:] }
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw StatusLineError(message: "~/.claude/settings.json isn't valid JSON")
        }
        return object
    }

    func command(in settings: [String: Any]) -> String? {
        (settings["statusLine"] as? [String: Any])?["command"] as? String
    }

    struct Original: Codable { var command: String?; var scriptBackup: String? }

    func readOriginal() -> Original? {
        (try? Data(contentsOf: file(Self.originalName))).flatMap { try? JSONDecoder().decode(Original.self, from: $0) }
    }

    public var canRestore: Bool { readOriginal() != nil }

    public func state() -> StatusLineState {
        guard let settings = try? readSettings() else { return .unreadable }
        guard let command = command(in: settings), !command.trimmingCharacters(in: .whitespaces).isEmpty else { return .none }
        if command.contains(Self.wrapperName), let original = readOriginal()?.command { return .wrapped(original: original) }
        if command.contains(Self.scriptName),
           let text = try? String(contentsOf: file(Self.scriptName), encoding: .utf8), text.contains(Self.marker) {
            return .claudeBar
        }
        return .own(command: command)
    }

    func writeSettings(_ settings: [String: Any]) throws {
        if FileManager.default.fileExists(atPath: settingsFile.path) {
            try FileManager.default.copyItem(at: settingsFile, to: file("settings.json.claude-bar-backup-\(stamp)"))
        }
        try FileManager.default.createDirectory(at: claudeDir, withIntermediateDirectories: true)
        let data = try JSONSerialization.data(withJSONObject: settings, options: [.prettyPrinted, .sortedKeys])
        try data.write(to: settingsFile, options: .atomic)
    }

    func setCommand(_ command: String?, in settings: [String: Any]) -> [String: Any] {
        var s = settings
        if let command { s["statusLine"] = ["type": "command", "command": command] } else { s.removeValue(forKey: "statusLine") }
        return s
    }

    func recordOriginal(_ original: Original) throws {
        try JSONEncoder().encode(original).write(to: file(Self.originalName), options: .atomic)
    }

    /// ClaudeBar's status line. The user's previous command and script (if any) are recorded and backed up first.
    public func useClaudeBar() throws {
        let settings = try readSettings()
        let previous = command(in: settings)
        var backup: String?
        let scriptFile = file(Self.scriptName)
        if let existing = try? String(contentsOf: scriptFile, encoding: .utf8), existing != script {
            let name = "\(Self.scriptName).claude-bar-backup-\(stamp)"
            try FileManager.default.copyItem(at: scriptFile, to: file(name))
            backup = name
        }
        if readOriginal() == nil, previous != nil || backup != nil { try recordOriginal(Original(command: previous, scriptBackup: backup)) }
        try FileManager.default.createDirectory(at: claudeDir, withIntermediateDirectories: true)
        try Data(script.utf8).write(to: scriptFile, options: .atomic)
        try writeSettings(setCommand(Self.claudeBarCommand, in: settings))
    }

    /// Keeps the user's own status line: ClaudeBar's hook saves its data quietly, then their command runs unchanged.
    public func wrap() throws {
        let settings = try readSettings()
        guard let theirs = command(in: settings) else { throw StatusLineError(message: "There is no status line to keep") }
        try Data(script.utf8).write(to: file(Self.hookName), options: .atomic)
        let quoted = "'" + theirs.replacingOccurrences(of: "'", with: "'\\''") + "'"
        let wrapper = """
        #!/bin/bash
        # ClaudeBar: saves ClaudeBar's data (quietly), then runs your own status line, unchanged.
        input=$(cat)
        printf '%s' "$input" | CLAUDEBAR_STATUSLINE_QUIET=1 bash "${CLAUDEBAR_HOOK:-$HOME/.claude/\(Self.hookName)}" >/dev/null 2>&1
        printf '%s' "$input" | /bin/bash -c \(quoted)

        """
        try Data(wrapper.utf8).write(to: file(Self.wrapperName), options: .atomic)
        try recordOriginal(Original(command: theirs, scriptBackup: nil))
        try writeSettings(setCommand("bash ~/.claude/\(Self.wrapperName)", in: settings))
    }

    /// Back to what the user had before ClaudeBar changed it.
    public func restore() throws {
        guard let original = readOriginal() else { return }
        if let backup = original.scriptBackup {
            let scriptFile = file(Self.scriptName)
            try? FileManager.default.removeItem(at: scriptFile)
            try FileManager.default.copyItem(at: file(backup), to: scriptFile)
        }
        try writeSettings(setCommand(original.command, in: try readSettings()))
        try FileManager.default.removeItem(at: file(Self.originalName))
    }
}
```

Note: `restore` replaces only ClaudeBar's own copy of the script (the backup holds the user's). Nothing of the user's is
ever deleted: the backup files stay.

- [ ] **Step 4: Run them to verify they pass** — the full `swift test`.
- [ ] **Step 5: Commit** — `feat: status line setup — install, wrap, restore (backups, other settings kept)`

---

### Task 4: Setup state, and existing setups (Core)

**Files:**
- Create: `Sources/ClaudeBarCore/SetupSettings.swift`
- Modify: `Sources/ClaudeBarCore/Config.swift` (parse `setup`)
- Test: `Tests/ClaudeBarCoreTests/SetupSettingsTests.swift`

**Interfaces:**
- Produces:

```swift
public enum SetupState: String, Sendable { case full, reduced, noCatOffice }
public struct SetupSettings: Equatable, Sendable {
    public var seen: Bool          // the window was shown (finished or skipped): never open it by itself again
    public var state: SetupState?
    public init(seen: Bool = false, state: SetupState? = nil)
    /// An existing working setup (from before onboarding existed): treat it as done.
    public static func inferred(catOfficeDir: String?, bridgeDir: String?, statusLine: StatusLineState) -> SetupSettings?
    /// The window opens by itself only when nothing was ever seen and nothing can be inferred.
    public static func opensByItself(_ s: SetupSettings, inferred: SetupSettings?) -> Bool
}
// Config gains: public var setup = SetupSettings()   (projects.json: "setup": {"seen": true, "state": "full"})
```

- [ ] **Step 1: Write the failing tests**

```swift
import Foundation
import Testing
@testable import ClaudeBarCore

@Suite struct SetupSettingsTests {
    @Test func parsesAndDefaults() throws {
        #expect(try Config.parse(Data(#"{"projects":[]}"#.utf8)).setup == SetupSettings())
        let c = try Config.parse(Data(#"{"projects":[],"setup":{"seen":true,"state":"reduced"}}"#.utf8))
        #expect(c.setup == SetupSettings(seen: true, state: .reduced))
    }

    @Test func anExistingSetupIsNotAskedAgain() {
        // The user's own Mac: patched Cat Office (bridge.json names its folder) and ClaudeBar's status line.
        let s = SetupSettings.inferred(catOfficeDir: nil, bridgeDir: "/Users/x/co", statusLine: .claudeBar)
        #expect(s == SetupSettings(seen: true, state: .full))
        #expect(!SetupSettings.opensByItself(SetupSettings(), inferred: s))
    }

    @Test func aFolderWithoutTheBridgeIsReduced() {
        #expect(SetupSettings.inferred(catOfficeDir: "/Users/x/co", bridgeDir: nil, statusLine: .wrapped(original: "x"))
                == SetupSettings(seen: true, state: .reduced))
    }

    @Test func aNewMacOpensTheWindow() {
        #expect(SetupSettings.inferred(catOfficeDir: nil, bridgeDir: nil, statusLine: .none) == nil)
        #expect(SetupSettings.opensByItself(SetupSettings(), inferred: nil))
    }

    @Test func skippedStaysClosed() {
        #expect(!SetupSettings.opensByItself(SetupSettings(seen: true, state: nil), inferred: nil))
    }
}
```

- [ ] **Step 2: Run them to verify they fail**
- [ ] **Step 3: Implement**

```swift
import Foundation

public enum SetupState: String, Sendable { case full, reduced, noCatOffice }

/// Onboarding: whether the setup window was shown, and how far setup got. In projects.json under "setup".
public struct SetupSettings: Equatable, Sendable {
    public var seen: Bool
    public var state: SetupState?

    public init(seen: Bool = false, state: SetupState? = nil) {
        self.seen = seen
        self.state = state
    }

    public static func inferred(catOfficeDir: String?, bridgeDir: String?, statusLine: StatusLineState) -> SetupSettings? {
        let usage: Bool = switch statusLine { case .claudeBar, .wrapped: true; default: false }
        guard usage, catOfficeDir != nil || bridgeDir != nil else { return nil }
        // Only a patched Cat Office writes bridge.json with its folder.
        return SetupSettings(seen: true, state: bridgeDir != nil ? .full : .reduced)
    }

    public static func opensByItself(_ s: SetupSettings, inferred: SetupSettings?) -> Bool {
        !s.seen && inferred == nil
    }
}
```

In `Config`, add `public var setup = SetupSettings()` and, in `parse`:

```swift
        if let s = root["setup"] as? [String: Any] {
            if let v = s["seen"] as? Bool { config.setup.seen = v }
            if let v = (s["state"] as? String).flatMap(SetupState.init(rawValue:)) { config.setup.state = v }
        }
```

- [ ] **Step 4: Run them to verify they pass** — the full `swift test`.
- [ ] **Step 5: Commit** — `feat: setup state in the config; existing setups count as done`

---

### Task 5: Bundling and the actions behind each step (app)

**Files:**
- Modify: `scripts/build.sh`
- Modify: `Sources/ClaudeBarCore/CatOfficeLauncher.swift` (make `nodeBinDir` public, add `hasNode`)
- Create: `Sources/ClaudeBar/Setup/SetupActions.swift`
- Modify: `Sources/ClaudeBar/AppState.swift` (`setSetup(_:)`, `inferSetupIfNeeded()`)

**Interfaces:**
- Produces:

```swift
/// Where setup reads and writes: the real Mac, or temp folders for the click test.
struct SetupEnvironment: Sendable {
    var home: URL                 // roots are searched under it
    var claudeDir: URL            // ~/.claude
    var resources: URL            // the bundled Setup folder
    var bridgeFile: URL
    static var real: SetupEnvironment { get }
}
enum PatchOutcome: Equatable { case patched, alreadyPatched, notCatOffice, doesNotFit(String), failed(String) }
@MainActor enum SetupActions {
    static func patch(_ dir: String, env: SetupEnvironment) async -> PatchOutcome
    static func restartCatOffice(_ dir: String, env: SetupEnvironment, settings: CatOfficeSettings) async -> CatOfficeLauncher.Result
    static func statusLine(env: SetupEnvironment) -> StatusLineSetup
    static func hasNode() -> Bool
    static func runningDir(env: SetupEnvironment) -> String?
}
// AppState: func setSetup(_ s: SetupSettings), func setCatOfficeDir(_ dir: String?)
```

- [ ] **Step 1: build.sh bundles `Setup/`**

```bash
# Onboarding: the patch, its older versions (for upgrades, no git needed in the app), and the scripts.
SETUP="$APP/Contents/Resources/Setup"
mkdir -p "$SETUP/patch-history"
cp patches/cat-office.patch scripts/patch-cat-office.sh scripts/stop-cat-office.sh scripts/statusline-command.sh "$SETUP/"
i=0
for rev in $(git log --reverse --format=%h -- patches/cat-office.patch 2>/dev/null); do
  i=$((i+1)); git show "$rev:patches/cat-office.patch" > "$SETUP/patch-history/$(printf '%02d' $i).patch"
done
```

- [ ] **Step 2: Implement `SetupActions`**

```swift
import ClaudeBarCore
import Foundation

struct SetupEnvironment: Sendable {
    var home: URL
    var claudeDir: URL
    var resources: URL
    var bridgeFile: URL

    static var real: SetupEnvironment {
        let home = Paths.home
        return SetupEnvironment(home: home, claudeDir: home.appendingPathComponent(".claude"),
                                resources: Bundle.main.resourceURL!.appendingPathComponent("Setup"),
                                bridgeFile: CatOfficeFeed.bridgeFile)
    }
}

enum PatchOutcome: Equatable {
    case patched, alreadyPatched, notCatOffice
    case doesNotFit(String)
    case failed(String)
}

/// What each setup step does on disk: run the bundled scripts and Cat Office's launcher.
@MainActor
enum SetupActions {
    static func patch(_ dir: String, env: SetupEnvironment) async -> PatchOutcome {
        let script = env.resources.appendingPathComponent("patch-cat-office.sh").path
        let result = await run("/bin/bash", [script, dir], env: [
            "CAT_OFFICE_PATCH": env.resources.appendingPathComponent("cat-office.patch").path,
            "CAT_OFFICE_PATCH_HISTORY": env.resources.appendingPathComponent("patch-history").path,
        ])
        switch result.code {
        case 0: return result.output.hasPrefix("Already patched") ? .alreadyPatched : .patched
        case 2: return .notCatOffice
        case 3: return .doesNotFit(result.output)
        default: return .failed(result.output)
        }
    }

    /// Stops this folder's Cat Office dev server (only its own node/npm processes), then starts it again.
    static func restartCatOffice(_ dir: String, env: SetupEnvironment, settings: CatOfficeSettings) async -> CatOfficeLauncher.Result {
        let stop = await run("/bin/bash", [env.resources.appendingPathComponent("stop-cat-office.sh").path, dir], env: [:])
        guard stop.code == 0 else { return .failed(stop.output) }
        var s = settings; s.dir = dir
        return await CatOfficeLauncher().start(settings: s)
    }

    static func statusLine(env: SetupEnvironment) -> StatusLineSetup {
        let script = (try? String(contentsOf: env.resources.appendingPathComponent("statusline-command.sh"), encoding: .utf8)) ?? ""
        return StatusLineSetup(claudeDir: env.claudeDir, script: script)
    }

    static func hasNode() -> Bool { CatOfficeLauncher.hasNode(home: NSHomeDirectory()) }

    static func runningDir(env: SetupEnvironment) -> String? {
        CatOfficeFeed.bridgeInfo(file: env.bridgeFile, isAlive: { kill($0, 0) == 0 })?.dir
    }

    struct Output { var code: Int32; var output: String }

    static func run(_ tool: String, _ args: [String], env extra: [String: String]) async -> Output {
        await Task.detached {
            let p = Process()
            p.executableURL = URL(fileURLWithPath: tool)
            p.arguments = args
            p.environment = ProcessInfo.processInfo.environment.merging(extra) { $1 }
            let pipe = Pipe(); p.standardOutput = pipe; p.standardError = pipe
            do { try p.run() } catch { return Output(code: -1, output: error.localizedDescription) }
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            p.waitUntilExit()
            return Output(code: p.terminationStatus, output: String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines))
        }.value
    }
}
```

In `CatOfficeLauncher`, add:

```swift
    /// Node.js (with npm) is installed where ClaudeBar can start Cat Office with it.
    public static func hasNode(home: String) -> Bool { nodeBinDir(home: home) != nil }
```

In `AppState`, add:

```swift
    func setSetup(_ s: SetupSettings) {
        do {
            try config.set(s.seen, at: ["setup", "seen"])
            if let state = s.state { try config.set(state.rawValue, at: ["setup", "state"]) }
        } catch let e as ConfigError { configError = e.message } catch {}
        settings = config.config
    }

    func setCatOfficeDir(_ dir: String) {
        do { try config.set(dir, at: ["catOffice", "dir"]) } catch let e as ConfigError { configError = e.message } catch {}
        settings = config.config
    }

    /// From before onboarding existed: a working setup counts as done, so its window doesn't open by itself.
    func inferSetupIfNeeded(env: SetupEnvironment = .real) -> Bool {
        guard !settings.setup.seen else { return false }
        let inferred = SetupSettings.inferred(catOfficeDir: settings.catOffice.dir, bridgeDir: SetupActions.runningDir(env: env),
                                              statusLine: SetupActions.statusLine(env: env).state())
        if let inferred { setSetup(inferred) }
        return SetupSettings.opensByItself(settings.setup, inferred: inferred)
    }
```

- [ ] **Step 3: Verify** — run `bash scripts/build.sh && ls build/ClaudeBar.app/Contents/Resources/Setup build/ClaudeBar.app/Contents/Resources/Setup/patch-history && swift test 2>&1 | tail -1`.
  Expected:
  - the four files are in `Setup/`
  - `patch-history/` holds `01.patch`…`05.patch`
  - all tests pass
- [ ] **Step 4: Commit** — `feat: bundle the setup scripts and patch history; setup actions`

---

### Task 6: The setup window

**Files:**
- Create: `Sources/ClaudeBar/Setup/SetupModel.swift`, `SetupView.swift`, `SetupWindow.swift`
- Modify: `Sources/ClaudeBar/StatusItemController.swift` (open on first launch)
- Modify: `Sources/ClaudeBar/RenderPeek.swift` (`--render-setup <step> <out.png>`)

**Interfaces:**
- Consumes: Tasks 2–5
- Produces:

```swift
@MainActor final class SetupModel: ObservableObject {
    enum Step: Int, CaseIterable { case welcome, find, connect, done }
    @Published var step: Step
    @Published var candidates: [CatOfficeCandidate]
    @Published var chosen: String?             // nil: "I don't use Cat Office"
    @Published var patch = true, usage = true, start = true
    @Published var keepOwnStatusLine = true    // the question when the user has their own
    @Published var results: [String: StepResult]   // "patch", "usage", "start" → ✓ / ✗ with a line
    @Published var statusLine: StatusLineState
    init(state: AppState, env: SetupEnvironment)
    func find()                                 // fills candidates, picks the first
    func choose(_ path: String) -> Bool         // false: "That folder isn't Cat Office"
    func connect() async                        // runs the ticked steps; then step = .done
    func skip()                                 // seen = true; closes
    var summary: [(ok: Bool, text: String)]     // Done's checklist
}
struct StepResult: Equatable { var ok: Bool; var text: String }
@MainActor final class SetupWindow { static let shared: SetupWindow; func open(state: AppState, env: SetupEnvironment = .real) }
```

- [ ] **Step 1: `SetupModel`**

```swift
import AppKit
import ClaudeBarCore

struct StepResult: Equatable { var ok: Bool; var text: String }

@MainActor
final class SetupModel: ObservableObject {
    enum Step: Int, CaseIterable { case welcome, find, connect, done }

    @Published var step: Step = .welcome
    @Published var candidates: [CatOfficeCandidate] = []
    @Published var chosen: String?
    @Published var choiceError: String?
    @Published var patch = true
    @Published var usage = true
    @Published var start = true
    @Published var keepOwnStatusLine = true
    @Published var working = false
    @Published var results: [String: StepResult] = [:]
    @Published private(set) var statusLine: StatusLineState = .none

    let state: AppState
    let env: SetupEnvironment
    var onClose: (() -> Void)?

    init(state: AppState, env: SetupEnvironment) {
        self.state = state
        self.env = env
        statusLine = SetupActions.statusLine(env: env).state()
    }

    var running: Bool { candidates.first?.running == true && candidates.first?.path == chosen }

    func find() {
        candidates = CatOfficeFinder.candidates(running: SetupActions.runningDir(env: env), saved: state.settings.catOffice.dir,
                                                roots: CatOfficeFinder.defaultRoots(home: env.home.path))
        chosen = candidates.first?.path
        step = .find
    }

    func choose(_ path: String) -> Bool {
        let real = URL(fileURLWithPath: path).resolvingSymlinksInPath().path
        guard CatOfficeFinder.isCatOffice(real) else { choiceError = "That folder isn't Cat Office."; return false }
        choiceError = nil
        if !candidates.contains(where: { $0.path == real }) {
            candidates.insert(CatOfficeCandidate(path: real, modified: Date(), running: false), at: 0)
        }
        chosen = real
        return true
    }

    func useNoCatOffice() {
        chosen = nil
        patch = false; start = false
        step = .connect
    }

    func connect() async {
        working = true
        defer { working = false }
        results = [:]
        var patched: Bool? = nil
        if let dir = chosen {
            state.setCatOfficeDir(dir)
            if patch {
                switch await SetupActions.patch(dir, env: env) {
                case .patched: results["patch"] = StepResult(ok: true, text: "Patched (a backup of the changed files is in .cat-office/)."); patched = true
                case .alreadyPatched: results["patch"] = StepResult(ok: true, text: "Already patched."); patched = true
                case .notCatOffice: results["patch"] = StepResult(ok: false, text: "That folder isn't Cat Office.")
                case .doesNotFit: results["patch"] = StepResult(ok: false, text: "Your Cat Office version isn't supported for the extras. Nothing was changed."); patched = false
                case .failed(let why): results["patch"] = StepResult(ok: false, text: "The patch didn't run: \(why)")
                }
            }
        }
        if usage {
            let line = SetupActions.statusLine(env: env)
            do {
                switch line.state() {
                case .claudeBar: results["usage"] = StepResult(ok: true, text: "ClaudeBar's status line is already set up.")
                case .none: try line.useClaudeBar(); results["usage"] = StepResult(ok: true, text: "ClaudeBar's status line is on.")
                case .own, .wrapped:
                    if keepOwnStatusLine { if case .own = line.state() { try line.wrap() }
                        results["usage"] = StepResult(ok: true, text: "Your status line is kept; ClaudeBar reads its data quietly.")
                    } else { try line.useClaudeBar(); results["usage"] = StepResult(ok: true, text: "ClaudeBar's status line is on (yours is backed up).") }
                case .unreadable:
                    results["usage"] = StepResult(ok: false, text: "~/.claude/settings.json isn't valid JSON, so it was left alone. See the guide to add the status line by hand.")
                }
            } catch {
                results["usage"] = StepResult(ok: false, text: (error as? StatusLineError)?.message ?? error.localizedDescription)
            }
            statusLine = line.state()
        }
        if start, let dir = chosen {
            if !SetupActions.hasNode() {
                results["start"] = StepResult(ok: false, text: "Cat Office needs Node.js. Install it from nodejs.org, then start Cat Office.")
            } else {
                var s = state.settings.catOffice; s.dir = dir
                switch await CatOfficeLauncher().start(settings: s) {
                case .started: results["start"] = StepResult(ok: true, text: "Cat Office is starting.")
                case .alreadyRunning: results["start"] = StepResult(ok: true, text: patched == true ? "Cat Office is running: restart it to load the patch." : "Cat Office is running.")
                case .notConfigured, .npmNotFound: results["start"] = StepResult(ok: false, text: "Cat Office needs Node.js. Install it from nodejs.org.")
                case .failed(let why): results["start"] = StepResult(ok: false, text: "Cat Office didn't start: \(why)")
                }
            }
        }
        let setupState: SetupState = chosen == nil ? .noCatOffice : (patched == true ? .full : .reduced)
        state.setSetup(SetupSettings(seen: true, state: setupState))
        step = .done
    }

    func restart() async {
        guard let dir = chosen else { return }
        working = true
        defer { working = false }
        let r = await SetupActions.restartCatOffice(dir, env: env, settings: state.settings.catOffice)
        results["start"] = StepResult(ok: r == .started || r == .alreadyRunning, text: r == .started ? "Cat Office restarted." : "Cat Office didn't restart.")
    }

    func skip() {
        state.setSetup(SetupSettings(seen: true, state: state.settings.setup.state))
        onClose?()
    }

    var summary: [(ok: Bool, text: String)] {
        ["patch", "usage", "start"].compactMap { results[$0] }.map { ($0.ok, $0.text) }
    }
}
```

- [ ] **Step 2: `SetupView`.** Four steps with a progress bar, `Back` / `Continue`, and `Skip for now`:
  - **Welcome:** a cat, the title, the one-line description, **Set up** and **Skip for now**.
  - **Find:**
    - one candidate: the green "✓ Found your Cat Office" box with its name and folder, and the
      **Not this one? Choose folder…** link (`NSOpenPanel`, folders only; an error shows the `choiceError` line)
    - several: a radio list, newest first, each with its folder and "running" when it is
    - none: the text "ClaudeBar couldn't find Cat Office.", **Choose folder…** and **I don't use Cat Office**
  - **Connect:**
    - three `Toggle`s (checkbox style), each with its one line from the spec
    - when the status line is `.own`, two radio choices under Usage: **Keep your status line** (default) and
      **Use ClaudeBar's status line**
    - **Start Cat Office now** shown only when it isn't running
    - **Continue** runs `connect()` with a spinner while `working`
  - **Done:**
    - the checklist (✓ green / ✗ amber, with each line)
    - "Usage appears after your next message in Claude Code."
    - a **Restart Cat Office** button when `results["start"]` says it's running and the patch changed something. Its
      help text and the line under it read: "This stops Cat Office's dev server and ends any Claude sessions running
      inside Cat Office."
    - **Open the office** (closes the window and opens the dropdown) and the **Full guide ↗** link

  Size: 460×420. Each control gets a stable `accessibilityIdentifier` (`setup-setup`, `setup-skip`,
  `setup-continue`, `setup-back`, `setup-open-office`), and `.onGeometryChange` records its frame into
  `SetupTargets.frames[id]`, the same pattern as `FloorSelection.targets`.

- [ ] **Step 3: `SetupWindow`**

```swift
import AppKit
import SwiftUI

/// The onboarding window: opens by itself on first launch, and from the Office card and Settings.
@MainActor
final class SetupWindow {
    static let shared = SetupWindow()
    private var window: NSWindow?

    func open(state: AppState, env: SetupEnvironment = .real) {
        if let window { window.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true); return }
        let model = SetupModel(state: state, env: env)
        let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 460, height: 420), styleMask: [.titled, .closable], backing: .buffered, defer: false)
        w.title = "Set up ClaudeBar"
        w.isReleasedWhenClosed = false
        w.contentView = NSHostingView(rootView: SetupView(model: model).environmentObject(state))
        w.center()
        model.onClose = { [weak self] in self?.window?.close() }
        NotificationCenter.default.addObserver(forName: NSWindow.willCloseNotification, object: w, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                // Closing with the red button counts as skipping.
                if !state.settings.setup.seen { state.setSetup(SetupSettings(seen: true, state: nil)) }
                self?.window = nil
            }
        }
        window = w
        w.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}
```

In `StatusItemController.init`, after the menu bar item is set up:

```swift
        // Onboarding: the setup window opens by itself once (not for a setup that already works).
        if state.sideEffects, state.inferSetupIfNeeded() {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) { SetupWindow.shared.open(state: state) }
        }
```

(`sideEffects` becomes `internal` if it is private.)

- [ ] **Step 4: Renders.** Add `--render-setup <welcome|find|connect|done> <out.png>`:
  - It renders `SetupView` with a `SetupModel` over a temp `SetupEnvironment`, whose home holds one fake Cat Office
    under `Documents/projects/cat-office` and whose claude folder holds a settings file with `"statusLine"` set to
    `npx ccstatusline`.
  - It sets `model.step` and, for `done`, fills `results` with one ✓ and one ✗.

  Run it for all four steps and open each image. Expected:
  - every step matches the spec's wording
  - the Connect step shows the "Keep your status line" choice
  - Done shows the checklist

- [ ] **Step 5: Commit** — `feat: onboarding window (welcome, find, connect, done)`

---

### Task 7: The entry points, the click test, docs

**Files:**
- Modify: `Sources/ClaudeBar/Views/DropdownView.swift` (Office card in `OfficeTabView`, the Settings row)
- Modify: `Sources/ClaudeBar/RenderPeek.swift` (`--test-setup`)
- Modify: `README.md`, `Resources/Help/guide.html`, `Sources/ClaudeBar/Views/HelpPanel.swift`

- [ ] **Step 1: The Office card.** In `OfficeTabView`, above `FloorPicker()`:

```swift
            if state.settings.setup.state != .full {
                SetupCard(reduced: state.settings.setup.state == .reduced) { SetupWindow.shared.open(state: state) }
            }
```

```swift
/// "Cat Office isn't set up yet · Set up…" (or, reduced: "Some extras are off · Fix…").
struct SetupCard: View {
    let reduced: Bool
    let open: () -> Void
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: reduced ? "exclamationmark.circle" : "pawprint").foregroundStyle(reduced ? Theme.waiting : .secondary)
            Text(reduced ? "Some extras are off" : "Cat Office isn't set up yet").font(.callout)
            Spacer()
            Button(reduced ? "Fix…" : "Set up…", action: open).buttonStyle(.link)
        }
        .padding(.horizontal, 10).padding(.vertical, 6)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(0.05)))
    }
}
```

  A user who is already set up (state `.full`, or inferred) sees no card.

- [ ] **Step 2: The Settings row.** In `SettingsTabView`, above the Sounds section:

```swift
            HStack {
                VStack(alignment: .leading, spacing: 1) {
                    Text("Setup").font(.callout)
                    Text(setupLine).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                }
                Spacer()
                Button("Set up ClaudeBar…") { SetupWindow.shared.open(state: state) }.buttonStyle(.link).font(.caption)
            }
            if SetupActions.statusLine(env: .real).canRestore {
                Button("Restore my old status line") { try? SetupActions.statusLine(env: .real).restore() }.buttonStyle(.link).font(.caption)
            }
```

  `setupLine` reads: "Full · Cat Office at ~/…", "Some extras are off · Cat Office at ~/…", or "Cat Office isn't set
  up". The folder is shortened with `~`.

- [ ] **Step 3: The click test (temp folders only).** `--test-setup`:
  1. Builds a temp `SetupEnvironment`. Its home holds a mini Cat Office: a `package.json`, a `server/agent-bridge/`
     folder, and no real files to patch. Its claude folder is empty.
  2. Opens `SetupWindow` with it, offscreen.
  3. Clicks, by recorded frames only: `setup-setup`, then `setup-continue` on Find. On Connect it turns off Patch and
     Start, then clicks `setup-continue`.
  4. Prints after each click: the step, the chosen folder, and finally the `results`, the temp `settings.json`
     statusLine, and the setup state.

  It must not use `AppState`'s real config: give it an `AppState` over a temp `ConfigStore` (the same mechanism the
  existing tests use), or skip `setSetup` in test mode and print the state instead.

  Run: `(build/ClaudeBar.app/Contents/MacOS/ClaudeBar --test-setup > /tmp/cb-setup.log 2>&1 &); sleep 15; pkill -f build/ClaudeBar.app/Contents/MacOS/ClaudeBar; cat /tmp/cb-setup.log`

  Expected:
  - steps welcome → find → connect → done
  - the chosen folder is the temp Cat Office
  - usage ✓, with the temp settings' command `bash ~/.claude/statusline-command.sh`
  - the state is `reduced` (a Cat Office was chosen, the patch was unticked)
  - the real `~/.claude/settings.json` is unchanged (compare an `md5` taken before and after the run)

- [ ] **Step 4: Docs**
  - README: a "Setting up ClaudeBar" section (the window, skipping, reopening).
  - `guide.html`: the same under "If something's wrong", with "Settings → Set up ClaudeBar…".
  - Help panel: one line, "First time? Settings → Set up ClaudeBar…".
- [ ] **Step 5: Full verification and install**

```bash
swift test 2>&1 | tail -1; bash scripts/test-statusline.sh | grep -c '^PASS'
bash scripts/test-setup-scripts.sh ~/Documents/projects/cat-ai-office-with-art-20261006-1038 | tail -1
md5 -q ~/.claude/settings.json > /tmp/cb-settings.md5
(CLAUDEBAR_START_TAB=office build/ClaudeBar.app/Contents/MacOS/ClaudeBar --test-tabs > /tmp/cb-tabtest.log 2>&1 &); sleep 14; pkill -f build/ClaudeBar.app/Contents/MacOS/ClaudeBar; grep -cE "^clicked|^floor clicked" /tmp/cb-tabtest.log
md5 -q ~/.claude/settings.json | cmp - /tmp/cb-settings.md5 && echo "real settings untouched"
pkill -f "MacOS/ClaudeBar"; sleep 1; rm -rf ~/Applications/ClaudeBar.app && cp -R build/ClaudeBar.app ~/Applications/ && open ~/Applications/ClaudeBar.app
```

  Expected:
  - all tests pass, then `8`, then `N passed, 0 failed`, then `8`, then "real settings untouched"
  - the installed app does **not** open the setup window on this Mac (an existing setup is inferred)

- [ ] **Step 6: Commit** — `feat: setup entry points (Office card, Settings), click test, docs`

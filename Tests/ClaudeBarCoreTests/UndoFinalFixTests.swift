import Foundation
import Testing
@testable import ClaudeBarCore

// Final whole-branch review fixes for undo.

extension StatusLineSetupTests {
    /// No status line → ClaudeBar's → the user puts their own script at ~/.claude/statusline-command.sh (what Claude
    /// Code's /statusline writes). That status line is theirs now: nothing to restore, and restore must not delete it.
    func claudeBarThenTheirOwnScript() throws -> (StatusLineSetup, URL) {
        let (s, dir) = try setup(#"{"model":"opus"}"#)
        try s.useClaudeBar()
        try write(dir, "statusline-command.sh", "#!/bin/bash\necho mine\n")
        return (s, dir)
    }

    @Test func theirScriptReplacingOursIsNotRestorable() throws {
        let (s, dir) = try claudeBarThenTheirOwnScript()
        #expect(s.state() == .own(command: "bash ~/.claude/statusline-command.sh"))
        #expect(!s.canRestore)
        let before = read(dir, "settings.json"), names = files(dir)
        #expect(throws: (any Error).self) { try s.restore() }
        #expect(read(dir, "settings.json") == before && files(dir) == names)
        #expect(read(dir, "statusline-command.sh") == "#!/bin/bash\necho mine\n")
    }

    @Test func keepingTheirScriptThenRestoreBringsItBack() throws {
        let (s, dir) = try claudeBarThenTheirOwnScript()
        try s.wrap()
        #expect(s.state() == .wrapped(original: "bash ~/.claude/statusline-command.sh"))
        #expect(files(dir).contains { $0.hasPrefix("claude-bar-statusline-original.json-stale-") })
        #expect(s.canRestore)
        try s.restore()
        #expect(s.state() == .own(command: "bash ~/.claude/statusline-command.sh"))
        #expect(read(dir, "statusline-command.sh") == "#!/bin/bash\necho mine\n")
        #expect((try settings(dir))["model"] as? String == "opus")
    }

    @Test func claudeBarAgainOverTheirScriptRestoresTheirs() throws {
        let (s, dir) = try claudeBarThenTheirOwnScript()
        try s.useClaudeBar()
        #expect(s.state() == .claudeBar && s.canRestore)
        try s.restore()
        #expect(s.state() == .own(command: "bash ~/.claude/statusline-command.sh"))
        #expect(read(dir, "statusline-command.sh") == "#!/bin/bash\necho mine\n")
    }

    @Test func anEditedClaudeBarScriptWithTheMarkerIsStillRestorable() throws {
        let (s, dir) = try setup(#"{"model":"opus"}"#)
        try s.useClaudeBar()
        try write(dir, "statusline-command.sh", ours + "\n# my tweak\n")
        #expect(s.canRestore)
    }
}

extension UndoPlanTests {
    /// A greyed row (still patched, or ClaudeBar's status line with no record) is left out, as is an unticked one.
    @Test func leftOutCountsGreyedAndUntickedRows() {
        let greyed = UndoPlan.rows(catOfficeDir: dir, unpatch: .cannotUndo, statusLine: .claudeBar, canRestore: true, home: home)
        #expect(UndoPlan.leftOut(rows: greyed, ticked: [.statusLine]))
        let all = UndoPlan.rows(catOfficeDir: dir, unpatch: .patched, statusLine: .claudeBar, canRestore: true, home: home)
        #expect(!UndoPlan.leftOut(rows: all, ticked: [.unpatch, .statusLine]))
        #expect(UndoPlan.leftOut(rows: all, ticked: [.unpatch]))
        #expect(!UndoPlan.leftOut(rows: all, ticked: [.unpatch, .statusLine, .remove]))
        let onlyRemove = UndoPlan.rows(catOfficeDir: dir, unpatch: .notPatched, statusLine: .none, canRestore: false, home: home)
        #expect(!UndoPlan.leftOut(rows: onlyRemove, ticked: [.remove]))
    }

    @Test func doneLinesNeverClaimAllDoneWithAGreyedRow() {
        let rows = UndoPlan.rows(catOfficeDir: dir, unpatch: .cannotUndo, statusLine: .claudeBar, canRestore: true, home: home)
        let leftOut = UndoPlan.leftOut(rows: rows, ticked: [.statusLine])
        #expect(UndoText.doneLines(results: [.statusLine: true], leftOut: leftOut) == [UndoText.extrasBack])
        #expect(UndoText.doneLines(results: [:], leftOut: false) == [UndoText.extrasBack])
        #expect(UndoText.doneLines(results: [.remove: false], leftOut: false) == [UndoText.extrasBack])
    }
}

extension StatusLineSetupTests {
    @Test func restoreSaysWhetherItBroughtALineBackOrRemovedOurs() throws {
        let (none, _) = try setup(#"{"model":"opus"}"#)
        try none.useClaudeBar()
        #expect(try none.restore() == .removed)
        let (theirs, _) = try setup(theirsCmd)
        try theirs.useClaudeBar()
        #expect(try theirs.restore() == .restored)
        let (wrapped, _) = try setup(theirsCmd)
        try wrapped.wrap()
        #expect(try wrapped.restore() == .restored)
    }

    @Test func restoredWording() {
        #expect(StatusLineRestore.removed.message == "ClaudeBar's status line is off, as before.")
        #expect(StatusLineRestore.restored.message == "Your old status line is back.")
    }
}

extension UndoPlanTests {
    @Test func failureMessagesEndAsSentences() {
        #expect(UndoText.sentence("~/.claude/settings.json isn't valid JSON; nothing was changed") == "~/.claude/settings.json isn't valid JSON; nothing was changed.")
        #expect(UndoText.sentence("Already ends.") == "Already ends.")
        #expect(UndoText.sentence("Really? ") == "Really?")
        #expect(UndoText.sentence("Wow!") == "Wow!")
    }
}

extension ClaudeBarRemovalTests {
    func setStatusLine(_ h: URL, _ command: String) {
        write(#"{"model":"opus","statusLine":{"type":"command","command":"\#(command)"}}"#, to: h.appendingPathComponent(".claude/settings.json"))
    }

    /// The wrapper in use: Claude Code still runs it (and it runs the hook), so both stay.
    @Test func helperScriptsStayWhileSettingsRunTheWrapper() {
        let h = home(); write("x", to: h.appendingPathComponent(".claude/claude-bar-hook.sh"))
        setStatusLine(h, "bash ~/.claude/claude-bar-statusline.sh")
        let (_, trash) = fakeTrash()
        let result = ClaudeBarRemoval(home: h, trash: trash).remove()
        #expect(result.failures.isEmpty && result.trashed.count == 4)
        for p in [".claude/claude-bar-statusline.sh", ".claude/claude-bar-hook.sh", ".claude/settings.json", ".claude/statusline-command.sh"] {
            #expect(exists(h, p))
        }
    }

    /// Not in use (ClaudeBar's own script, their own line, or none): both helpers go to the Trash; never
    /// settings.json or statusline-command.sh.
    @Test func helperScriptsGoWhenSettingsDoNotRunTheWrapper() {
        for command in ["bash ~/.claude/statusline-command.sh", "npx ccstatusline", nil] as [String?] {
            let h = home(); write("x", to: h.appendingPathComponent(".claude/claude-bar-hook.sh"))
            if let command { setStatusLine(h, command) } else { write(#"{"model":"opus"}"#, to: h.appendingPathComponent(".claude/settings.json")) }
            let settingsBefore = try? String(contentsOf: h.appendingPathComponent(".claude/settings.json"), encoding: .utf8)
            let (_, trash) = fakeTrash()
            let result = ClaudeBarRemoval(home: h, trash: trash).remove()
            #expect(result.failures.isEmpty && result.trashed.count == 6)
            #expect(!exists(h, ".claude/claude-bar-statusline.sh") && !exists(h, ".claude/claude-bar-hook.sh"))
            #expect(exists(h, ".claude/statusline-command.sh"))
            #expect((try? String(contentsOf: h.appendingPathComponent(".claude/settings.json"), encoding: .utf8)) == settingsBefore)
        }
    }

    /// settings.json unreadable: ClaudeBar can't tell whether the wrapper runs, so the helpers stay.
    @Test func helperScriptsStayWhenSettingsAreUnreadable() {
        let h = home(); write("{ broken", to: h.appendingPathComponent(".claude/settings.json"))
        let (_, trash) = fakeTrash()
        _ = ClaudeBarRemoval(home: h, trash: trash).remove()
        #expect(exists(h, ".claude/claude-bar-statusline.sh"))
    }
}

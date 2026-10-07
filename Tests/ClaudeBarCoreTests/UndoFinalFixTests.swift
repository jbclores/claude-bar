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

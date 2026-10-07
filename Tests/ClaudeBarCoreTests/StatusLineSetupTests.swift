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
        let (s, dir) = try setup(##"{"statusLine":{"type":"command","command":"# placeholder"}}"##)
        var d = try settings(dir); d["statusLine"] = ["type": "command", "command": theirs]
        try JSONSerialization.data(withJSONObject: d).write(to: dir.appendingPathComponent("settings.json"))
        try s.wrap()
        #expect(s.state() == .wrapped(original: theirs))
        // Run the wrapper as Claude Code would: their output, byte for byte; ClaudeBar's data saved quietly.
        let home = dir.appendingPathComponent("home")
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
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

    func read(_ dir: URL, _ name: String) -> String? { try? String(contentsOf: dir.appendingPathComponent(name), encoding: .utf8) }
    func write(_ dir: URL, _ name: String, _ text: String) throws { try Data(text.utf8).write(to: dir.appendingPathComponent(name)) }
    func files(_ dir: URL) -> [String] { ((try? FileManager.default.contentsOfDirectory(atPath: dir.path)) ?? []).sorted() }
    let theirsCmd = #"{"statusLine":{"type":"command","command":"npx ccstatusline"}}"#

    @Test func wrapTwiceThrowsAndChangesNothing() throws {
        let (s, dir) = try setup(theirsCmd)
        try s.wrap()
        let before = files(dir), settingsBefore = read(dir, "settings.json"), wrapperBefore = read(dir, StatusLineSetup.wrapperName)
        #expect(throws: (any Error).self) { try s.wrap() }
        #expect(files(dir) == before && read(dir, "settings.json") == settingsBefore && read(dir, StatusLineSetup.wrapperName) == wrapperBefore)
        try s.restore()
        #expect(s.state() == .own(command: "npx ccstatusline"))
    }

    @Test func wrapperCommandWithoutRecordIsNotWrappedAgain() throws {
        let (s, dir) = try setup(#"{"statusLine":{"type":"command","command":"bash ~/.claude/claude-bar-statusline.sh"}}"#)
        #expect(s.state() == .own(command: "bash ~/.claude/claude-bar-statusline.sh"))
        #expect(throws: (any Error).self) { try s.wrap() }
        #expect(read(dir, StatusLineSetup.wrapperName) == nil)
    }

    @Test func claudeBarThenWrapThenRestoreBringsEverythingBack() throws {
        let (s, dir) = try setup(#"{"statusLine":{"type":"command","command":"bash ~/.claude/statusline-command.sh"}}"#)
        try write(dir, "statusline-command.sh", "#!/bin/bash\necho theirs\n")
        try s.useClaudeBar()
        try s.wrap()
        #expect(s.state() == .wrapped(original: "bash ~/.claude/statusline-command.sh") || s.state() == .own(command: "bash ~/.claude/statusline-command.sh"))
        try s.restore()
        #expect(s.state() == .own(command: "bash ~/.claude/statusline-command.sh"))
        #expect(read(dir, "statusline-command.sh") == "#!/bin/bash\necho theirs\n")
        #expect(!s.canRestore)
    }

    @Test func wrapThenClaudeBarThenRestore() throws {
        let (s, dir) = try setup(theirsCmd)
        try s.wrap()
        try s.useClaudeBar()
        #expect(s.state() == .claudeBar)
        try s.restore()
        #expect(s.state() == .own(command: "npx ccstatusline"))
        #expect(!(read(dir, "settings.json") ?? "").contains(StatusLineSetup.wrapperName))
    }

    @Test func restoreTwiceThrowsAndChangesNothing() throws {
        let (s, dir) = try setup(theirsCmd)
        try s.useClaudeBar(); try s.restore()
        let after = read(dir, "settings.json"), names = files(dir)
        #expect(throws: (any Error).self) { try s.restore() }
        #expect(read(dir, "settings.json") == after && files(dir) == names)
    }

    @Test func restoreWithTheBackupMissingThrowsAndRemovesNothing() throws {
        let (s, dir) = try setup(#"{"statusLine":{"type":"command","command":"bash ~/.claude/statusline-command.sh"}}"#)
        try write(dir, "statusline-command.sh", "#!/bin/bash\necho theirs\n")
        try s.useClaudeBar()
        for f in files(dir) where f.hasPrefix("statusline-command.sh.claude-bar-backup-") { try FileManager.default.removeItem(at: dir.appendingPathComponent(f)) }
        let settingsBefore = read(dir, "settings.json")
        #expect(throws: (any Error).self) { try s.restore() }
        #expect(read(dir, "statusline-command.sh") == ours && read(dir, "settings.json") == settingsBefore && s.canRestore)
    }

    @Test func theirEditAfterClaudeBarIsBackedUpNotLost() throws {
        let (s, dir) = try setup(#"{"statusLine":{"type":"command","command":"bash ~/.claude/statusline-command.sh"}}"#)
        try write(dir, "statusline-command.sh", "#!/bin/bash\necho theirs\n")
        try s.useClaudeBar()
        try write(dir, "statusline-command.sh", "#!/bin/bash\necho edited\n")
        try s.restore()
        #expect(read(dir, "statusline-command.sh") == "#!/bin/bash\necho theirs\n")
        let kept = files(dir).filter { $0.hasPrefix("statusline-command.sh.claude-bar-backup-") }.compactMap { read(dir, $0) }
        #expect(kept.contains("#!/bin/bash\necho edited\n"))
    }

    @Test func extraStatusLineKeysSurviveEverything() throws {
        let original = #"{"statusLine":{"type":"command","command":"npx ccstatusline","padding":2}}"#
        let (s, dir) = try setup(original)
        try s.wrap()
        #expect((try settings(dir)["statusLine"] as? [String: Any])?["padding"] as? Int == 2)
        try s.useClaudeBar()
        #expect((try settings(dir)["statusLine"] as? [String: Any])?["padding"] as? Int == 2)
        try s.restore()
        let line = try settings(dir)["statusLine"] as? [String: Any]
        #expect(line?["padding"] as? Int == 2 && line?["command"] as? String == "npx ccstatusline" && line?["type"] as? String == "command")
    }

    @Test func aStatusLineWithoutACommandIsRestored() throws {
        let (s, dir) = try setup(#"{"statusLine":{"type":"static","text":"hi"}}"#)
        #expect(s.state() == .none)
        try s.useClaudeBar()
        try s.restore()
        let line = try settings(dir)["statusLine"] as? [String: Any]
        #expect(line?["type"] as? String == "static" && line?["text"] as? String == "hi" && line?["command"] == nil)
    }

    @Test func aScriptAtAnotherPathIsTheirOwn() throws {
        let (s, dir) = try setup(#"{"statusLine":{"type":"command","command":"bash ~/dotfiles/statusline-command.sh"}}"#)
        try write(dir, "statusline-command.sh", ours)
        #expect(s.state() == .own(command: "bash ~/dotfiles/statusline-command.sh"))
    }

    @Test func homeAndAbsoluteSpellingsAreClaudeBars() throws {
        for cmd in ["bash $HOME/.claude/statusline-command.sh", "bash  \"$HOME/.claude/statusline-command.sh\""] {
            let (s, dir) = try setup("{}")
            try write(dir, "statusline-command.sh", ours)
            var d = try settings(dir); d["statusLine"] = ["type": "command", "command": cmd]
            try JSONSerialization.data(withJSONObject: d).write(to: dir.appendingPathComponent("settings.json"))
            #expect(s.state() == .claudeBar)
        }
        let (s, dir) = try setup("{}")
        try write(dir, "statusline-command.sh", ours)
        let abs = dir.deletingLastPathComponent().path + "/.claude/statusline-command.sh"
        try JSONSerialization.data(withJSONObject: ["statusLine": ["type": "command", "command": "bash " + abs]]).write(to: dir.appendingPathComponent("settings.json"))
        #expect(s.state() == .claudeBar)
    }

    @Test func aWrappedCommandWithNewlineAndBacktickRunsExactly() throws {
        let theirs = "echo \"line1\"\necho `echo tick`"
        let (s, dir) = try setup("{}")
        try JSONSerialization.data(withJSONObject: ["statusLine": ["type": "command", "command": theirs]]).write(to: dir.appendingPathComponent("settings.json"))
        try s.wrap()
        let home = dir.appendingPathComponent("home")
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        let p = Process(); p.executableURL = URL(fileURLWithPath: "/bin/bash"); p.arguments = [dir.appendingPathComponent(StatusLineSetup.wrapperName).path]
        p.environment = ["HOME": home.path, "PATH": "/usr/bin:/bin", "CLAUDE_BAR_DIR": home.appendingPathComponent("cb").path,
                         "CLAUDEBAR_HOOK": dir.appendingPathComponent(StatusLineSetup.hookName).path]
        let input = Pipe(), output = Pipe(); p.standardInput = input; p.standardOutput = output
        try p.run(); try input.fileHandleForWriting.close(); p.waitUntilExit()
        #expect(String(data: output.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) == "line1\ntick\n")
    }

    func handSet(_ dir: URL, _ command: String) throws {
        var d = try settings(dir); d["statusLine"] = ["type": "command", "command": command]
        try JSONSerialization.data(withJSONObject: d).write(to: dir.appendingPathComponent("settings.json"))
    }

    @Test func aHandChangedStatusLineMakesTheRecordStaleAfterClaudeBar() throws {
        let (s, dir) = try setup(theirsCmd)
        try s.useClaudeBar()
        try handSet(dir, "my-new-line")
        #expect(!s.canRestore)
        let before = read(dir, "settings.json"), names = files(dir)
        #expect(throws: (any Error).self) { try s.restore() }
        #expect(read(dir, "settings.json") == before && files(dir) == names)
        try s.useClaudeBar()
        #expect(files(dir).contains { $0.hasPrefix("claude-bar-statusline-original.json-stale-") })
        try s.restore()
        #expect(s.state() == .own(command: "my-new-line"))
    }

    @Test func aHandChangedStatusLineMakesTheRecordStaleAfterWrap() throws {
        let (s, dir) = try setup(theirsCmd)
        try s.wrap()
        try handSet(dir, "my-new-line")
        #expect(!s.canRestore)
        #expect(throws: (any Error).self) { try s.restore() }
        try s.wrap()
        try s.restore()
        #expect(s.state() == .own(command: "my-new-line"))
    }

    @Test func wrapThatCannotProceedLeavesClaudeBarInstalled() throws {
        let (s, dir) = try setup(#"{"model":"opus"}"#)
        try s.useClaudeBar()          // nothing of theirs recorded (no statusLine, no script), so no record
        #expect(throws: (any Error).self) { try s.wrap() }
        #expect(s.state() == .claudeBar)
        // A record whose original was "no statusLine": wrap must refuse without undoing the install.
        let (s2, dir2) = try setup(#"{"statusLine":{"type":"static","text":"hi"}}"#)
        try s2.useClaudeBar()
        #expect(throws: (any Error).self) { try s2.wrap() }
        #expect(s2.state() == .claudeBar && s2.canRestore)
        _ = dir; _ = dir2
    }

    @Test func unreadableSettingsNeverArchiveALiveRecord() throws {
        let (s, dir) = try setup(theirsCmd)
        try s.useClaudeBar()
        let good = read(dir, "settings.json")!, record = read(dir, StatusLineSetup.originalName)
        try write(dir, "settings.json", "{ broken")
        let names = files(dir)
        #expect(throws: (any Error).self) { try s.useClaudeBar() }
        #expect(throws: (any Error).self) { try s.wrap() }
        #expect(throws: (any Error).self) { try s.restore() }
        #expect(read(dir, StatusLineSetup.originalName) == record && files(dir) == names)
        #expect(!files(dir).contains { $0.contains("-stale-") })
        try write(dir, "settings.json", good)
        #expect(s.canRestore)
        try s.restore()
        #expect(s.state() == .own(command: "npx ccstatusline"))
    }

    @Test func wrapRefusesWhenRestoringWouldLandOnAClaudeBarScript() throws {
        let (s, dir) = try setup(#"{"statusLine":{"type":"command","command":"bash ~/.claude/statusline-command.sh"}}"#)
        try write(dir, "statusline-command.sh", "#!/bin/bash\n# older ClaudeBar writes ~/.claude/claude-bar\n")
        try s.useClaudeBar()
        #expect(s.state() == .claudeBar && s.canRestore)
        let before = read(dir, "settings.json"), names = files(dir)
        #expect(throws: (any Error).self) { try s.wrap() }
        #expect(read(dir, "settings.json") == before && files(dir) == names && s.state() == .claudeBar)
    }
}

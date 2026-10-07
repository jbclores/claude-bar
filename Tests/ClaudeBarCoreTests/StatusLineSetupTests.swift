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

import Foundation
import Testing
@testable import ClaudeBarCore

// Final review fixes for onboarding.

extension StatusLineSetupTests {
    // 7. An empty (or foreign) bundled script is never installed.
    @Test func anEmptyOrForeignScriptIsNeverInstalled() throws {
        for bad in ["", "#!/bin/bash\necho not ClaudeBar's\n"] {
            let dir = makeTempDir()
            try Data(theirsCmd.utf8).write(to: dir.appendingPathComponent("settings.json"))
            let s = StatusLineSetup(claudeDir: dir, script: bad)
            let before = files(dir), settingsBefore = read(dir, "settings.json")
            #expect(throws: StatusLineError.self) { try s.useClaudeBar() }
            #expect(throws: StatusLineError.self) { try s.wrap() }
            #expect(files(dir) == before && read(dir, "settings.json") == settingsBefore)
        }
    }

    // 4. Without Apple's command line tools (python3, git), nothing is installed or wrapped.
    @Test func withoutCommandLineToolsNothingIsInstalledOrWrapped() throws {
        for start in [theirsCmd, #"{"model":"opus"}"#] {
            let dir = makeTempDir()
            try Data(start.utf8).write(to: dir.appendingPathComponent("settings.json"))
            let s = StatusLineSetup(claudeDir: dir, script: ours, toolsInstalled: { false })
            let before = files(dir), settingsBefore = read(dir, "settings.json")
            #expect(throws: StatusLineError(message: StatusLineSetup.toolsMissing)) { try s.useClaudeBar() }
            #expect(throws: StatusLineError(message: StatusLineSetup.toolsMissing)) { try s.wrap() }
            #expect(files(dir) == before && read(dir, "settings.json") == settingsBefore)
        }
        #expect(StatusLineSetup.toolsMissing == "Usage needs Apple's command line tools: run xcode-select --install, then Settings → Set up ClaudeBar…")
    }

    // 5. Symlinked settings.json and script (dotfiles setups) stay symlinks; their targets change; backups hold content.
    func isLink(_ url: URL) -> Bool {
        ((try? FileManager.default.attributesOfItem(atPath: url.path))?[.type] as? FileAttributeType) == .typeSymbolicLink
    }

    func linkedSetup(settings: String, script: String?) throws -> (StatusLineSetup, URL, URL) {
        let dir = makeTempDir(), dots = makeTempDir()
        try Data(settings.utf8).write(to: dots.appendingPathComponent("settings.json"))
        try FileManager.default.createSymbolicLink(at: dir.appendingPathComponent("settings.json"), withDestinationURL: dots.appendingPathComponent("settings.json"))
        if let script {
            try Data(script.utf8).write(to: dots.appendingPathComponent("statusline-command.sh"))
            try FileManager.default.createSymbolicLink(at: dir.appendingPathComponent("statusline-command.sh"),
                                                       withDestinationURL: dots.appendingPathComponent("statusline-command.sh"))
        }
        return (StatusLineSetup(claudeDir: dir, script: ours, now: { Date(timeIntervalSince1970: 1_791_300_000) }), dir, dots)
    }

    @Test func symlinkedFilesStayLinksThroughClaudeBarAndRestore() throws {
        let theirs = #"{"statusLine":{"type":"command","command":"bash ~/.claude/statusline-command.sh"}}"#
        let (s, dir, dots) = try linkedSetup(settings: theirs, script: "#!/bin/bash\necho theirs\n")
        try s.useClaudeBar()
        #expect(s.state() == .claudeBar)
        #expect(isLink(dir.appendingPathComponent("settings.json")) && isLink(dir.appendingPathComponent("statusline-command.sh")))
        #expect(read(dots, "statusline-command.sh") == ours)
        #expect(read(dots, "settings.json")?.contains("bash ~/.claude/statusline-command.sh") == true)
        // Backups are real files holding the content, not links.
        let backups = files(dir).filter { $0.contains(".claude-bar-backup-") }
        #expect(!backups.isEmpty)
        for b in backups { #expect(!isLink(dir.appendingPathComponent(b))) }
        #expect(backups.contains { read(dir, $0) == "#!/bin/bash\necho theirs\n" })
        #expect(backups.contains { read(dir, $0) == theirs })
        try s.restore()
        #expect(isLink(dir.appendingPathComponent("settings.json")) && isLink(dir.appendingPathComponent("statusline-command.sh")))
        #expect(read(dots, "statusline-command.sh") == "#!/bin/bash\necho theirs\n")
        #expect(s.state() == .own(command: "bash ~/.claude/statusline-command.sh"))
    }

    @Test func symlinkedSettingsStayALinkThroughWrapAndRestore() throws {
        let (s, dir, dots) = try linkedSetup(settings: theirsCmd, script: nil)
        try s.wrap()
        #expect(s.state() == .wrapped(original: "npx ccstatusline"))
        #expect(isLink(dir.appendingPathComponent("settings.json")))
        #expect(read(dots, "settings.json")?.contains(StatusLineSetup.wrapperName) == true)
        try s.restore()
        #expect(isLink(dir.appendingPathComponent("settings.json")))
        #expect(s.state() == .own(command: "npx ccstatusline"))
    }
}

extension SetupSettingsTests {
    // 3. A remembered folder (no configured one) counts as a known Cat Office.
    @Test func aRememberedPatchedFolderWithClaudeBarsStatusLineIsFull() async throws {
        let co = makeTempDir()
        try FileManager.default.createDirectory(at: co.appendingPathComponent("server/agent-bridge"), withIntermediateDirectories: true)
        write(#"{"name":"cat-office"}"#, to: co.appendingPathComponent("package.json"))
        let claude = makeTempDir()
        let script = try String(contentsOfFile: #filePath.replacingOccurrences(of: "Tests/ClaudeBarCoreTests/OnboardingFixTests.swift", with: "scripts/statusline-command.sh"), encoding: .utf8)
        let line = StatusLineSetup(claudeDir: claude, script: script)
        try line.useClaudeBar()
        var asked: [String] = []
        let s = await SetupSettings.inferred(configured: nil, remembered: co.path, bridgeDir: nil, statusLine: line.state()) { dir in
            asked.append(dir); return true
        }
        #expect(asked == [co.path])
        #expect(s == SetupSettings(seen: true, state: .full))
        #expect(!SetupSettings.opensByItself(SetupSettings(), inferred: s))
        // A configured folder that's gone falls back to the remembered one too.
        let s2 = await SetupSettings.inferred(configured: "/nonexistent/co", remembered: co.path, bridgeDir: nil, statusLine: line.state()) { _ in true }
        #expect(s2 == SetupSettings(seen: true, state: .full))
        // Neither known: the window opens.
        let s3 = await SetupSettings.inferred(configured: nil, remembered: nil, bridgeDir: nil, statusLine: line.state()) { _ in true }
        #expect(s3 == nil)
    }

    // 8. After a restore, usage is off: a full setup is reduced; others stay.
    @Test func restoringTheStatusLineReducesAFullSetup() {
        #expect(SetupSettings(seen: true, state: .full).afterStatusLineRestore() == SetupSettings(seen: true, state: .reduced))
        #expect(SetupSettings(seen: true, state: .reduced).afterStatusLineRestore() == SetupSettings(seen: true, state: .reduced))
        #expect(SetupSettings(seen: true, state: .noCatOffice).afterStatusLineRestore() == SetupSettings(seen: true, state: .noCatOffice))
        #expect(SetupSettings(seen: true, state: nil).afterStatusLineRestore() == SetupSettings(seen: true, state: nil))
    }
}

@Suite struct CatOfficeBridgeTrustTests {
    // 2. A stale bridge (dead pid, or a pid that isn't node/npm) isn't Cat Office.
    @Test func onlyALiveNodeProcessIsTrusted() throws {
        #expect(!CatOfficeDiscovery.isNodeOrNpm(getpid()), "the test runner isn't node")
        #expect(!CatOfficeDiscovery.isCatOfficeProcess(getpid()))
        let sleeper = Process(); sleeper.executableURL = URL(fileURLWithPath: "/bin/sleep"); sleeper.arguments = ["30"]
        try sleeper.run(); defer { sleeper.terminate() }
        #expect(!CatOfficeDiscovery.isCatOfficeProcess(sleeper.processIdentifier))
        #expect(!CatOfficeDiscovery.isCatOfficeProcess(999_999))
        // A stand-in named node (compiled; a copied system binary is killed on Apple silicon).
        let dir = makeTempDir()
        write("#include <unistd.h>\nint main(void){sleep(30);return 0;}\n", to: dir.appendingPathComponent("n.c"))
        let cc = Process(); cc.executableURL = URL(fileURLWithPath: "/usr/bin/clang")
        cc.arguments = ["-o", dir.appendingPathComponent("node").path, dir.appendingPathComponent("n.c").path]
        guard (try? cc.run()) != nil else { return }
        cc.waitUntilExit()
        guard cc.terminationStatus == 0 else { return }
        let node = Process(); node.executableURL = dir.appendingPathComponent("node")
        try node.run(); defer { node.terminate() }
        #expect(CatOfficeDiscovery.isCatOfficeProcess(node.processIdentifier))
    }

    // 1. Cat Office reloaded with the patch: its bridge names the folder again, from a new start (pid or token).
    @Test func aReloadIsANewBridgeForTheFolder() {
        let before = BridgeStamp(pid: 10, token: "a", dir: "/w/co")
        #expect(!CatOfficeDiscovery.reloaded(before: before, after: before, dir: "/w/co"))
        #expect(!CatOfficeDiscovery.reloaded(before: before, after: nil, dir: "/w/co"))
        #expect(CatOfficeDiscovery.reloaded(before: before, after: BridgeStamp(pid: 11, token: "a", dir: "/w/co"), dir: "/w/co"))
        #expect(CatOfficeDiscovery.reloaded(before: before, after: BridgeStamp(pid: 10, token: "b", dir: "/w/co"), dir: "/w/co"))
        #expect(!CatOfficeDiscovery.reloaded(before: before, after: BridgeStamp(pid: 11, token: "b", dir: "/w/other"), dir: "/w/co"))
        #expect(CatOfficeDiscovery.reloaded(before: nil, after: BridgeStamp(pid: 11, token: "b", dir: "/w/co"), dir: "/w/co"))
    }

    @Test func bridgeStampReadsPidTokenAndFolder() throws {
        let file = makeTempDir().appendingPathComponent("bridge.json")
        write(#"{"url":"http://localhost:5174","token":"tok","dir":"/w/cat-office","pid":42}"#, to: file)
        #expect(CatOfficeDiscovery.bridgeStamp(file: file, isAlive: { $0 == 42 }) == BridgeStamp(pid: 42, token: "tok", dir: "/w/cat-office"))
        #expect(CatOfficeDiscovery.bridgeStamp(file: file, isAlive: { _ in false }) == nil)
    }
}

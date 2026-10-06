import Foundation
import Testing
@testable import ClaudeBarCore

@Suite struct CatOfficeLauncherTests {
    @Test func findsFirstFolderWithNpmAndNode() {
        let home = makeTempDir()
        let nvmOld = home.appendingPathComponent(".nvm/versions/node/v18.20.0/bin")
        let nvmNew = home.appendingPathComponent(".nvm/versions/node/v22.11.0/bin")
        for dir in [nvmOld, nvmNew] {
            write("", to: dir.appendingPathComponent("npm"))
            write("", to: dir.appendingPathComponent("node"))
        }
        let found = CatOfficeLauncher.nodeBinDir(home: home.path, systemDirs: ["/nonexistent-\(UUID())"])
        #expect(found == nvmNew.path)
    }

    @Test func prefersSystemDirsWhenTheyHaveNpm() {
        let sys = makeTempDir()
        write("", to: sys.appendingPathComponent("npm"))
        write("", to: sys.appendingPathComponent("node"))
        #expect(CatOfficeLauncher.nodeBinDir(home: makeTempDir().path, systemDirs: [sys.path]) == sys.path)
    }

    @Test func noneFound() {
        #expect(CatOfficeLauncher.nodeBinDir(home: makeTempDir().path, systemDirs: []) == nil)
    }

    @Test func nvmVersionsSortNumerically() {
        #expect(CatOfficeLauncher.newestVersion(["v9.1.0", "v22.1.0", "v18.20.4", "notes"]) == "v22.1.0")
    }

    @Test func environmentGivesATerminalLikePath() {
        let env = CatOfficeLauncher.environment(
            binDir: "/opt/node/bin", base: ["PATH": "/usr/bin:/bin", "HOME": "/Users/me"],
            loginPath: "/Users/me/.cargo/bin:/usr/local/bin:/usr/bin", home: "/Users/me")
        #expect(env["PATH"] == [
            "/opt/node/bin", "/Users/me/.local/bin", "/opt/homebrew/bin", "/opt/homebrew/sbin", "/usr/local/bin",
            "/Users/me/.cargo/bin", "/usr/bin", "/bin",
        ].joined(separator: ":"))
        #expect(env["HOME"] == "/Users/me")
        let noLogin = CatOfficeLauncher.environment(binDir: "/n", base: [:], loginPath: nil, home: "/h")
        #expect(noLogin["PATH"]?.hasSuffix(":/usr/bin:/bin:/usr/sbin:/sbin") == true)
    }

    @Test func loginShellPathIsReadWithATimeout() {
        let path = CatOfficeLauncher.loginShellPath(shell: "/bin/zsh", timeout: 5)
        #expect(path?.contains("/usr/bin") == true)
        #expect(CatOfficeLauncher.loginShellPath(shell: "/nonexistent-shell", timeout: 1) == nil)
    }

    @Test func refusesWithoutFolder() async {
        let result = await CatOfficeLauncher().start(settings: CatOfficeSettings(dir: nil), log: makeTempDir().appendingPathComponent("l.log"))
        #expect(result == .notConfigured)
        let missing = await CatOfficeLauncher().start(settings: CatOfficeSettings(dir: "/nonexistent-\(UUID())"), log: makeTempDir().appendingPathComponent("l.log"))
        #expect(missing == .notConfigured)
    }

    @Test(.enabled(if: ProcessInfo.processInfo.environment["CLAUDEBAR_LIVE"] == "1"))
    func doesNotStartASecondCopy() async {
        let dir = NSHomeDirectory() + "/Downloads/cat-ai-office-with-art-20261006-1038"
        let result = await CatOfficeLauncher().start(settings: CatOfficeSettings(dir: dir), log: makeTempDir().appendingPathComponent("l.log"))
        #expect(result == .alreadyRunning)
    }
}

@Suite struct CatOfficeLauncherLiveTests {
    @Test(.enabled(if: ProcessInfo.processInfo.environment["CLAUDEBAR_LIVE"] == "1"))
    func runsNpmDevInTheFolderAndLogs() async throws {
        let dir = makeTempDir()
        write(#"{"name":"stand-in","private":true,"scripts":{"dev":"node -e \"require('fs').writeFileSync('ran','ok'); console.log('dev up')\""}}"#,
              to: dir.appendingPathComponent("package.json"))
        let log = makeTempDir().appendingPathComponent("logs/cat-office.log")
        let result = await CatOfficeLauncher().start(
            settings: CatOfficeSettings(dir: dir.path, url: URL(string: "http://localhost:59999")!), log: log)
        #expect(result == .started)
        let marker = dir.appendingPathComponent("ran")
        for _ in 0..<50 where !FileManager.default.fileExists(atPath: marker.path) { try await Task.sleep(nanoseconds: 100_000_000) }
        #expect(FileManager.default.fileExists(atPath: marker.path))
        try await Task.sleep(nanoseconds: 300_000_000)
        let text = try String(contentsOf: log, encoding: .utf8)
        #expect(text.contains("ClaudeBar started Cat Office") && text.contains("dev up"))
    }
}

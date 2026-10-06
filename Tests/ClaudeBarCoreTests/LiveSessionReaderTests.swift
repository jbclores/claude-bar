import Foundation
import Testing
@testable import ClaudeBarCore

@Suite struct LiveSessionReaderTests {
    @Test func keepsOnlyRunningSessionsAndMapsStatus() {
        let dir = makeTempDir()
        write(#"{"pid":1,"sessionId":"busy","cwd":"/p/a","status":"busy","name":"term-a","entrypoint":"cli"}"#, to: dir.appendingPathComponent("1.json"))
        write(#"{"pid":2,"sessionId":"idle","cwd":"/p/b","status":"idle","name":"office-x","entrypoint":"sdk-cli"}"#, to: dir.appendingPathComponent("2.json"))
        write(#"{"pid":3,"sessionId":"wait","cwd":"/p/c","status":"busy","waitingFor":"permission"}"#, to: dir.appendingPathComponent("3.json"))
        write(#"{"pid":4,"sessionId":"dead","cwd":"/p/d","status":"busy"}"#, to: dir.appendingPathComponent("4.json"))
        write(#"{"pid":5,"sessionId":"nullwait","cwd":"/p/e","status":"idle","waitingFor":null}"#, to: dir.appendingPathComponent("5.json"))
        write("garbage", to: dir.appendingPathComponent("6.json"))
        write("x", to: dir.appendingPathComponent("7.abc.key"))
        let reader = LiveSessionReader(dir: dir, isAlive: { $0 != 4 })
        let byKey = Dictionary(uniqueKeysWithValues: reader.read().map { ($0.key, $0) })
        #expect(Set(byKey.keys) == ["busy", "idle", "wait", "nullwait"])
        #expect(byKey["busy"]?.status == .working)
        #expect(byKey["idle"]?.status == .idle)
        #expect(byKey["wait"]?.status == .waiting)
        #expect(byKey["nullwait"]?.status == .idle)
        #expect(byKey["busy"]?.cwd == Paths.normalize("/p/a"))
        #expect(byKey["busy"]?.name == "term-a")
        #expect(byKey["idle"]?.isOffice == true)
        #expect(byKey["busy"]?.isOffice == false)
    }

    @Test func urgencyOrder() {
        #expect(AgentStatus.waiting.urgency > AgentStatus.working.urgency)
        #expect(AgentStatus.working.urgency > AgentStatus.idle.urgency)
        #expect(AgentStatus.idle.urgency > AgentStatus.ended.urgency)
    }
}

@Suite struct GitBranchReaderTests {
    func git(_ dir: URL, _ args: String...) {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        p.arguments = ["-C", dir.path, "-c", "user.name=t", "-c", "user.email=t@t"] + args
        p.standardOutput = FileHandle.nullDevice
        p.standardError = FileHandle.nullDevice
        try! p.run()
        p.waitUntilExit()
    }

    @Test func branchOfNewRepo() {
        let dir = makeTempDir()
        git(dir, "init", "-q", "-b", "feat/invite-expiry")
        #expect(GitBranchReader().branch(at: dir.path) == "feat/invite-expiry")
    }

    @Test func subfolderAndDetached() throws {
        let dir = makeTempDir()
        git(dir, "init", "-q", "-b", "main")
        git(dir, "commit", "-q", "--allow-empty", "-m", "one")
        let sub = dir.appendingPathComponent("src")
        try FileManager.default.createDirectory(at: sub, withIntermediateDirectories: true)
        #expect(GitBranchReader().branch(at: sub.path) == "main")
        git(dir, "checkout", "-q", "--detach")
        #expect(GitBranchReader().branch(at: dir.path) == "detached")
    }

    @Test func notARepoOrMissing() {
        #expect(GitBranchReader().branch(at: makeTempDir().path) == nil)
        #expect(GitBranchReader().branch(at: "/nonexistent-\(UUID())") == nil)
    }
}

import Foundation
import Testing
@testable import ClaudeBarCore

/// Finding every Cat Office dev server for a folder, on any port (two copies make the cats disagree).
@Suite struct CatOfficeServersTests {
    @Test func parsesListeningServersAndTheirFolders() {
        let listening = "p1633\ncnode\nf18\nn[::1]:5173\nf20\nn127.0.0.1:24678\np1634\ncnode\nf18\nn[::1]:5174\np999\ncnode\nf3\nn*:3000\n"
        #expect(CatOfficeServers.listening(listening) == [1633: 5173, 1634: 5174, 999: 3000], "a process's lowest port")
        let cwd = "p1633\nfcwd\nn/Users/me/co\np1634\nfcwd\nn/Users/me/co\np999\nfcwd\nn/Users/me/other\n"
        #expect(CatOfficeServers.folders(cwd) == [1633: "/Users/me/co", 1634: "/Users/me/co", 999: "/Users/me/other"])
    }

    @Test func theExtraCopiesAreTheOnesClaudeBarIsntConnectedTo() {
        let a = CatOfficeServers.Server(pid: 1, port: 5173), b = CatOfficeServers.Server(pid: 2, port: 5174)
        #expect(CatOfficeServers.extra([a, b], connectedPort: 5174) == [a])
        #expect(CatOfficeServers.extra([a, b], connectedPort: 5173) == [b])
        #expect(CatOfficeServers.extra([b, a], connectedPort: nil) == [b], "not connected: keep the lowest port")
        #expect(CatOfficeServers.extra([a], connectedPort: 5174).isEmpty, "one copy is never extra")
        #expect(CatOfficeServers.extra([], connectedPort: nil).isEmpty)
    }

    /// Two fake Cat Office servers (node scripts at node_modules/.bin/vite) in a temp folder: both found, the extra one
    /// stopped, the other left running. Never touches a real Cat Office.
    @Test(.enabled(if: FileManager.default.isExecutableFile(atPath: "/opt/homebrew/bin/node")
                      || FileManager.default.isExecutableFile(atPath: "/usr/local/bin/node")))
    func findsAndStopsAnExtraCopyInATempFolder() async throws {
        let node = ["/opt/homebrew/bin/node", "/usr/local/bin/node"].first { FileManager.default.isExecutableFile(atPath: $0) }!
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("cb-servers-\(UUID().uuidString)")
        let bin = dir.appendingPathComponent("node_modules/.bin")
        try FileManager.default.createDirectory(at: bin, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let vite = bin.appendingPathComponent("vite")
        try "require('http').createServer((q, s) => s.end('ok')).listen(Number(process.argv[2]), '127.0.0.1');\n"
            .write(to: vite, atomically: true, encoding: .utf8)
        var procs: [Process] = []
        defer { procs.forEach { if $0.isRunning { $0.terminate() } } }
        for port in [47_311, 47_312] {
            let p = Process()
            p.executableURL = URL(fileURLWithPath: node)
            p.arguments = [vite.path, String(port)]
            p.currentDirectoryURL = dir
            try p.run()
            procs.append(p)
        }
        var found: [CatOfficeServers.Server] = []
        for _ in 0..<50 {
            found = CatOfficeServers.find(folder: dir.path)
            if found.count == 2 { break }
            try await Task.sleep(nanoseconds: 100_000_000)
        }
        #expect(found.map(\.port).sorted() == [47_311, 47_312])
        let extra = CatOfficeServers.extra(found, connectedPort: 47_311)
        #expect(extra.map(\.port) == [47_312])
        for s in extra { CatOfficeServers.stop(s) }
        for _ in 0..<50 where procs[1].isRunning { try await Task.sleep(nanoseconds: 100_000_000) }
        #expect(!procs[1].isRunning && procs[0].isRunning)
        #expect(CatOfficeServers.find(folder: dir.path).map(\.port) == [47_311])
    }
}

/// Settings' connection line: a plain sentence; the address and how fresh it is on hover.
@Suite struct ConnectionLineTests {
    let now = Date(timeIntervalSince1970: 1_800_000_000)

    @Test func connectedWithAndWithoutABrowserPage() {
        let url = URL(string: "http://localhost:5173")!
        let live = ConnectionLine.text(url: url, lastUpdate: now.addingTimeInterval(-2), placesLive: true, copies: 1, now: now)
        #expect(live.line == "Connected, copying your browser page")
        #expect(live.detail == "localhost:5173, updated 2 s ago")
        let noPage = ConnectionLine.text(url: url, lastUpdate: now.addingTimeInterval(-90), placesLive: false, copies: 1, now: now)
        #expect(noPage.line == "Connected. No browser page is open, so ClaudeBar runs the office itself")
        #expect(noPage.detail == "localhost:5173, updated 1 min ago")
        #expect(ConnectionLine.text(url: url, lastUpdate: now, placesLive: true, copies: 2, now: now).line
                == "Connected, but two copies of Cat Office are running")
        #expect(ConnectionLine.text(url: url, lastUpdate: now, placesLive: true, copies: 1, now: now).detail == "localhost:5173, updated just now")
        let off = ConnectionLine.text(url: nil, lastUpdate: nil, placesLive: false, copies: 0, now: now)
        #expect(off.line == "Not connected to Cat Office" && off.detail == nil)
    }
}

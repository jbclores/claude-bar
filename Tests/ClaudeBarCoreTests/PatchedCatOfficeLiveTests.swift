import Foundation
import Testing
@testable import ClaudeBarCore

/// Runs only with CLAUDEBAR_PATCHED_DIR set to a running, patched Cat Office's folder.
@Suite struct PatchedCatOfficeLiveTests {
    @Test(.enabled(if: ProcessInfo.processInfo.environment["CLAUDEBAR_PATCHED_DIR"] != nil))
    func findsTheBridgeFileAndReadsCats() async throws {
        let dir = ProcessInfo.processInfo.environment["CLAUDEBAR_PATCHED_DIR"]!
        // The URL points nowhere: only bridge.json can lead the client to the server.
        let settings = CatOfficeSettings(dir: dir, url: URL(string: "http://localhost:1")!)
        let got = LockedBox<OfficeSnapshot?>(nil)
        let client = CatOfficeClient(settings: LockedBox(settings)) { snap in if let snap { got.set(snap) } }
        client.start()
        defer { client.stop() }
        for _ in 0..<80 where got.get() == nil { try await Task.sleep(nanoseconds: 100_000_000) }
        let snap = try #require(got.get())
        let withCat = snap.agents.filter { $0.cat != nil }
        print("via", client.baseURL, "cats:", withCat.map { "\($0.name)=\($0.cat!)" })
        #expect(client.baseURL.port != 1)
        #expect(withCat.contains { $0.cat == "tuxedo" })
        let agent = try #require(withCat.first)
        #expect(CatPicker.cat(for: agent, catIds: ["orange"]) == "tuxedo")
    }
}

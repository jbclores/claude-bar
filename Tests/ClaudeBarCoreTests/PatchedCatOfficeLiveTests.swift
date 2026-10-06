import Foundation
import Testing
@testable import ClaudeBarCore

/// Runs only with CLAUDEBAR_BRIDGE_FILE set to the bridge file of a running, patched Cat Office.
@Suite struct PatchedCatOfficeLiveTests {
    @Test(.enabled(if: ProcessInfo.processInfo.environment["CLAUDEBAR_BRIDGE_FILE"] != nil))
    func findsTheBridgeFileAndReadsCats() async throws {
        let file = URL(fileURLWithPath: ProcessInfo.processInfo.environment["CLAUDEBAR_BRIDGE_FILE"]!)
        // The URL points nowhere: only the bridge file can lead the client to the server.
        let settings = CatOfficeSettings(dir: nil, url: URL(string: "http://localhost:1")!)
        let got = LockedBox<OfficeSnapshot?>(nil)
        let seenDir = LockedBox<String?>(nil)
        let client = CatOfficeClient(settings: LockedBox(settings), bridgeFile: file,
                                     onBridge: { seenDir.set($0.dir) }) { snap in if let snap { got.set(snap) } }
        client.start()
        defer { client.stop() }
        for _ in 0..<80 where got.get() == nil { try await Task.sleep(nanoseconds: 100_000_000) }
        let snap = try #require(got.get())
        let withCat = snap.agents.filter { $0.cat != nil }
        print("via", client.baseURL, "cats:", withCat.map { "\($0.name)=\($0.cat!)" })
        #expect(client.baseURL.port != 1)
        #expect(seenDir.get() != nil)
        #expect(withCat.contains { $0.cat == "tuxedo" })
        let agent = try #require(withCat.first)
        #expect(CatPicker.cat(for: agent, catIds: ["orange"]) == "tuxedo")
    }
}

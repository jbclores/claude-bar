import Foundation
import Testing
@testable import ClaudeBarCore

/// Runs against the real Cat Office only with CLAUDEBAR_LIVE=1 (it must be running at localhost:5173).
@Suite struct CatOfficeLiveTests {
    @Test(.enabled(if: ProcessInfo.processInfo.environment["CLAUDEBAR_LIVE"] == "1"))
    func receivesASnapshotFromRunningCatOffice() async throws {
        let got = LockedBox<OfficeSnapshot?>(nil)
        let client = CatOfficeClient(settings: LockedBox(CatOfficeSettings())) { snap in
            if let snap { got.set(snap) }
        }
        client.start()
        defer { client.stop() }
        for _ in 0..<50 where got.get() == nil { try await Task.sleep(nanoseconds: 100_000_000) }
        let snap = try #require(got.get())
        #expect(!snap.agents.isEmpty)
        print("live agents:", snap.agents.map { "\($0.name)=\($0.status.rawValue)" })
    }
}

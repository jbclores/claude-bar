import Foundation
import Testing
@testable import ClaudeBarCore

@Suite struct SnapshotReaderTests {
    let now = Date(timeIntervalSince1970: 1_791_266_721)

    @Test func readsAllFields() {
        let dir = makeTempDir()
        write("""
        {"session_id":"s1","cwd":"/p","model":"Opus 5.5","context_pct":61.2,
         "five_hour_pct":42,"five_hour_resets_at":1791280000,
         "seven_day_pct":18.5,"seven_day_resets_at":"2026-10-09T01:00:00Z","updated_at":1791266700}
        """, to: dir.appendingPathComponent("s1.json"))
        let snaps = SnapshotReader(dir: dir).read(now: now)
        #expect(snaps.count == 1)
        let s = snaps[0]
        #expect(s.sessionId == "s1")
        #expect(s.model == "Opus 5.5")
        #expect(s.contextPct == 61.2)
        #expect(s.fiveHourPct == 42)
        #expect(s.fiveHourResetsAt == Date(timeIntervalSince1970: 1_791_280_000))
        #expect(s.sevenDayResetsAt == ISO8601DateFormatter().date(from: "2026-10-09T01:00:00Z"))
        #expect(s.updatedAt == Date(timeIntervalSince1970: 1_791_266_700))
    }

    @Test func nullFieldsAndMillisecondResets() {
        let dir = makeTempDir()
        write("""
        {"session_id":"s2","cwd":"/p","model":null,"context_pct":null,"five_hour_pct":null,
         "five_hour_resets_at":1791280000000,"seven_day_pct":null,"seven_day_resets_at":null,"updated_at":1791266700}
        """, to: dir.appendingPathComponent("s2.json"))
        let s = SnapshotReader(dir: dir).read(now: now)[0]
        #expect(s.model == nil)
        #expect(s.fiveHourPct == nil)
        #expect(s.fiveHourResetsAt == Date(timeIntervalSince1970: 1_791_280_000))
        #expect(s.sevenDayResetsAt == nil)
    }

    @Test func skipsInvalidAndTempFiles() {
        let dir = makeTempDir()
        write("not json", to: dir.appendingPathComponent("bad.json"))
        write(#"{"cwd":"/p","updated_at":1}"#, to: dir.appendingPathComponent("noid.json"))
        write(#"{"session_id":"t","cwd":"/p","updated_at":1791266700}"#, to: dir.appendingPathComponent(".tmp-x.json"))
        #expect(SnapshotReader(dir: dir).read(now: now).isEmpty)
    }

    @Test func deletesSnapshotsOlderThanMaxAge() {
        let dir = makeTempDir()
        let old = dir.appendingPathComponent("old.json")
        write(#"{"session_id":"old","cwd":"/p","updated_at":\#(now.timeIntervalSince1970 - 31 * 86_400)}"#, to: old)
        write(#"{"session_id":"new","cwd":"/p","updated_at":\#(now.timeIntervalSince1970 - 29 * 86_400)}"#, to: dir.appendingPathComponent("new.json"))
        let snaps = SnapshotReader(dir: dir).read(now: now)
        #expect(snaps.map(\.sessionId) == ["new"])
        #expect(!FileManager.default.fileExists(atPath: old.path))
    }

    @Test func missingDirectoryGivesNothing() {
        #expect(SnapshotReader(dir: URL(fileURLWithPath: "/nonexistent-\(UUID())")).read(now: now).isEmpty)
    }
}

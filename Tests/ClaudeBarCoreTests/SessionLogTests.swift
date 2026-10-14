import Foundation
import Testing
@testable import ClaudeBarCore

@Suite struct SessionLogTests {
    var utc: Calendar { var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(identifier: "UTC")!; return c }
    /// 2027-01-15 08:00 UTC.
    let t0 = Date(timeIntervalSince1970: 1_800_000_000)
    func at(_ m: Double) -> Date { t0.addingTimeInterval(m * 60) }

    @Test func spansAndFinishes() {
        var log = SessionLog()
        _ = log.update([("a", "claude-bar", .idle)], now: at(0))
        _ = log.update([("a", "claude-bar", .working)], now: at(10))
        _ = log.update([("a", "claude-bar", .waiting)], now: at(40))     // stops working, not finished
        _ = log.update([("a", "claude-bar", .working)], now: at(45))
        _ = log.update([("a", "claude-bar", .idle), ("b", "turbo", .working)], now: at(60))
        _ = log.update([("b", "turbo", .ended)], now: at(70))
        let r = TodayRecap.of(log, now: at(80), calendar: utc)
        #expect(r.finished == 2)
        #expect(r.working == (30 + 15 + 10) * 60)
        #expect(r.busiest == "claude-bar")
        #expect(r.line == "2 sessions finished · 55m working · busiest: claude-bar")
    }

    @Test func spansAcrossMidnightCountFromMidnight() {
        var log = SessionLog()
        _ = log.update([("a", "p", .working)], now: at(-9 * 60))   // yesterday 23:00
        _ = log.update([("a", "p", .idle)], now: at(-7 * 60))       // today 01:00
        let r = TodayRecap.of(log, now: at(0), calendar: utc)
        #expect(r.working == 3600 && r.finished == 1 && r.busiest == nil)
        #expect(r.line == "1 session finished · 1h working")
    }

    @Test func anOpenSpanCountsToNowAndNothingHidesTheLine() {
        var log = SessionLog()
        _ = log.update([("a", "p", .working)], now: at(0))
        #expect(TodayRecap.of(log, now: at(130), calendar: utc).line == "0 sessions finished · 2h 10m working")
        #expect(TodayRecap.of(SessionLog(), now: at(0), calendar: utc).line == nil)
    }

    @Test func trimsToTwoDaysAndRoundTrips() throws {
        var log = SessionLog()
        _ = log.update([("a", "p", .working)], now: at(-3 * 24 * 60))
        _ = log.update([("a", "p", .idle)], now: at(0))
        #expect(log.events.count == 1)
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("cb-sess-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }
        let file = dir.appendingPathComponent("sessions-today.jsonl")
        try log.save(file)
        #expect(SessionLog.load(file).events == log.events)
    }

    func tempFile() -> (URL, URL) {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("cb-sess-\(UUID().uuidString)")
        return (dir, dir.appendingPathComponent("sessions-today.jsonl"))
    }

    @Test func reloadingWhileWorkingKeepsOneSpan() throws {
        var log = SessionLog()
        _ = log.update([("a", "p", .working)], now: at(0))
        let (dir, file) = tempFile()
        defer { try? FileManager.default.removeItem(at: dir) }
        try log.save(file)
        var reloaded = SessionLog.load(file)
        let added = reloaded.update([("a", "p", .working)], now: at(60))
        #expect(added == false)
        #expect(reloaded.events.count == 1)
        #expect(TodayRecap.of(reloaded, now: at(90), calendar: utc).working == 90 * 60)
    }

    @Test func reloadThenGoneClosesTheSpan() throws {
        var log = SessionLog()
        _ = log.update([("a", "p", .working)], now: at(0))
        let (dir, file) = tempFile()
        defer { try? FileManager.default.removeItem(at: dir) }
        try log.save(file)
        var reloaded = SessionLog.load(file)
        let added = reloaded.update([], now: at(30))
        #expect(added)
        #expect(reloaded.events.last?.working == false && reloaded.events.last?.finished == false)
        #expect(reloaded.events.last?.at == at(30))
        #expect(TodayRecap.of(reloaded, now: at(120), calendar: utc).working == 30 * 60)
    }

    @Test func aSessionDisappearingWhileWorkingStopsCounting() {
        var log = SessionLog()
        _ = log.update([("a", "p", .working)], now: at(0))
        _ = log.update([], now: at(20))
        let r = TodayRecap.of(log, now: at(60), calendar: utc)
        #expect(r.working == 20 * 60 && r.finished == 0)
    }
}

import Foundation
import Testing
@testable import ClaudeBarCore

@Suite struct SessionLogTests {
    var utc: Calendar { var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(identifier: "UTC")!; return c }
    /// 2027-01-15 08:00 UTC.
    let t0 = Date(timeIntervalSince1970: 1_800_000_000)
    func at(_ m: Double) -> Date { t0.addingTimeInterval(m * 60) }
    typealias Sessions = [(key: String, project: String, status: AgentStatus)]
    /// ClaudeBar running steadily: each step's sessions, updated once a minute from its time up to the next step's
    /// (the last step once).
    func play(_ log: inout SessionLog, _ steps: [(Int, Sessions)]) {
        for (i, (start, sessions)) in steps.enumerated() {
            let end = i + 1 < steps.count ? steps[i + 1].0 : start + 1
            for m in start..<end { _ = log.update(sessions, now: at(Double(m))) }
        }
    }

    @Test func spansAndFinishes() {
        var log = SessionLog()
        play(&log, [
            (0, [("a", "claude-bar", .idle)]),
            (10, [("a", "claude-bar", .working)]),
            (40, [("a", "claude-bar", .waiting)]),     // stops working, not finished
            (45, [("a", "claude-bar", .working)]),
            (60, [("a", "claude-bar", .idle), ("b", "turbo", .working)]),
            (70, [("b", "turbo", .ended)]),
        ])
        let r = TodayRecap.of(log, now: at(80), calendar: utc)
        #expect(r.finished == 2)
        #expect(r.working == (30 + 15 + 10) * 60)
        #expect(r.busiest == "claude-bar")
        #expect(r.line == "2 sessions finished · 55m working · busiest: claude-bar")
    }

    @Test func spansAcrossMidnightCountFromMidnight() {
        var log = SessionLog()
        play(&log, [(-9 * 60, [("a", "p", .working)]),   // yesterday 23:00
                    (-7 * 60, [("a", "p", .idle)])])     // today 01:00
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
        _ = log.update([("a", "p", .idle)], now: at(-3 * 24 * 60 + 1))
        _ = log.update([("a", "p", .working)], now: at(-1))
        _ = log.update([("a", "p", .idle)], now: at(0))
        #expect(log.events.map(\.at) == [at(-1), at(0)], "3 days old: trimmed")
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
        // A quick restart (within 2 minutes of the log's last event) continues the span.
        var reloaded = SessionLog.load(file)
        let added = reloaded.update([("a", "p", .working)], now: at(1))
        #expect(added == false)
        #expect(reloaded.events.count == 1)
        play(&reloaded, [(2, [("a", "p", .working)]), (90, [("a", "p", .working)])])
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
        let added = reloaded.update([], now: at(1))
        #expect(added)
        #expect(reloaded.events.last?.working == false && reloaded.events.last?.finished == false)
        #expect(reloaded.events.last?.at == at(1))
        #expect(TodayRecap.of(reloaded, now: at(120), calendar: utc).working == 1 * 60)
    }

    @Test func aSessionDisappearingWhileWorkingStopsCounting() {
        var log = SessionLog()
        play(&log, [(0, [("a", "p", .working)]), (20, [])])
        let r = TodayRecap.of(log, now: at(60), calendar: utc)
        #expect(r.working == 20 * 60 && r.finished == 0)
    }

    /// The Mac slept 18:00 → 09:00 with a session working: the night isn't working time. Its span closes at the last
    /// update before the gap (18:00) and opens again at 09:00.
    @Test func sleepIsNotWorkingTime() {
        var log = SessionLog()
        play(&log, [(9 * 60, [("a", "p", .working)]), (10 * 60, [("a", "p", .working)])])   // 17:00 → 18:00
        _ = log.update([("a", "p", .working)], now: at(25 * 60))                              // 09:00 the next day
        #expect(log.events.map(\.at) == [at(9 * 60), at(10 * 60), at(25 * 60)])
        #expect(log.events.map(\.working) == [true, false, true])
        #expect(log.events[1].finished == false)
        #expect(TodayRecap.of(log, now: at(15 * 60), calendar: utc).working == 60 * 60, "the first day: 17:00 to 18:00")
        #expect(TodayRecap.of(log, now: at(25 * 60 + 30), calendar: utc).working == 30 * 60, "the next day: from 09:00")
        // Up to 2 minutes between updates is no gap.
        var steady = SessionLog()
        _ = steady.update([("a", "p", .working)], now: at(0))
        _ = steady.update([("a", "p", .working)], now: at(2))
        #expect(steady.events.count == 1)
    }

    /// ClaudeBar was off: after a restart the log's last event is the last update; a session still working counts from
    /// the restart, not across the gap.
    @Test func aRestartAfterAGapDoesNotCountTheGap() throws {
        var log = SessionLog()
        _ = log.update([("a", "p", .working)], now: at(9 * 60))     // 17:00
        let (dir, file) = tempFile()
        defer { try? FileManager.default.removeItem(at: dir) }
        try log.save(file)
        var reloaded = SessionLog.load(file)
        let reopened = reloaded.update([("a", "p", .working)], now: at(25 * 60))   // 09:00 the next day
        #expect(reopened)
        #expect(reloaded.events.map(\.at) == [at(9 * 60), at(9 * 60), at(25 * 60)])
        #expect(reloaded.events.map(\.working) == [true, false, true])
        #expect(TodayRecap.of(reloaded, now: at(25 * 60 + 30), calendar: utc).working == 30 * 60)
        // A session that was idle when ClaudeBar stopped: nothing to close.
        var idle = SessionLog()
        _ = idle.update([("b", "p", .working)], now: at(0))
        _ = idle.update([("b", "p", .idle)], now: at(1))
        try idle.save(file)
        var back = SessionLog.load(file)
        let added = back.update([("b", "p", .idle)], now: at(600))
        #expect(added == false)
    }
}

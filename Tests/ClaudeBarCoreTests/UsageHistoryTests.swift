import Foundation
import Testing
@testable import ClaudeBarCore

@Suite struct UsageHistoryTests {
    let t0 = Date(timeIntervalSince1970: 1_800_000_000)
    var utc: Calendar { var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(identifier: "UTC")!; return c }

    func s(_ minutes: Double, _ five: Double?, reset: Double = 300, seven: Double? = 10) -> UsageSample {
        UsageSample(at: t0.addingTimeInterval(minutes * 60), fiveHourPct: five, fiveHourResetsAt: t0.addingTimeInterval(reset * 60),
                    sevenDayPct: seven, sevenDayResetsAt: t0.addingTimeInterval(7 * 86_400))
    }

    @Test func addsOnlyChangesAtMostOncePerMinute() {
        var h = UsageHistory()
        let first = h.add(s(0, 10)), same = h.add(s(5, 10)), later = h.add(s(2, 12)), again = h.add(s(4, 12))
        #expect(first && later)
        #expect(!same && !again, "unchanged")
        #expect(h.samples.map(\.fiveHourPct) == [10, 12])
    }

    /// A change under a minute after the last sample replaces it (it may be the last reading for a while: 100%).
    @Test func aQuickChangeReplacesTheLastSample() {
        var h = UsageHistory()
        _ = h.add(s(0, 90)); _ = h.add(s(2, 98))
        let kept = h.add(s(2.67, 100))
        #expect(kept)
        #expect(h.samples.map(\.fiveHourPct) == [90, 100])
        #expect(h.samples.last?.at == t0.addingTimeInterval(2.67 * 60))
    }

    @Test func trimsToThirtyDays() {
        var h = UsageHistory()
        _ = h.add(s(0, 10))
        _ = h.add(s(31 * 24 * 60, 20, reset: 31 * 24 * 60 + 300))
        #expect(h.samples.count == 1 && h.samples[0].fiveHourPct == 20)
    }

    @Test func savesAndLoadsAndSkipsDamagedLines() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("cb-usage-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }
        let file = dir.appendingPathComponent("usage-history.jsonl")
        var h = UsageHistory()
        _ = h.add(s(0, 10)); _ = h.add(s(2, 12))
        try h.save(file)
        #expect(UsageHistory.load(file) == h)
        try (String(contentsOf: file, encoding: .utf8) + "{not json\n").write(to: file, atomically: true, encoding: .utf8)
        #expect(UsageHistory.load(file).samples.count == 2, "damaged line skipped")
        #expect(UsageHistory.load(dir.appendingPathComponent("missing.jsonl")).samples.isEmpty)
    }

    @Test func daysFollowLocalMidnight() {
        // t0 is 2027-01-15 08:00 UTC.
        var h = UsageHistory()
        _ = h.add(s(-9 * 60, 40, reset: -5 * 60))   // yesterday 23:00
        _ = h.add(s(10, 5))                          // today 08:10
        _ = h.add(s(70, 25))                         // today 09:10
        let now = t0.addingTimeInterval(80 * 60)
        #expect(h.today(now: now, calendar: utc).map(\.fiveHourPct) == [5, 25])
        let highs = h.dailyHighs(days: 7, now: now, calendar: utc)
        #expect(highs.count == 7)
        #expect(highs.last?.high == 25 && highs[5].high == 40 && highs[0].high == nil)
    }

    @Test func limitHitsCountOncePerWindow() {
        var h = UsageHistory()
        _ = h.add(s(0, 98)); _ = h.add(s(2, 100)); _ = h.add(s(4, 100, seven: 11))
        _ = h.add(s(400, 100, reset: 700))
        let hits = h.limitHits(days: 7, now: t0.addingTimeInterval(500 * 60), calendar: utc)
        #expect(hits.map(\.at) == [t0.addingTimeInterval(400 * 60), t0.addingTimeInterval(2 * 60)])
        #expect(hits.allSatisfy { $0.window == .fiveHour })
    }

    @Test func sampleFromUsage() {
        let u = UsageSummary(fiveHourPct: 30, fiveHourResetsAt: t0, sevenDayPct: nil, sevenDayResetsAt: nil, asOf: t0, workingCount: 0)
        #expect(UsageSample(usage: u, at: t0)?.fiveHourPct == 30)
        #expect(UsageSample(usage: UsageSummary(workingCount: 0), at: t0) == nil)
    }
}

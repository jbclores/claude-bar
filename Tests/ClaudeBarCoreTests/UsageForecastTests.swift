import Foundation
import Testing
@testable import ClaudeBarCore

@Suite struct UsageForecastTests {
    let t0 = Date(timeIntervalSince1970: 1_800_000_000)
    let time: (Date) -> String = { d in "T+\(Int(d.timeIntervalSince(Date(timeIntervalSince1970: 1_800_000_000)) / 60))m" }

    func s(_ minutes: Double, _ five: Double, reset: Double = 120, seven: Double = 10, sevenReset: Double = 3 * 24 * 60) -> UsageSample {
        UsageSample(at: t0.addingTimeInterval(minutes * 60), fiveHourPct: five, fiveHourResetsAt: t0.addingTimeInterval(reset * 60),
                    sevenDayPct: seven, sevenDayResetsAt: t0.addingTimeInterval(sevenReset * 60))
    }
    func at(_ minutes: Double) -> Date { t0.addingTimeInterval(minutes * 60) }

    @Test func steadyPaceProjectsToTheReset() throws {
        // +10% over 40 min = 0.25%/min; at 40 min 30%; 80 min left → 30 + 20 = 50%.
        let f = try #require(UsageForecast.of(.fiveHour, history: [s(0, 20), s(20, 25), s(40, 30)], now: at(40)))
        #expect(abs(f.projected - 50) < 0.01 && !f.atRisk)
        #expect(f.line(time: time) == "On pace for about 50% of the 5-hour limit by T+120m")
    }

    @Test func fastPaceReachesTheLimitBeforeTheReset() throws {
        // +30% over 30 min = 1%/min; 70% at 30 min → 100% at 60 min, before the reset at 120.
        let f = try #require(UsageForecast.of(.fiveHour, history: [s(0, 40), s(15, 55), s(30, 70)], now: at(30)))
        #expect(f.atRisk && f.hitAt == at(60) && f.projected == 100)
        #expect(f.line(time: time) == "At this pace you'll reach the 5-hour limit around T+60m")
        #expect(f.warning(time: time) == "At this pace you'll reach your 5-hour limit around T+60m. It resets at T+120m.")
    }

    @Test func tooFewSamplesOrNoRiseMeansNoPace() throws {
        let one = try #require(UsageForecast.of(.fiveHour, history: [s(0, 30)], now: at(5)))
        #expect(one.projected == 30 && !one.atRisk)
        let close = try #require(UsageForecast.of(.fiveHour, history: [s(0, 30), s(5, 35)], now: at(5)))
        #expect(close.projected == 35, "under 10 minutes apart")
        let flat = try #require(UsageForecast.of(.fiveHour, history: [s(0, 30), s(20, 30)], now: at(20)))
        #expect(flat.projected == 30)
    }

    @Test func aResetStartsAFreshWindow() throws {
        // 90% before the reset at 60; after it, 5% then 10%: only the new window counts.
        let h = [s(0, 80, reset: 60), s(30, 90, reset: 60), s(70, 5, reset: 360), s(90, 10, reset: 360)]
        let f = try #require(UsageForecast.of(.fiveHour, history: h, now: at(90)))
        #expect(!f.atRisk && f.resetsAt == at(360))
        // 0.25%/min × 270 min left = 67.5 → 77.5%.
        #expect(abs(f.projected - 77.5) < 0.01)
    }

    @Test func stalePaceIsIgnored() throws {
        // The last rise ended 3 hours ago: nothing in the last hour, so no pace.
        let f = try #require(UsageForecast.of(.fiveHour, history: [s(0, 20, reset: 300), s(20, 40, reset: 300)], now: at(200)))
        #expect(f.projected == 40 && !f.atRisk)
    }

    @Test func roundsToFivePercentAndPicksTheHeadline() throws {
        let f = try #require(UsageForecast.of(.fiveHour, history: [s(0, 20), s(20, 23), s(40, 26)], now: at(40)))
        #expect(f.line(time: time).hasPrefix("On pace for about 40% "), "26 + 0.15×80 = 38 → 40")
        // 7-day at risk wins over a calm 5-hour window.
        let risky = [s(0, 10, seven: 90, sevenReset: 600), s(30, 12, seven: 96, sevenReset: 600)]
        #expect(UsageForecast.headline(history: risky, now: at(30))?.window == .sevenDay)
        #expect(UsageForecast.headline(history: [s(0, 10)], now: at(1))?.window == .fiveHour)
        #expect(UsageForecast.headline(history: [], now: at(1)) == nil)
    }

    @Test func warnsOncePerWindow() throws {
        var w = UsageWarner()
        let f = try #require(UsageForecast.of(.fiveHour, history: [s(0, 40), s(15, 55), s(30, 70)], now: at(30)))
        let first = w.shouldWarn(f), again = w.shouldWarn(f)
        #expect(first)
        #expect(!again, "same window")
        var next = f
        next.resetsAt = at(420)
        let fresh = w.shouldWarn(next)
        #expect(fresh, "a new window")
        var calm = f
        calm.hitAt = nil
        let quiet = w.shouldWarn(calm)
        #expect(!quiet)
    }
}

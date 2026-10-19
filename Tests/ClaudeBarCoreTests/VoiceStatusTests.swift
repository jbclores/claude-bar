import Testing
import Foundation
@testable import ClaudeBarCore

@Suite struct VoiceStatusTests {
    @Test func statusSentences() {
        #expect(VoiceStatus.status(running: ["claude-bar", "x"], needYou: ["claude-bar"], idle: ["pnp-ufdms"])
                == "2 running, 1 needs you: claude-bar. pnp-ufdms idle.")
        #expect(VoiceStatus.status(running: ["a", "b", "c"], needYou: ["a", "b"], idle: [])
                == "3 running, 2 need you: a and b.")
        #expect(VoiceStatus.status(running: [], needYou: [], idle: ["a", "b", "c", "d"]) == "4 others idle.")
        #expect(VoiceStatus.status(running: [], needYou: [], idle: []) == "Nothing is running.")
        #expect(VoiceStatus.status(running: [], needYou: [], idle: ["a"]) == "a idle.")
    }

    @Test func usageSentences() {
        let now = Date(timeIntervalSince1970: 0)
        let f = UsageForecast(window: .fiveHour, projected: 70, hitAt: nil, resetsAt: now)
        let u = UsageSummary(fiveHourPct: 40.4, sevenDayPct: 12, workingCount: 0)
        #expect(VoiceStatus.usage(u, forecast: f, time: { _ in "6:00 PM" })
                == "5-hour at 40%, on pace for about 70% of the 5-hour limit by 6:00 PM. 7-day at 12%.")
        #expect(VoiceStatus.usage(u, forecast: nil, time: { _ in "x" }) == "5-hour at 40%. 7-day at 12%.")
        #expect(VoiceStatus.usage(UsageSummary(workingCount: 0), forecast: nil, time: { _ in "x" })
                == "I don't have your usage yet.")
    }

    @Test func recapSentences() {
        #expect(VoiceStatus.recap(TodayRecap(finished: 4, working: 7800, busiest: "claude-bar"))
                == "4 sessions finished, 2 hours 10 minutes working, busiest: claude-bar.")
        #expect(VoiceStatus.recap(TodayRecap(finished: 1, working: 2700, busiest: nil))
                == "1 session finished, 45 minutes working.")
        #expect(VoiceStatus.recap(TodayRecap(finished: 0, working: 3600, busiest: nil)) == "1 hour working.")
        #expect(VoiceStatus.recap(TodayRecap(finished: 0, working: 60, busiest: nil)) == "1 minute working.")
        #expect(VoiceStatus.recap(TodayRecap(finished: 0, working: 59, busiest: nil)) == "Nothing yet today.")
    }

    @Test func failureSentences() {
        #expect(VoiceStatus.failure("That question changed: check it again") == "That question changed; check it again.")
        #expect(VoiceStatus.failure("Couldn't reach Cat Office.") == "Couldn't reach Cat Office.")
        #expect(VoiceStatus.failure("Couldn't reach Cat Office") == "Couldn't reach Cat Office.")
    }
}

import Foundation
import Testing
@testable import ClaudeBarCore

@Suite struct FormatTests {
    let now = Date(timeIntervalSince1970: 1_791_266_000)

    @Test func percentRounds() {
        #expect(Format.percent(41.6) == "42%")
        #expect(Format.percent(0) == "0%")
    }

    @Test func levels() {
        #expect(UsageLevel(percent: 59.9) == .ok)
        #expect(UsageLevel(percent: 60) == .warn)
        #expect(UsageLevel(percent: 84.9) == .warn)
        #expect(UsageLevel(percent: 85) == .high)
    }

    @Test func ages() {
        #expect(Format.age(now.addingTimeInterval(-30), now: now) == "now")
        #expect(Format.age(now.addingTimeInterval(-5 * 60), now: now) == "5m ago")
        #expect(Format.age(now.addingTimeInterval(-3 * 3600 - 59), now: now) == "3h ago")
        #expect(Format.age(now.addingTimeInterval(-2 * 86_400), now: now) == "2d ago")
        #expect(Format.age(now.addingTimeInterval(60), now: now) == "now")
    }

    @Test func durations() {
        #expect(Format.duration(30) == "<1m")
        #expect(Format.duration(125) == "2m")
        #expect(Format.duration(7200) == "2h")
        #expect(Format.duration(3 * 86_400) == "3d")
    }

    @Test func resets() {
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = TimeZone(identifier: "UTC")!
        #expect(Format.resets(now.addingTimeInterval(2 * 3600 + 14 * 60), now: now, calendar: utc) == "resets in 2h 14m")
        #expect(Format.resets(now.addingTimeInterval(14 * 60 + 5), now: now, calendar: utc) == "resets in 15m")
        #expect(Format.resets(now.addingTimeInterval(-5), now: now, calendar: utc) == "resets now")
        let friday = ISO8601DateFormatter().date(from: "2026-10-09T01:00:00Z")!
        #expect(Format.resets(friday, now: ISO8601DateFormatter().date(from: "2026-10-06T12:00:00Z")!, calendar: utc) == "resets Fri 1:00 AM")
    }
}

@Suite struct ModelNameTests {
    @Test func prettifiesModelIds() {
        #expect(Format.modelName("claude-opus-5-5") == "Opus 5.5")
        #expect(Format.modelName("claude-sonnet-5-5[1m]") == "Sonnet 5.5")
        #expect(Format.modelName("claude-haiku-4-5-20251001") == "Haiku 4.5")
        #expect(Format.modelName("claude-fable-5-1") == "Fable 5.1")
        #expect(Format.modelName("Opus 5.5") == "Opus 5.5")
        #expect(Format.modelName("some-other-model") == "some-other-model")
    }
}

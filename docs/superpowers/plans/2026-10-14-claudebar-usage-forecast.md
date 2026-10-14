# ClaudeBar Usage Forecast, Warnings and History Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** ClaudeBar remembers usage over time and shows a forecast line, one warning per window, today's sparkline and a 7-day chart.

**Architecture:** Two pure Core units — `UsageHistory` (samples, file, trim, days) and `UsageForecast` (pace,
projection, line, warn-once) — fully unit-tested. `AppState` records each usage reading into the log, publishes the
forecast and posts the warning through the existing `Notifier`. The usage header view draws the line, the sparkline
and the fold-out week chart.

**Tech Stack:** Swift 6 toolchain (language mode 5), SwiftPM, Swift Testing, SwiftUI, macOS 14+.

**Spec:** `docs/superpowers/specs/2026-10-14-claudebar-usage-forecast-design.md`

## Global Constraints

- Log file: `~/.claude/claude-bar/usage-history.jsonl`; one JSON sample per line; last 30 days kept; a damaged line is skipped.
- A sample is added only when the reading changed (any of the four values, or `asOf`), at most one per minute.
- Forecast pace: rise over the last 60 minutes of samples in the current window; needs ≥ 2 samples ≥ 10 minutes apart and a rise.
- Line wording, exactly: grey "On pace for about 55% of the 5-hour limit by 5:40 PM" (rounded to 5%); amber "At this pace you'll reach the 5-hour limit around 3:40 PM"; 7-day: "the 7-day limit".
- Warning, exactly: title "Usage", body "At this pace you'll reach your 5-hour limit around 3:40 PM. It resets at 5:00 PM."; once per window (by `resetsAt`).
- Setting: Settings → General "Warn before I hit a usage limit", config key `usageWarnings`, on by default.
- Tests never touch the real `~/.claude`, `~/.config/claude-bar`, or the installed app; temp folders only.
- Sentence case, plain words; match surrounding code style (doc comments on types and non-obvious functions).

## Review Focus

1. A 5-hour reset mid-hour (the percentage drops): the pace must use only samples after the reset — no negative pace, no "reach the limit" from old samples. (Task 2 test `aResetStartsAFreshWindow`.)
2. The status line silent for hours (no new samples): the line falls back to the current percentage at the reset, never extrapolates from a stale pace. (Task 2 test `stalePaceIsIgnored`.)
3. The clock passing midnight: today's sparkline starts empty and the week chart moves a day. (Task 1 test `daysFollowLocalMidnight`.)
4. A corrupt or half-written log line: skipped; the log keeps working. (Task 1 test `damagedLinesAreSkipped`.)
5. 100% reached exactly at a sample: counted once as "limit reached", not per sample. (Task 1 test `limitHitsCountOncePerWindow`.)

---

## File Structure

| File | Responsibility |
|---|---|
| `Sources/ClaudeBarCore/UsageHistory.swift` (new) | `UsageSample`, `UsageHistory` (add, load, save, trim, today, daily highs, limit hits) |
| `Sources/ClaudeBarCore/UsageForecast.swift` (new) | `UsageForecast` (pace, projection, hit time, line, tone), `UsageWarner` |
| `Sources/ClaudeBarCore/Config.swift` | `usageWarnings` setting |
| `Sources/ClaudeBar/Notifier.swift` | `post(title:body:)` for the warning |
| `Sources/ClaudeBar/AppState.swift` | Record samples, publish history + forecast, warn |
| `Sources/ClaudeBar/Views/UsageHistoryViews.swift` (new) | Forecast line, sparkline, week chart |
| `Sources/ClaudeBar/Views/DropdownView.swift` | Usage header uses them; Settings switch |
| `Resources/Help/guide.html`, `Resources/Help/changes.html` | Describe the forecast and the log file |
| Tests: `UsageHistoryTests.swift`, `UsageForecastTests.swift` (new), `ConfigTests.swift` | Core tests |

---

### Task 1: The usage log (`UsageHistory`)

**Files:**
- Create: `Sources/ClaudeBarCore/UsageHistory.swift`
- Test: `Tests/ClaudeBarCoreTests/UsageHistoryTests.swift`

**Interfaces:**
- Produces:
  - `public struct UsageSample: Codable, Equatable, Sendable { at: Date; fiveHourPct: Double?; fiveHourResetsAt: Date?; sevenDayPct: Double?; sevenDayResetsAt: Date? }` with `init(at:fiveHourPct:fiveHourResetsAt:sevenDayPct:sevenDayResetsAt:)` and `init?(usage: UsageSummary, at: Date)` (nil when both percentages are nil).
  - `public struct UsageHistory: Equatable, Sendable { public private(set) var samples: [UsageSample] }`
  - `public static let keepFor: TimeInterval = 30 * 86_400`
  - `public mutating func add(_ s: UsageSample) -> Bool` — true when added (changed and ≥ 60 s after the last), trims to `keepFor` before `s.at`.
  - `public static func load(_ file: URL) -> UsageHistory`, `public func save(_ file: URL) throws`
  - `public static var defaultFile: URL` (`Paths.home/.claude/claude-bar/usage-history.jsonl`)
  - `public func today(now: Date, calendar: Calendar) -> [UsageSample]`
  - `public func dailyHighs(days: Int, now: Date, calendar: Calendar) -> [(day: Date, high: Double?)]` (oldest first, today last; `high` = max 5-hour % that day)
  - `public func limitHits(days: Int, now: Date, calendar: Calendar) -> [(at: Date, window: UsageWindow)]` (newest first; one per window reset)
  - `public enum UsageWindow: String, Sendable { case fiveHour, sevenDay }`

- [ ] **Step 1: Write the failing tests**

```swift
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
        #expect(h.add(s(0, 10)))
        #expect(!h.add(s(5, 10)), "unchanged")
        #expect(!h.add(s(0.5, 12)), "under a minute after the last")
        #expect(h.add(s(2, 12)))
        #expect(h.samples.map(\.fiveHourPct) == [10, 12])
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
```

- [ ] **Step 2: Run to verify they fail**

Run: `swift test --filter UsageHistoryTests`
Expected: FAIL to compile ("cannot find 'UsageHistory' in scope").

- [ ] **Step 3: Implement**

```swift
import Foundation

/// Which usage limit: the 5-hour or the 7-day window.
public enum UsageWindow: String, Sendable { case fiveHour, sevenDay }

/// One usage reading: the status line's 5-hour and 7-day percentages and when each resets.
public struct UsageSample: Codable, Equatable, Sendable {
    public var at: Date
    public var fiveHourPct: Double?
    public var fiveHourResetsAt: Date?
    public var sevenDayPct: Double?
    public var sevenDayResetsAt: Date?

    public init(at: Date, fiveHourPct: Double?, fiveHourResetsAt: Date?, sevenDayPct: Double?, sevenDayResetsAt: Date?) {
        self.at = at; self.fiveHourPct = fiveHourPct; self.fiveHourResetsAt = fiveHourResetsAt
        self.sevenDayPct = sevenDayPct; self.sevenDayResetsAt = sevenDayResetsAt
    }

    /// The reading ClaudeBar shows now, taken `at` (nil without any percentage).
    public init?(usage: UsageSummary, at: Date) {
        guard usage.fiveHourPct != nil || usage.sevenDayPct != nil else { return nil }
        self.init(at: at, fiveHourPct: usage.fiveHourPct, fiveHourResetsAt: usage.fiveHourResetsAt,
                  sevenDayPct: usage.sevenDayPct, sevenDayResetsAt: usage.sevenDayResetsAt)
    }

    /// The same reading, whenever taken.
    func sameReading(_ o: UsageSample) -> Bool {
        fiveHourPct == o.fiveHourPct && fiveHourResetsAt == o.fiveHourResetsAt
            && sevenDayPct == o.sevenDayPct && sevenDayResetsAt == o.sevenDayResetsAt
    }
}

/// ClaudeBar's usage log (~/.claude/claude-bar/usage-history.jsonl): a sample each time the reading changes, at most
/// one a minute, the last 30 days.
public struct UsageHistory: Equatable, Sendable {
    public private(set) var samples: [UsageSample] = []
    public static let keepFor: TimeInterval = 30 * 86_400
    static let minGap: TimeInterval = 60

    public init(samples: [UsageSample] = []) { self.samples = samples }

    public static var defaultFile: URL { Paths.home.appendingPathComponent(".claude/claude-bar/usage-history.jsonl") }

    /// Adds `s` when the reading changed and a minute has passed since the last sample; drops samples over 30 days old.
    @discardableResult
    public mutating func add(_ s: UsageSample) -> Bool {
        if let last = samples.last, last.sameReading(s) || s.at.timeIntervalSince(last.at) < Self.minGap { return false }
        samples.append(s)
        samples.removeAll { s.at.timeIntervalSince($0.at) > Self.keepFor }
        return true
    }

    public static func load(_ file: URL) -> UsageHistory {
        guard let text = try? String(contentsOf: file, encoding: .utf8) else { return UsageHistory() }
        let decoder = Self.decoder
        return UsageHistory(samples: text.split(separator: "\n").compactMap { try? decoder.decode(UsageSample.self, from: Data($0.utf8)) })
    }

    public func save(_ file: URL) throws {
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = Self.encoder
        let lines = try samples.map { String(decoding: try encoder.encode($0), as: UTF8.self) }
        try (lines.joined(separator: "\n") + "\n").write(to: file, atomically: true, encoding: .utf8)
    }

    static var encoder: JSONEncoder { let e = JSONEncoder(); e.dateEncodingStrategy = .millisecondsSince1970; e.outputFormatting = .sortedKeys; return e }
    static var decoder: JSONDecoder { let d = JSONDecoder(); d.dateDecodingStrategy = .millisecondsSince1970; return d }

    /// Today's samples (since local midnight).
    public func today(now: Date, calendar: Calendar) -> [UsageSample] {
        let start = calendar.startOfDay(for: now)
        return samples.filter { $0.at >= start && $0.at <= now }
    }

    /// The highest 5-hour percentage of each of the last `days` days, oldest first, today last (nil: no samples).
    public func dailyHighs(days: Int, now: Date, calendar: Calendar) -> [(day: Date, high: Double?)] {
        let today = calendar.startOfDay(for: now)
        return (0..<days).reversed().map { back in
            let day = calendar.date(byAdding: .day, value: -back, to: today)!
            let next = calendar.date(byAdding: .day, value: 1, to: day)!
            let highs = samples.filter { $0.at >= day && $0.at < next }.compactMap(\.fiveHourPct)
            return (day, highs.max())
        }
    }

    /// When a limit was reached (a sample at 100%) in the last `days` days: the first such sample of each window
    /// (one per reset), newest first.
    public func limitHits(days: Int, now: Date, calendar: Calendar) -> [(at: Date, window: UsageWindow)] {
        let from = calendar.date(byAdding: .day, value: -(days - 1), to: calendar.startOfDay(for: now))!
        var seen = Set<String>(), hits: [(at: Date, window: UsageWindow)] = []
        for s in samples where s.at >= from && s.at <= now {
            for (window, pct, reset) in [(UsageWindow.fiveHour, s.fiveHourPct, s.fiveHourResetsAt), (.sevenDay, s.sevenDayPct, s.sevenDayResetsAt)] {
                guard let pct, pct >= 100 else { continue }
                if seen.insert("\(window.rawValue)|\(reset?.timeIntervalSince1970 ?? 0)").inserted { hits.append((s.at, window)) }
            }
        }
        return hits.reversed()
    }
}
```

- [ ] **Step 4: Run to verify they pass**

Run: `swift test --filter UsageHistoryTests` — Expected: PASS (6 tests). Then `swift test` — Expected: all pass.

- [ ] **Step 5: Commit**

```bash
git add Sources/ClaudeBarCore/UsageHistory.swift Tests/ClaudeBarCoreTests/UsageHistoryTests.swift
git commit -m "feat: ClaudeBar keeps a usage log (each change, at most one a minute, 30 days)"
```

### Task 2: The forecast and warn-once (`UsageForecast`, `UsageWarner`)

**Files:**
- Create: `Sources/ClaudeBarCore/UsageForecast.swift`
- Test: `Tests/ClaudeBarCoreTests/UsageForecastTests.swift`

**Interfaces:**
- Consumes: `UsageSample`, `UsageHistory`, `UsageWindow` (Task 1).
- Produces:
  - `public struct UsageForecast: Equatable, Sendable { window: UsageWindow; projected: Double; hitAt: Date?; resetsAt: Date; atRisk: Bool { hitAt != nil } }`
  - `public static func of(_ window: UsageWindow, history: [UsageSample], now: Date) -> UsageForecast?`
  - `public static func headline(history: [UsageSample], now: Date) -> UsageForecast?` (the 7-day one at risk, else the 5-hour at risk, else the 5-hour one, else the 7-day one)
  - `public func line(time: (Date) -> String) -> String`
  - `public func warning(time: (Date) -> String) -> String`
  - `public struct UsageWarner: Sendable { public mutating func shouldWarn(_ f: UsageForecast) -> Bool }` (once per `window` + `resetsAt`)

- [ ] **Step 1: Write the failing tests**

```swift
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
        #expect(w.shouldWarn(f))
        #expect(!w.shouldWarn(f), "same window")
        var next = f
        next.resetsAt = at(420)
        #expect(w.shouldWarn(next), "a new window")
        var calm = f
        calm.hitAt = nil
        #expect(!w.shouldWarn(calm))
    }
}
```

- [ ] **Step 2: Run to verify they fail**

Run: `swift test --filter UsageForecastTests` — Expected: FAIL to compile ("cannot find 'UsageForecast' in scope").

- [ ] **Step 3: Implement**

```swift
import Foundation

/// Where a usage limit is heading: the percentage at its reset if the last hour's pace holds, and when it reaches 100%
/// if that comes before the reset.
public struct UsageForecast: Equatable, Sendable {
    public var window: UsageWindow
    public var projected: Double
    public var hitAt: Date?
    public var resetsAt: Date
    public var atRisk: Bool { hitAt != nil }

    /// The pace counts the last hour of samples, at least two of them 10 minutes apart, with a rise.
    static let paceSpan: TimeInterval = 3600
    static let minSpan: TimeInterval = 600

    /// `window`'s forecast from `history` (samples oldest first): only samples in the current window (its latest
    /// resetsAt) count. Nil without a current reading and reset.
    public static func of(_ window: UsageWindow, history: [UsageSample], now: Date) -> UsageForecast? {
        let read = { (s: UsageSample) -> (Date, Double, Date)? in
            switch window {
            case .fiveHour: s.fiveHourPct.flatMap { p in s.fiveHourResetsAt.map { (s.at, p, $0) } }
            case .sevenDay: s.sevenDayPct.flatMap { p in s.sevenDayResetsAt.map { (s.at, p, $0) } }
            }
        }
        let points = history.compactMap(read)
        guard let last = points.last, last.2 > now else { return nil }
        let reset = last.2
        let current = points.filter { $0.2 == reset && $0.0 >= now.addingTimeInterval(-paceSpan) && $0.0 <= now }
        var pace = 0.0 // percent per second
        if let first = current.first, let end = current.last, end.0.timeIntervalSince(first.0) >= minSpan, end.1 > first.1 {
            pace = (end.1 - first.1) / end.0.timeIntervalSince(first.0)
        }
        let left = reset.timeIntervalSince(now)
        let projected = min(100, last.1 + pace * left)
        var hit: Date?
        if pace > 0, last.1 < 100 {
            let toFull = (100 - last.1) / pace
            if toFull < left { hit = now.addingTimeInterval(toFull) }
        } else if last.1 >= 100 {
            hit = now
        }
        return UsageForecast(window: window, projected: projected, hitAt: hit, resetsAt: reset)
    }

    /// The line under the bars: the 7-day limit at risk first, then the 5-hour one at risk, else the 5-hour pace.
    public static func headline(history: [UsageSample], now: Date) -> UsageForecast? {
        let five = of(.fiveHour, history: history, now: now), seven = of(.sevenDay, history: history, now: now)
        if let seven, seven.atRisk { return seven }
        if let five, five.atRisk { return five }
        return five ?? seven
    }

    private var name: String { window == .fiveHour ? "5-hour" : "7-day" }

    /// "On pace for about 55% of the 5-hour limit by 5:40 PM", or at risk "At this pace you'll reach the 5-hour limit
    /// around 3:40 PM".
    public func line(time: (Date) -> String) -> String {
        if let hitAt { return "At this pace you'll reach the \(name) limit around \(time(hitAt))" }
        let rounded = Int((projected / 5).rounded()) * 5
        return "On pace for about \(rounded)% of the \(name) limit by \(time(resetsAt))"
    }

    /// The notification's text.
    public func warning(time: (Date) -> String) -> String {
        "At this pace you'll reach your \(name) limit around \(time(hitAt ?? resetsAt)). It resets at \(time(resetsAt))."
    }
}

/// Warns once per usage window: the first forecast at risk for a window and reset, never again for that one.
public struct UsageWarner: Sendable {
    private var warned = Set<String>()
    public init() {}

    public mutating func shouldWarn(_ f: UsageForecast) -> Bool {
        guard f.atRisk else { return false }
        return warned.insert("\(f.window.rawValue)|\(f.resetsAt.timeIntervalSince1970)").inserted
    }
}
```

- [ ] **Step 4: Run to verify they pass**

Run: `swift test --filter UsageForecastTests` — Expected: PASS (7 tests). Then `swift test` — Expected: all pass.

- [ ] **Step 5: Commit**

```bash
git add Sources/ClaudeBarCore/UsageForecast.swift Tests/ClaudeBarCoreTests/UsageForecastTests.swift
git commit -m "feat: usage forecast (last hour's pace, per window) and warn once per window"
```

### Task 3: The setting, recording, and the warning (app glue)

**Files:**
- Modify: `Sources/ClaudeBarCore/Config.swift` (field `usageWarnings`, parse `root["usageWarnings"]`)
- Modify: `Sources/ClaudeBar/Notifier.swift` (add `post(title:body:)`)
- Modify: `Sources/ClaudeBar/AppState.swift`
- Test: `Tests/ClaudeBarCoreTests/ConfigTests.swift`

**Interfaces:**
- Consumes: `UsageHistory`, `UsageSample`, `UsageForecast`, `UsageWarner`.
- Produces (AppState): `@Published private(set) var usageHistory: UsageHistory`; `var usageForecast: UsageForecast?` (headline at `Date()`); `func setUsageWarnings(_ on: Bool)`; `Config.usageWarnings: Bool` (default true).

- [ ] **Step 1: Failing config test** — in `ConfigTests.swift` add:

```swift
@Test func usageWarningsDefaultOnAndCanBeTurnedOff() throws {
    #expect(Config.empty.usageWarnings)
    let off = try #require(Config.parse(Data(#"{"projects":[],"usageWarnings":false}"#.utf8)))
    #expect(!off.usageWarnings)
}
```

(Use the file's existing parse entry point; if it is named differently, call that one — check the top of `ConfigTests.swift`.)

- [ ] **Step 2:** `swift test --filter ConfigTests` — Expected: FAIL ("no member 'usageWarnings'").
- [ ] **Step 3: Implement**
  - `Config`: `public var usageWarnings = true`; in parsing next to `notifications`: `if let w = root["usageWarnings"] as? Bool { config.usageWarnings = w }`.
  - `Notifier`: add

```swift
    /// A plain notification (the usage warning): same permission and fallback as a cat finishing.
    func post(title: String, body: String) {
        let fallback = { @Sendable in Self.osascript(title, body) }
        guard Bundle.main.bundleIdentifier != nil else { return fallback() }
        let center = UNUserNotificationCenter.current()
        center.delegate = self
        center.requestAuthorization(options: [.alert, .sound]) { granted, error in
            if error != nil { return fallback() }
            guard granted else { return }
            let content = UNMutableNotificationContent()
            content.title = title
            content.body = body
            center.add(UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)) { error in
                if error != nil { fallback() }
            }
        }
    }
```

  - `AppState`:

```swift
    /// ClaudeBar's usage log; renders read CLAUDEBAR_RENDER_USAGE_HISTORY=<jsonl file> instead (never written).
    @Published private(set) var usageHistory = UsageHistory()
    private var usageWarner = UsageWarner()
    private var usageHistoryLoaded = false

    /// The line under the usage bars.
    var usageForecast: UsageForecast? { UsageForecast.headline(history: usageHistory.samples, now: Date()) }

    func setUsageWarnings(_ on: Bool) { setSetting(on, at: ["usageWarnings"]) }

    /// Notes the usage reading in the log (on change, at most once a minute), and warns once per window when the pace
    /// reaches a limit before its reset.
    private func recordUsage(_ usage: UsageSummary) {
        if !usageHistoryLoaded {
            usageHistoryLoaded = true
            if !sideEffects, let file = ProcessInfo.processInfo.environment["CLAUDEBAR_RENDER_USAGE_HISTORY"] {
                usageHistory = UsageHistory.load(URL(fileURLWithPath: file))
                return
            }
            usageHistory = UsageHistory.load(UsageHistory.defaultFile)
        }
        guard sideEffects else { return }
        let now = Date()
        if let sample = UsageSample(usage: usage, at: usage.asOf ?? now), usageHistory.add(sample) {
            try? usageHistory.save(UsageHistory.defaultFile)
        }
        if settings.usageWarnings, let f = usageForecast, usageWarner.shouldWarn(f) {
            notifier.post(title: "Usage", body: f.warning(time: Self.usageTime))
        }
    }

    /// "3:40 PM" today, else "Fri 2:00 PM".
    static func usageTime(_ d: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = Calendar.current.isDateInToday(d) ? "h:mm a" : "EEE h:mm a"
        return f.string(from: d)
    }
```

  Call `recordUsage(output.usage)` where `recompute()` assigns the new `output` (right after it), so every refresh feeds the log.
- [ ] **Step 4:** `swift test` — Expected: all pass. `swift build` — no errors.
- [ ] **Step 5: Commit** — `git commit -am "feat: record usage, warn once per window before a limit (Settings switch)"`

### Task 4: The views (forecast line, sparkline, week chart, switch, guide)

**Files:**
- Create: `Sources/ClaudeBar/Views/UsageHistoryViews.swift`
- Modify: `Sources/ClaudeBar/Views/DropdownView.swift` (`DropdownHeader` passes state; `UsageHeader` adds the views; Settings switch)
- Modify: `Resources/Help/guide.html` (Menu bar / usage section), `Resources/Help/changes.html` (the log file under `~/.claude/claude-bar/`)

**Interfaces:**
- Consumes: `AppState.usageHistory`, `AppState.usageForecast`, `AppState.usageTime(_:)`, `UsageHistory.today/dailyHighs/limitHits`.

- [ ] **Step 1: Views** — `UsageHistoryViews.swift`:

```swift
import ClaudeBarCore
import SwiftUI

/// The quiet line under the usage bars: grey "On pace for about 55% …", amber when a limit comes before its reset.
struct UsageForecastLine: View {
    let forecast: UsageForecast

    var body: some View {
        Text(forecast.line(time: AppState.usageTime))
            .font(.caption)
            .foregroundStyle(forecast.atRisk ? Theme.waiting : Theme.secondaryText)
            .lineLimit(1)
    }
}

/// Today's 5-hour usage as a thin step line, 0–100%.
struct UsageSparkline: View {
    let samples: [UsageSample]

    var body: some View {
        GeometryReader { geo in
            let start = Calendar.current.startOfDay(for: Date()).timeIntervalSince1970, span = 86_400.0
            Path { p in
                var last: CGPoint?
                for s in samples {
                    guard let pct = s.fiveHourPct else { continue }
                    let x = geo.size.width * CGFloat((s.at.timeIntervalSince1970 - start) / span)
                    let y = geo.size.height * CGFloat(1 - min(100, pct) / 100)
                    if let l = last { p.addLine(to: CGPoint(x: x, y: l.y)); p.addLine(to: CGPoint(x: x, y: y)) } else { p.move(to: CGPoint(x: x, y: y)) }
                    last = CGPoint(x: x, y: y)
                }
                if let l = last { p.addLine(to: CGPoint(x: geo.size.width * CGFloat((Date().timeIntervalSince1970 - start) / span), y: l.y)) }
            }
            .stroke(Theme.working, lineWidth: 1.5)
        }
        .frame(height: 14)
        .accessibilityLabel("Today's 5-hour usage")
    }
}

/// The last 7 days: each day's highest 5-hour use, and when a limit was reached.
struct UsageWeekChart: View {
    let history: UsageHistory

    var body: some View {
        let now = Date(), cal = Calendar.current
        let days = history.dailyHighs(days: 7, now: now, calendar: cal)
        VStack(alignment: .leading, spacing: 6) {
            Text("Highest 5-hour use each day").font(.caption).foregroundStyle(Theme.secondaryText)
            HStack(alignment: .bottom, spacing: 10) {
                ForEach(days, id: \.day) { d in
                    VStack(spacing: 3) {
                        RoundedRectangle(cornerRadius: 2)
                            .fill((d.high ?? 0) >= 100 ? Theme.waiting : Theme.working)
                            .frame(width: 22, height: max(2, 48 * CGFloat((d.high ?? 0) / 100)))
                            .opacity(d.high == nil ? 0 : 1)
                        Text(cal.isDateInToday(d.day) ? "Today" : d.day.formatted(.dateTime.weekday(.abbreviated)))
                            .font(.caption2).foregroundStyle(Theme.secondaryText)
                    }
                    .frame(maxWidth: .infinity)
                    .help(d.high.map { "\(Int($0))%" } ?? "No use")
                }
            }
            .frame(height: 66, alignment: .bottom)
            ForEach(Array(history.limitHits(days: 7, now: now, calendar: cal).prefix(3).enumerated()), id: \.offset) { _, hit in
                Text("\(hit.window == .fiveHour ? "Limit" : "7-day limit") reached: \(AppState.usageTime(hit.at))")
                    .font(.caption).foregroundStyle(Theme.waiting)
            }
        }
        .padding(8)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(0.05)))
    }
}
```

- [ ] **Step 2: Header** — in `DropdownHeader` replace `UsageHeader(usage: state.output.usage)` with `UsageHeader(usage: state.output.usage, history: state.usageHistory, forecast: state.usageForecast)`. In `UsageHeader` add `let history: UsageHistory`, `let forecast: UsageForecast?`, `@State private var showWeek = false`, and after the 7d row:

```swift
            let today = history.today(now: Date(), calendar: .current)
            if today.count >= 2 { UsageSparkline(samples: today) }
            if let forecast { UsageForecastLine(forecast: forecast) }
            if showWeek { UsageWeekChart(history: history) }
```

  Make the VStack tappable: `.contentShape(Rectangle()).onTapGesture { showWeek.toggle() }` and `.help(showWeek ? "Hide this week's usage" : "Show this week's usage")`. Folded each opening: `.onAppear { showWeek = false }`.
- [ ] **Step 3: Settings switch** — under "Notify when a cat finishes": `setting("Warn before I hit a usage limit", state.settings.usageWarnings) { state.setUsageWarnings($0) }`.
- [ ] **Step 4: Guide and changes page** — guide (usage section): "Under the bars, a quiet line says where your pace leads; it turns amber when you'd reach a limit before it resets, and ClaudeBar warns you once. Click the usage area to see the last 7 days." changes.html, in the `~/.claude/claude-bar/` row: add "and `usage-history.jsonl`, its usage log (30 days)".
- [ ] **Step 5: Renders** — make a sample log in /tmp (a heavy day today and four earlier days, one hit at 100%), then:

```bash
scripts/build.sh
CLAUDEBAR_RENDER_USAGE_HISTORY=/tmp/usage-sample.jsonl build/ClaudeBar.app/Contents/MacOS/ClaudeBar --render-dropdown /tmp/usage-dark.png projects
CLAUDEBAR_RENDER_LIGHT=1 CLAUDEBAR_RENDER_USAGE_HISTORY=/tmp/usage-sample.jsonl build/ClaudeBar.app/Contents/MacOS/ClaudeBar --render-dropdown /tmp/usage-light.png projects
```

  Read the PNGs: forecast line present, sparkline visible. For the week chart add a render-only `CLAUDEBAR_RENDER_USAGE_WEEK=1` that starts `showWeek` true, and render once more.
- [ ] **Step 6:** `swift test`, the click tests (`--test-tabs`, `--test-zoom`, `--test-setup`, `--test-undo`, `CLAUDEBAR_NO_DATA=1 --test-start`) — all pass.
- [ ] **Step 7: Commit** — `git commit -am "feat: forecast line, today's sparkline and the week chart under the usage bars"`

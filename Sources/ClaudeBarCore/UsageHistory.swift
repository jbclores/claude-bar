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

    /// Adds `s` when the reading changed: a new sample a minute or more after the last, else in place of the last (a
    /// quick change may be the last reading for a while, e.g. 100%). Drops samples over 30 days old. True when stored.
    @discardableResult
    public mutating func add(_ s: UsageSample) -> Bool {
        if let last = samples.last {
            if last.sameReading(s) { return false }
            if s.at.timeIntervalSince(last.at) < Self.minGap { samples.removeLast() }
        }
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

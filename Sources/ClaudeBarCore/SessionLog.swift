import Foundation

/// A session starting or stopping work (finished: it went idle or ended, not waiting).
public struct SessionEvent: Codable, Equatable, Sendable {
    public var at: Date
    public var key: String
    public var project: String
    public var working: Bool
    public var finished: Bool
}

/// ClaudeBar's log of sessions starting and stopping work (~/.claude/claude-bar/sessions-today.jsonl), 2 days kept:
/// enough for today's recap across midnight.
public struct SessionLog: Equatable, Sendable {
    public private(set) var events: [SessionEvent] = []
    private var last: [String: (status: AgentStatus, project: String)] = [:]
    /// When ClaudeBar last watched: `update` last ran, or after a restart the later of the saved heartbeat and the
    /// log's last event (the log is only saved when an event is added, so the heartbeat is kept apart).
    public private(set) var lastUpdate: Date?
    static let keepFor: TimeInterval = 2 * 86_400
    /// Longer than this between updates (the Mac slept, ClaudeBar was off): nobody was seen working in between.
    /// Longer than this between updates counts as ClaudeBar not watching (off, or a sleep it didn't hear about). Long
    /// enough that App Nap slowing ClaudeBar's timer doesn't split a span; sleep itself is caught by `pause(at:)`.
    static let maxGap: TimeInterval = 15 * 60

    /// Keys whose last event is "started working" are seeded as working, so a restart continues their span (closed at
    /// the last time ClaudeBar watched instead when the restart comes after a gap; see `update`).
    public init(events: [SessionEvent] = [], lastUpdate: Date? = nil) {
        self.events = events
        self.lastUpdate = [lastUpdate, events.map(\.at).max()].compactMap { $0 }.max()
        var lastEvent: [String: SessionEvent] = [:]
        for e in events { lastEvent[e.key] = e }
        for (key, e) in lastEvent where e.working { last[key] = (.working, e.project) }
    }
    public static func == (a: SessionLog, b: SessionLog) -> Bool { a.events == b.events }

    public static var defaultFile: URL { Paths.home.appendingPathComponent(".claude/claude-bar/sessions-today.jsonl") }

    /// Notes who started or stopped working since the last update. True when events were added. After a gap (sleep,
    /// ClaudeBar off) the sessions working at the last update stop there (not finished); one still working starts again
    /// now, so the gap never counts as working time.
    /// The Mac is going to sleep (or ClaudeBar stops watching) at `time`: the sessions working stop there (not finished);
    /// one still working when the next update comes starts again then.
    public mutating func pause(at time: Date) {
        for key in last.keys.sorted() where last[key]?.status == .working {
            events.append(SessionEvent(at: time, key: key, project: last[key]!.project, working: false, finished: false))
            last[key] = nil
        }
        lastUpdate = time
    }

    @discardableResult
    public mutating func update(_ sessions: [(key: String, project: String, status: AgentStatus)], now: Date) -> Bool {
        let before = events.count
        if let lastUpdate, now.timeIntervalSince(lastUpdate) > Self.maxGap {
            for key in last.keys.sorted() where last[key]?.status == .working {
                events.append(SessionEvent(at: lastUpdate, key: key, project: last[key]!.project, working: false, finished: false))
                last[key] = nil
            }
        }
        lastUpdate = now
        var seen = Set<String>()
        for s in sessions {
            seen.insert(s.key)
            let was = last[s.key]?.status
            let working = s.status == .working
            if working, was != .working {
                events.append(SessionEvent(at: now, key: s.key, project: s.project, working: true, finished: false))
            } else if !working, was == .working {
                events.append(SessionEvent(at: now, key: s.key, project: s.project, working: false,
                                           finished: s.status == .idle || s.status == .ended))
            }
            last[s.key] = (s.status, s.project)
        }
        for (key, info) in last where !seen.contains(key) {
            if info.status == .working {
                events.append(SessionEvent(at: now, key: key, project: info.project, working: false, finished: false))
            }
            last[key] = nil
        }
        events.removeAll { now.timeIntervalSince($0.at) > Self.keepFor }
        return events.count != before
    }

    public static func load(_ file: URL, lastUpdate: Date? = nil) -> SessionLog {
        guard let data = try? Data(contentsOf: file) else { return SessionLog(lastUpdate: lastUpdate) }
        let d = JSONDecoder(); d.dateDecodingStrategy = .millisecondsSince1970
        return SessionLog(events: data.split(separator: UInt8(ascii: "\n")).compactMap { try? d.decode(SessionEvent.self, from: Data($0)) },
                          lastUpdate: lastUpdate)
    }

    public func save(_ file: URL) throws {
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        let e = JSONEncoder(); e.dateEncodingStrategy = .millisecondsSince1970; e.outputFormatting = .sortedKeys
        let lines = try events.map { String(decoding: try e.encode($0), as: UTF8.self) }
        try (lines.joined(separator: "\n") + "\n").write(to: file, atomically: true, encoding: .utf8)
    }
}

/// Today so far: sessions that finished, time spent working (since midnight; an open span counts to now), and the
/// project with the most of it.
public struct TodayRecap: Equatable, Sendable {
    public var finished: Int
    public var working: TimeInterval
    public var busiest: String?

    public static func of(_ log: SessionLog, now: Date, calendar: Calendar) -> TodayRecap {
        let midnight = calendar.startOfDay(for: now)
        var open: [String: (Date, String)] = [:], byProject: [String: TimeInterval] = [:], finished = 0
        func close(_ key: String, at end: Date) {
            guard let (start, project) = open.removeValue(forKey: key) else { return }
            let span = max(0, min(end, now).timeIntervalSince(max(start, midnight)))
            byProject[project, default: 0] += span
        }
        for e in log.events where e.at <= now {
            if e.working {
                close(e.key, at: e.at)
                open[e.key] = (e.at, e.project)
            } else {
                close(e.key, at: e.at)
                if e.finished, e.at >= midnight { finished += 1 }
            }
        }
        for key in Array(open.keys) { close(key, at: now) }
        let total = byProject.values.reduce(0, +)
        let projects = byProject.filter { $0.value > 0 }
        let busiest = projects.count >= 2 ? projects.max { $0.value < $1.value }?.key : nil
        return TodayRecap(finished: finished, working: total, busiest: busiest)
    }

    /// "4 sessions finished · 2h 10m working · busiest: claude-bar"; nil when nothing happened today.
    public var line: String? {
        guard finished > 0 || working >= 60 else { return nil }
        let m = Int(working / 60), time = m >= 60 ? (m % 60 == 0 ? "\(m / 60)h" : "\(m / 60)h \(m % 60)m") : "\(m)m"
        var parts = ["\(finished) session\(finished == 1 ? "" : "s") finished", "\(time) working"]
        if let busiest { parts.append("busiest: \(busiest)") }
        return parts.joined(separator: " · ")
    }
}

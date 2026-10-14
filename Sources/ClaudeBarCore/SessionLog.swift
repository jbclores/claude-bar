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
    static let keepFor: TimeInterval = 2 * 86_400

    /// Keys whose last event is "started working" are seeded as working, so a restart continues their span.
    public init(events: [SessionEvent] = []) {
        self.events = events
        var lastEvent: [String: SessionEvent] = [:]
        for e in events { lastEvent[e.key] = e }
        for (key, e) in lastEvent where e.working { last[key] = (.working, e.project) }
    }
    public static func == (a: SessionLog, b: SessionLog) -> Bool { a.events == b.events }

    public static var defaultFile: URL { Paths.home.appendingPathComponent(".claude/claude-bar/sessions-today.jsonl") }

    /// Notes who started or stopped working since the last update. True when events were added.
    @discardableResult
    public mutating func update(_ sessions: [(key: String, project: String, status: AgentStatus)], now: Date) -> Bool {
        let before = events.count
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

    public static func load(_ file: URL) -> SessionLog {
        guard let data = try? Data(contentsOf: file) else { return SessionLog() }
        let d = JSONDecoder(); d.dateDecodingStrategy = .millisecondsSince1970
        return SessionLog(events: data.split(separator: UInt8(ascii: "\n")).compactMap { try? d.decode(SessionEvent.self, from: Data($0)) })
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

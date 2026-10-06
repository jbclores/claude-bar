import Foundation

/// One Claude Code session's latest status line values, written by statusline-command.sh.
public struct Snapshot: Equatable, Sendable {
    public var sessionId: String
    public var cwd: String
    public var model: String?
    public var contextPct: Double?
    public var fiveHourPct: Double?
    public var fiveHourResetsAt: Date?
    public var sevenDayPct: Double?
    public var sevenDayResetsAt: Date?
    public var updatedAt: Date

    public init(sessionId: String, cwd: String, model: String? = nil, contextPct: Double? = nil,
                fiveHourPct: Double? = nil, fiveHourResetsAt: Date? = nil,
                sevenDayPct: Double? = nil, sevenDayResetsAt: Date? = nil, updatedAt: Date) {
        self.sessionId = sessionId
        self.cwd = cwd
        self.model = model
        self.contextPct = contextPct
        self.fiveHourPct = fiveHourPct
        self.fiveHourResetsAt = fiveHourResetsAt
        self.sevenDayPct = sevenDayPct
        self.sevenDayResetsAt = sevenDayResetsAt
        self.updatedAt = updatedAt
    }
}

extension Snapshot: Decodable {
    enum CodingKeys: String, CodingKey {
        case sessionId = "session_id", cwd, model
        case contextPct = "context_pct"
        case fiveHourPct = "five_hour_pct", fiveHourResetsAt = "five_hour_resets_at"
        case sevenDayPct = "seven_day_pct", sevenDayResetsAt = "seven_day_resets_at"
        case updatedAt = "updated_at"
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        sessionId = try c.decode(String.self, forKey: .sessionId)
        cwd = try c.decode(String.self, forKey: .cwd)
        model = try c.decodeIfPresent(String.self, forKey: .model)
        contextPct = try c.decodeIfPresent(Double.self, forKey: .contextPct)
        fiveHourPct = try c.decodeIfPresent(Double.self, forKey: .fiveHourPct)
        sevenDayPct = try c.decodeIfPresent(Double.self, forKey: .sevenDayPct)
        fiveHourResetsAt = Self.date(c, .fiveHourResetsAt)
        sevenDayResetsAt = Self.date(c, .sevenDayResetsAt)
        updatedAt = Date(timeIntervalSince1970: try c.decode(Double.self, forKey: .updatedAt))
    }

    /// `resets_at` may be epoch seconds, epoch milliseconds, or an ISO 8601 string.
    private static func date(_ c: KeyedDecodingContainer<CodingKeys>, _ key: CodingKeys) -> Date? {
        if let n = try? c.decodeIfPresent(Double.self, forKey: key) {
            return Date(timeIntervalSince1970: n > 1e12 ? n / 1000 : n)
        }
        guard let s = try? c.decodeIfPresent(String.self, forKey: key) else { return nil }
        let f = ISO8601DateFormatter()
        if let d = f.date(from: s) { return d }
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f.date(from: s)
    }
}

public struct SnapshotReader: Sendable {
    public var dir: URL
    public var maxAge: TimeInterval

    public init(dir: URL = Paths.snapshotsDir, maxAge: TimeInterval = 30 * 86_400) {
        self.dir = dir
        self.maxAge = maxAge
    }

    /// Every readable snapshot. Snapshots older than `maxAge` are deleted and skipped.
    public func read(now: Date = Date()) -> [Snapshot] {
        let fm = FileManager.default
        guard let names = try? fm.contentsOfDirectory(atPath: dir.path) else { return [] }
        let decoder = JSONDecoder()
        var out: [Snapshot] = []
        for name in names where name.hasSuffix(".json") && !name.hasPrefix(".") {
            let url = dir.appendingPathComponent(name)
            guard let data = try? Data(contentsOf: url),
                  let snap = try? decoder.decode(Snapshot.self, from: data) else { continue }
            if now.timeIntervalSince(snap.updatedAt) > maxAge {
                try? fm.removeItem(at: url)
                continue
            }
            out.append(snap)
        }
        return out
    }
}

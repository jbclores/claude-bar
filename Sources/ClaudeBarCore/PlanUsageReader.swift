import Foundation

/// Reads ~/.cat-office/plan-usage.json, the 5h / 7d reading that the status line and (patched) Cat Office's
/// headless workers both save, so usage stays fresh when no terminal session is open.
public struct PlanUsageReader: Sendable {
    public var file: URL

    public static var defaultFile: URL { Paths.home.appendingPathComponent(".cat-office/plan-usage.json") }

    public init(file: URL = PlanUsageReader.defaultFile) {
        self.file = file
    }

    /// The reading, minus windows that have reset (or, without a reset time, outlived their span); nil when none is left.
    public func read(now: Date = Date()) -> UsageSummary? {
        guard let data = try? Data(contentsOf: file),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let atMs = (obj["at"] as? NSNumber)?.doubleValue,
              let limits = obj["rate_limits"] as? [String: Any] else { return nil }
        let at = Date(timeIntervalSince1970: atMs > 1e12 ? atMs / 1000 : atMs)
        let five = Self.window(limits["five_hour"], at: at, span: 5 * 3600, now: now)
        let seven = Self.window(limits["seven_day"], at: at, span: 7 * 86_400, now: now)
        guard five != nil || seven != nil else { return nil }
        return UsageSummary(fiveHourPct: five?.pct, fiveHourResetsAt: five?.resets,
                            sevenDayPct: seven?.pct, sevenDayResetsAt: seven?.resets, asOf: at, workingCount: 0)
    }

    private static func window(_ value: Any?, at: Date, span: TimeInterval, now: Date) -> (pct: Double, resets: Date?)? {
        guard let w = value as? [String: Any], let pct = (w["used_percentage"] as? NSNumber)?.doubleValue else { return nil }
        let resets = date(w["resets_at"])
        if let resets { if resets <= now { return nil } } else if now.timeIntervalSince(at) > span { return nil }
        return (min(100, max(0, pct)), resets)
    }

    private static func date(_ value: Any?) -> Date? {
        if let n = (value as? NSNumber)?.doubleValue, n > 0 { return Date(timeIntervalSince1970: n > 1e12 ? n / 1000 : n) }
        guard let s = value as? String else { return nil }
        let f = ISO8601DateFormatter()
        if let d = f.date(from: s) { return d }
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f.date(from: s)
    }
}

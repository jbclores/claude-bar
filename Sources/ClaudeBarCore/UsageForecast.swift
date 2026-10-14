import Foundation

/// Where a usage limit is heading: the percentage at its reset if the last hour's pace holds, and when it reaches 100%
/// if that comes before the reset.
public struct UsageForecast: Equatable, Sendable {
    public var window: UsageWindow
    public var projected: Double
    public var hitAt: Date?
    public var resetsAt: Date
    public var atRisk: Bool { hitAt != nil }
    /// Already at the limit.
    public var reached = false

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
        // The rise counts the time up to now: after a burst, quiet minutes slow the pace instead of the forecast
        // sliding on.
        if let first = current.first, let end = current.last, end.0.timeIntervalSince(first.0) >= minSpan, end.1 > first.1 {
            pace = (end.1 - first.1) / max(now.timeIntervalSince(first.0), end.0.timeIntervalSince(first.0))
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
        var f = UsageForecast(window: window, projected: projected, hitAt: hit, resetsAt: reset)
        f.reached = last.1 >= 100
        return f
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
        if reached { return "You've reached the \(name) limit. It resets at \(time(resetsAt))" }
        if let hitAt { return "At this pace you'll reach the \(name) limit around \(time(hitAt))" }
        let rounded = Int((projected / 5).rounded()) * 5
        return "On pace for about \(rounded)% of the \(name) limit by \(time(resetsAt))"
    }

    /// The notification's text.
    public func warning(time: (Date) -> String) -> String {
        if reached { return "You've reached your \(name) limit. It resets at \(time(resetsAt))." }
        return "At this pace you'll reach your \(name) limit around \(time(hitAt ?? resetsAt)). It resets at \(time(resetsAt))."
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

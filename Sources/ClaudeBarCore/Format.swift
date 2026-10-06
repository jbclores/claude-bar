import Foundation

/// The status line's color thresholds: green below 60, yellow from 60, red from 85.
public enum UsageLevel: Equatable, Sendable {
    case ok, warn, high

    public init(percent: Double) {
        self = percent >= 85 ? .high : percent >= 60 ? .warn : .ok
    }
}

public enum Format {
    public static func percent(_ value: Double) -> String {
        "\(Int(value.rounded()))%"
    }

    /// "now", "5m ago", "3h ago", "2d ago".
    public static func age(_ date: Date, now: Date) -> String {
        let seconds = now.timeIntervalSince(date)
        return seconds < 60 ? "now" : duration(seconds) + " ago"
    }

    /// "<1m", "2m", "3h", "2d".
    public static func duration(_ seconds: TimeInterval) -> String {
        let s = Int(max(0, seconds))
        if s < 60 { return "<1m" }
        if s < 3600 { return "\(s / 60)m" }
        if s < 86_400 { return "\(s / 3600)h" }
        return "\(s / 86_400)d"
    }

    /// "resets in 2h 14m" within a day, else "resets Fri 1:00 AM".
    public static func resets(_ date: Date, now: Date, calendar: Calendar = .current) -> String {
        let seconds = date.timeIntervalSince(now)
        if seconds <= 0 { return "resets now" }
        if seconds < 86_400 {
            let minutes = Int((seconds / 60).rounded(.up))
            let h = minutes / 60, m = minutes % 60
            return h > 0 ? "resets in \(h)h \(m)m" : "resets in \(m)m"
        }
        let f = DateFormatter()
        f.calendar = calendar
        f.timeZone = calendar.timeZone
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "EEE h:mm a"
        return "resets " + f.string(from: date)
    }
}

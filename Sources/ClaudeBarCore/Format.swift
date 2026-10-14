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

    /// Whitespace collapsed, cut at a word boundary to at most `max` characters (with "…"); a single long word is cut.
    public static func shortTitle(_ text: String, max: Int) -> String {
        let words = text.split(whereSeparator: \.isWhitespace)
        let joined = words.joined(separator: " ")
        guard joined.count > max else { return joined }
        var out = ""
        for word in words {
            let next = out.isEmpty ? String(word) : out + " " + word
            if next.count > max - 1 { break }
            out = next
        }
        if out.isEmpty { out = String(joined.prefix(max - 1)) }
        return out + "…"
    }

    /// "running 3m", "idle 1h", "needs you" (Cat Office's words, StatusWords) — the second line of a cat's label.
    public static func statusText(_ status: AgentStatus, needsYou: Bool, since: Date?, now: Date = Date(),
                                  words: StatusWords = .current) -> String {
        if needsYou { return words.inline(.waiting) }
        guard let since else { return words.inline(status) }
        return "\(words.inline(status)) \(duration(now.timeIntervalSince(since)))"
    }

    /// "claude-opus-5-5[1m]" → "Opus 5.5", like the status line's display names; anything else unchanged.
    public static func modelName(_ id: String) -> String {
        guard id.hasPrefix("claude-") else { return id }
        let base = id.split(separator: "[").first.map(String.init) ?? id
        let parts = base.dropFirst("claude-".count).split(separator: "-").map(String.init)
        guard let family = parts.first, !family.isEmpty, family.allSatisfy(\.isLetter) else { return id }
        let version = parts.dropFirst().prefix { $0.count <= 2 && $0.allSatisfy(\.isNumber) }
        let name = family.prefix(1).uppercased() + family.dropFirst()
        return version.isEmpty ? name : "\(name) \(version.joined(separator: "."))"
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

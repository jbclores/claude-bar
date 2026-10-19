import Foundation

/// The sentences ClaudeBar speaks for status, usage and recap questions.
public enum VoiceStatus {
    /// "2 running, 1 needs you: claude-bar. pnp-ufdms idle."
    public static func status(running: [String], needYou: [String], idle: [String]) -> String {
        var sentences: [String] = []
        var head: [String] = []
        if !running.isEmpty { head.append("\(running.count) running") }
        if !needYou.isEmpty {
            head.append("\(needYou.count) \(needYou.count == 1 ? "needs" : "need") you: \(list(needYou))")
        }
        if !head.isEmpty { sentences.append(head.joined(separator: ", ") + ".") }
        if !idle.isEmpty { sentences.append(idle.count >= 4 ? "\(idle.count) others idle." : "\(list(idle)) idle.") }
        return sentences.isEmpty ? "Nothing is running." : sentences.joined(separator: " ")
    }

    /// "5-hour at 40%, on pace for about 70% of the 5-hour limit by 6:00 PM. 7-day at 12%."
    public static func usage(_ u: UsageSummary, forecast: UsageForecast?, time: (Date) -> String) -> String {
        guard let five = u.fiveHourPct else { return "I don't have your usage yet." }
        var first = "5-hour at \(Int(five.rounded()))%"
        if let forecast {
            let line = forecast.line(time: time)
            first += ", " + line.prefix(1).lowercased() + line.dropFirst()
        }
        var out = first + "."
        if let seven = u.sevenDayPct { out += " 7-day at \(Int(seven.rounded()))%." }
        return out
    }

    /// "4 sessions finished, 2 hours 10 minutes working, busiest: claude-bar."
    public static func recap(_ r: TodayRecap) -> String {
        guard r.finished > 0 || r.working >= 60 else { return "Nothing yet today." }
        var parts: [String] = []
        if r.finished > 0 { parts.append("\(r.finished) session\(r.finished == 1 ? "" : "s") finished") }
        if r.working >= 60 {
            let m = Int(r.working / 60), h = m / 60, rest = m % 60
            var words: [String] = []
            if h > 0 { words.append("\(h) hour\(h == 1 ? "" : "s")") }
            if rest > 0 { words.append("\(rest) minute\(rest == 1 ? "" : "s")") }
            parts.append(words.joined(separator: " ") + " working")
        }
        if let busiest = r.busiest { parts.append("busiest: \(busiest)") }
        return parts.joined(separator: ", ") + "."
    }

    /// An answer failure said aloud: colons become semicolons and it ends in a full stop.
    public static func failure(_ message: String) -> String {
        let s = message.replacingOccurrences(of: ": ", with: "; ")
        return s.hasSuffix(".") ? s : s + "."
    }

    private static func list(_ names: [String]) -> String {
        guard names.count > 1 else { return names.first ?? "" }
        return names.dropLast().joined(separator: ", ") + " and " + names[names.count - 1]
    }
}

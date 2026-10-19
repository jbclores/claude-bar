import Foundation

/// The sentences ClaudeBar speaks when a session needs you or finishes: short by default, with a few words of detail
/// when asked.
public enum SpokenAlert {
    /// "<name> needs you." With details: what it asks (the permission, the question) or that it has a plan.
    public static func needsYou(name: String, prompt: PendingPrompt?, details: Bool) -> String {
        guard details, let prompt else { return "\(name) needs you." }
        switch prompt {
        case let .permission(tool, input):
            return sentence("\(name) asks: \(permissionPhrase(tool: tool, input: input))", end: "?")
        case let .question(questions):
            let q = questions.first.map { words($0.question, max: 20) } ?? ""
            return q.isEmpty ? "\(name) needs you." : sentence("\(name) asks: \(q)", end: "?")
        case .plan:
            return "\(name) has a plan for you."
        }
    }

    /// "<name> finished." With details: the first words of the task.
    public static func finished(name: String, task: String?, details: Bool) -> String {
        let t = details ? words(task ?? "", max: 12) : ""
        return t.isEmpty ? "\(name) finished." : sentence("\(name) finished: \(t)", end: ".")
    }

    /// The permission in lowercase words, without the name or a question mark ("allow npm run build && npm test").
    public static func permissionPhrase(tool: String, input: String) -> String {
        if tool == "Bash" {
            let cmd = words(input, max: 6)
            return cmd.isEmpty ? "allow Bash" : "allow \(cmd)"
        }
        if AnswerChoices.editTools.contains(tool) {
            let first = input.split(whereSeparator: \.isNewline).first.map(String.init) ?? ""
            let file = (first.trimmingCharacters(in: .whitespaces) as NSString).lastPathComponent
            return file.isEmpty ? "allow an edit" : "allow an edit to \(file)"
        }
        return "allow \(tool)"
    }

    /// At most `max` sentences; the rest become "and N more."
    public static func capped(_ sentences: [String], max: Int = 3) -> [String] {
        guard sentences.count > max else { return sentences }
        return Array(sentences.prefix(max)) + ["and \(sentences.count - max) more."]
    }

    /// False when the same alert (`key`) was spoken less than 60 seconds ago.
    public static func shouldSpeak(key: String, last: [String: Date], now: Date) -> Bool {
        guard let at = last[key] else { return true }
        return now.timeIntervalSince(at) >= 60
    }

    /// The first `max` words of the first non-empty line (no "…").
    public static func words(_ text: String, max: Int) -> String {
        guard let line = text.split(whereSeparator: \.isNewline).first(where: { !$0.trimmingCharacters(in: .whitespaces).isEmpty })
        else { return "" }
        return line.split(whereSeparator: \.isWhitespace).prefix(max).joined(separator: " ")
    }

    private static func sentence(_ s: String, end: String) -> String {
        s.hasSuffix("?") || s.hasSuffix(".") ? s : s + end
    }
}

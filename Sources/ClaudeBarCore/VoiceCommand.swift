import Foundation

/// A session the user might name out loud, with the answer choices it is offering.
public struct VoiceTarget: Equatable, Sendable {
    public var id: String
    public var name: String
    public var options: [String]

    public init(id: String, name: String, options: [String]) {
        self.id = id
        self.name = name
        self.options = options
    }
}

/// What the user meant by what they said.
public enum VoiceIntent: Equatable, Sendable {
    case allow, alwaysAllow, deny, approve, reject
    /// A 0-based answer choice.
    case option(Int)
    case yes, cancel, status, usage, recap
    /// Only a session name was said.
    case name
    case none
}

/// A spoken command: what to do, and which session (a `VoiceTarget.id`) it is for.
public struct VoiceCommand: Equatable, Sendable {
    public var intent: VoiceIntent
    public var target: String?

    public init(intent: VoiceIntent, target: String? = nil) {
        self.intent = intent
        self.target = target
    }

    /// Lowercase, with punctuation and dashes turned into single spaces.
    public static func normalized(_ s: String) -> String {
        let spaced = s.lowercased().unicodeScalars.map { CharacterSet.alphanumerics.contains($0) ? Character($0) : " " }
        return String(spaced).split(separator: " ").joined(separator: " ")
    }

    /// Match what was said to a command; the first rule that fits wins.
    public static func parse(_ transcript: String, targets: [VoiceTarget]) -> VoiceCommand {
        let text = normalized(transcript)
        let words = text.split(separator: " ").map(String.init)
        let target = matchTarget(words, targets: targets)

        func has(_ phrase: String) -> Bool { contains(words, phrase.split(separator: " ").map(String.init)) }
        func hasAny(_ phrases: [String]) -> Bool { phrases.contains(where: has) }

        let intent: VoiceIntent
        if has("always allow") { intent = .alwaysAllow }
        else if hasAny(["deny", "don t allow", "do not allow"]) || text == "no" { intent = .deny }
        else if has("allow") { intent = .allow }
        else if has("approve") { intent = .approve }
        else if has("reject") { intent = .reject }
        else if let i = optionIndex(words, text: text, targets: targets) { intent = .option(i) }
        else if hasAny(["yes", "yeah", "yep", "confirm"]) { intent = .yes }
        else if hasAny(["cancel", "never mind"]) { intent = .cancel }
        else if hasAny(["status", "running"]) { intent = .status }
        else if has("usage") { intent = .usage }
        else if hasAny(["recap", "what did i do"]) { intent = .recap }
        else if target != nil { intent = .name }
        else { intent = .none }
        return VoiceCommand(intent: intent, target: target)
    }

    private static let numberWords = ["one", "two", "three", "four", "five", "six", "seven", "eight", "nine"]
    private static let ordinalWords = ["first", "second", "third", "fourth", "fifth", "sixth", "seventh", "eighth", "ninth"]
    private static let commandWords: Set<String> = [
        "allow", "always", "deny", "no", "approve", "reject", "option", "number", "yes", "yeah", "yep",
        "confirm", "cancel", "never", "mind", "status", "running", "usage", "recap",
    ]

    /// True when `phrase` appears in `words` as a run of whole words.
    private static func contains(_ words: [String], _ phrase: [String]) -> Bool {
        guard !phrase.isEmpty, words.count >= phrase.count else { return false }
        return (0...(words.count - phrase.count)).contains { Array(words[$0..<($0 + phrase.count)]) == phrase }
    }

    /// 1...9 from a digit or a number word.
    private static func number(_ w: String) -> Int? {
        if let n = Int(w), (1...9).contains(n) { return n }
        return numberWords.firstIndex(of: w).map { $0 + 1 }
    }

    private static func optionIndex(_ words: [String], text: String, targets: [VoiceTarget]) -> Int? {
        for i in words.indices {
            if i + 1 < words.count, words[i] == "option" || words[i] == "number", let n = number(words[i + 1]) { return n - 1 }
            if i + 1 < words.count, words[i + 1] == "one", let o = ordinalWords.firstIndex(of: words[i]) { return o }
        }
        if words.count == 1, let n = number(words[0]), numberWords.contains(words[0]) { return n - 1 }
        for t in targets {
            for (i, label) in t.options.enumerated() {
                let l = normalized(label).split(separator: " ").map(String.init)
                if contains(words, l) { return i }
            }
        }
        return nil
    }

    private static func matchTarget(_ words: [String], targets: [VoiceTarget]) -> String? {
        let names = targets.map { (id: $0.id, key: normalized($0.name).replacingOccurrences(of: " ", with: "")) }
        var best: (len: Int, id: String)?
        for start in words.indices {
            for end in start..<words.count {
                if start == end, commandWords.contains(words[start]) { continue }
                let run = words[start...end].joined()
                let len = end - start + 1
                if let b = best, b.len >= len { continue }
                if let exact = names.first(where: { $0.key == run }) {
                    best = (len, exact.id)
                } else if run.count >= 3 {
                    let hits = names.filter { $0.key.hasPrefix(run) }
                    if hits.count == 1 { best = (len, hits[0].id) }
                }
            }
        }
        return best?.id
    }
}

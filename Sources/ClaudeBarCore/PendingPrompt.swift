import Foundation

/// What a waiting session waits on (Cat Office's pendingPrompt, read from its transcript): a question with options,
/// a tool call to allow, or a plan to approve.
public enum PendingPrompt: Equatable, Sendable {
    public struct Option: Equatable, Sendable, Decodable {
        public var label: String
        public var description: String
        public init(label: String, description: String) { self.label = label; self.description = description }
    }
    public struct Question: Equatable, Sendable, Decodable {
        public var question: String
        public var header: String
        public var multiSelect: Bool
        public var options: [Option]
        public init(question: String, header: String, multiSelect: Bool, options: [Option]) {
            self.question = question; self.header = header; self.multiSelect = multiSelect; self.options = options
        }
    }
    case question([Question])
    case permission(tool: String, input: String)
    case plan(String)
}

extension PendingPrompt: Decodable {
    private enum Keys: String, CodingKey { case kind, questions, tool, input, plan }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: Keys.self)
        switch try c.decode(String.self, forKey: .kind) {
        case "question": self = .question(try c.decode([Question].self, forKey: .questions))
        case "permission": self = .permission(tool: try c.decode(String.self, forKey: .tool), input: try c.decodeIfPresent(String.self, forKey: .input) ?? "")
        case "plan": self = .plan(try c.decode(String.self, forKey: .plan))
        default: throw DecodingError.dataCorruptedError(forKey: .kind, in: c, debugDescription: "unknown kind")
        }
    }
}

import Foundation

/// A session Cat Office can answer that is waiting on a prompt.
public struct VoiceWaiting: Equatable, Sendable {
    public var id: String
    public var name: String
    public var prompt: PendingPrompt

    public init(id: String, name: String, prompt: PendingPrompt) {
        self.id = id
        self.name = name
        self.prompt = prompt
    }
}

/// What to do about a spoken command: say something, send an answer, or give a report.
public enum VoiceReply: Equatable, Sendable {
    case say(String)
    /// `button` indexes `AnswerChoices.of(prompt).buttons`; `then` is spoken once Cat Office takes the answer.
    case send(agentId: String, prompt: PendingPrompt, button: Int, then: String)
    case status, usage, recap
}

/// The back-and-forth of answering by voice: asks "which one?" when several sessions fit, asks for a "yes" before
/// allowing, approving or choosing, and forgets either after `expiry` seconds.
public struct VoiceConversation: Sendable {
    public static let expiry: TimeInterval = 20

    private enum Pending: Sendable {
        case pick(VoiceIntent, candidates: [String], at: Date)
        case confirm(agentId: String, prompt: PendingPrompt, button: Int, then: String, at: Date)
    }

    private var pending: Pending?

    public init() {}

    public mutating func handle(_ command: VoiceCommand, waiting: [VoiceWaiting], now: Date) -> VoiceReply {
        var command = command
        let held = pending
        pending = nil
        switch held {
        case let .confirm(agentId, prompt, button, then, at) where now.timeIntervalSince(at) <= Self.expiry:
            switch command.intent {
            case .yes: return .send(agentId: agentId, prompt: prompt, button: button, then: then)
            case .cancel, .deny: return .say("Okay.")
            default: break
            }
        case let .pick(intent, candidates, at) where now.timeIntervalSince(at) <= Self.expiry:
            if let target = command.target, candidates.contains(target), command.intent == .name || command.intent == intent {
                command.intent = intent
            }
        default: break
        }

        switch command.intent {
        case .status: return .status
        case .usage: return .usage
        case .recap: return .recap
        case .yes: return .say("Nothing to confirm.")
        case .cancel: return .say("Okay.")
        case .name, .none: return .say("Sorry, I didn't catch that.")
        default: return answer(command, waiting: waiting, now: now)
        }
    }

    private mutating func answer(_ command: VoiceCommand, waiting: [VoiceWaiting], now: Date) -> VoiceReply {
        let intent = command.intent
        guard let first = waiting.first else { return .say("Nothing is waiting.") }
        var scope = waiting
        if let target = command.target {
            scope = waiting.filter { $0.id == target }
            if scope.isEmpty { return .say("That one isn't waiting anymore.") }
        }
        let fits = scope.filter { Self.fits(intent, $0.prompt) }

        if fits.isEmpty {
            guard let w = scope.first(where: { Self.buttons($0.prompt) > 0 }) else { return .say("Answer that one in Cat Office.") }
            if case .option = intent, case .question = w.prompt, Self.buttons(w.prompt) > 0 {
                return .say("\(w.name) has no such choice.")
            }
            return .say("\(w.name) is asking \(Self.has(w.prompt)), not \(Self.wants(intent)).")
        }
        if fits.count > 1 {
            pending = .pick(intent, candidates: fits.map(\.id), at: now)
            return .say("\(Self.count(fits.count)) are waiting: \(Self.join(fits.map(\.name))). Which one?")
        }

        let w = fits[0]
        func confirm(_ ask: String, button: Int, then: String) -> VoiceReply {
            pending = .confirm(agentId: w.id, prompt: w.prompt, button: button, then: then, at: now)
            return .say(ask)
        }
        var said = ""
        if case let .permission(tool, input) = w.prompt { said = SpokenAlert.permissionPhrase(tool: tool, input: input) }
        switch intent {
        case .deny: return .send(agentId: w.id, prompt: w.prompt, button: 2, then: "Denied for \(w.name).")
        case .reject: return .send(agentId: w.id, prompt: w.prompt, button: 1, then: "Rejected \(w.name)'s plan.")
        case .allow: return confirm("\(said.prefix(1).uppercased() + said.dropFirst()) for \(w.name)? Say yes.", button: 0, then: "Allowed.")
        case .alwaysAllow: return confirm("Always \(said) for \(w.name)? Say yes.", button: 1, then: "Always allowed.")
        case .approve: return confirm("Approve \(w.name)'s plan? Say yes.", button: 0, then: "Approved.")
        case let .option(i):
            let label = AnswerChoices.of(w.prompt).buttons[i].title
            return confirm("Answer '\(label)' for \(w.name)? Say yes.", button: i, then: "Answered.")
        default: return .say("Sorry, I didn't catch that.")
        }
    }

    private static func buttons(_ p: PendingPrompt) -> Int { AnswerChoices.of(p).buttons.count }

    private static func fits(_ intent: VoiceIntent, _ p: PendingPrompt) -> Bool {
        switch (intent, p) {
        case (.allow, .permission), (.alwaysAllow, .permission), (.deny, .permission): return true
        case (.approve, .plan), (.reject, .plan): return true
        case let (.option(i), .question): return i >= 0 && i < buttons(p)
        default: return false
        }
    }

    private static func has(_ p: PendingPrompt) -> String {
        switch p {
        case .permission: return "for permission"
        case .question: return "a question"
        case .plan: return "you to approve a plan"
        }
    }

    private static func wants(_ intent: VoiceIntent) -> String {
        switch intent {
        case .allow, .alwaysAllow, .deny: return "permission"
        case .approve, .reject: return "a plan"
        default: return "a question"
        }
    }

    private static func count(_ n: Int) -> String {
        let words = ["Two", "Three", "Four", "Five", "Six", "Seven", "Eight", "Nine"]
        return (2...9).contains(n) ? words[n - 2] : String(n)
    }

    private static func join(_ names: [String]) -> String {
        names.count < 2 ? names.joined() : names.dropLast().joined(separator: ", ") + " and " + names[names.count - 1]
    }
}

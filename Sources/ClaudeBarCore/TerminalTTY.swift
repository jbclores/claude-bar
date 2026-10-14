import Foundation

/// A session's terminal, from `ps -o tty= -p <pid>` (the app's TerminalFinder runs it and brings that tab forward).
public enum TerminalTTY {
    /// `ps` output → "/dev/ttys004"; nil for "??" (no terminal: Orca, VS Code, a headless worker) or nothing.
    public static func path(psOutput: String) -> String? {
        let t = psOutput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty, t != "??" else { return nil }
        return t.hasPrefix("/dev/") ? t : "/dev/" + t
    }
}

/// Which cat's hover card shows: the cat under the pointer, else the card's own cat while the pointer is on the card
/// or on its way there (`lingering`, a moment after leaving the cat). Leaving both closes it. While the card is held
/// (lingering or pointed at), another cat takes it only once the pointer has rested on that cat `switchAfter`: on the
/// way up to the card the pointer crosses other cats, and their card must not replace the one being reached for.
public enum StickyCard {
    public static let switchAfter: TimeInterval = 0.15

    /// `hoveredFor`: how long the pointer has been on `hovered`.
    public static func shown<ID: Equatable>(hovered: ID?, hoveredFor: TimeInterval, card: ID?, onCard: Bool, lingering: Bool) -> ID? {
        let held = (onCard || lingering) ? card : nil
        guard let hovered else { return held }
        guard let held, held != hovered else { return hovered }
        return hoveredFor >= switchAfter ? hovered : held
    }
}

/// Which agents' answer states ("Sent", an error) no longer apply: the agent went away, stopped waiting, or now waits
/// on something else.
public enum AnswerReset {
    public static func stale(_ ids: Set<String>, before: [OfficeAgent], after: [OfficeAgent]) -> Set<String> {
        ids.filter { id in
            guard let now = after.first(where: { $0.id == id }), now.status == .waiting else { return true }
            return before.first(where: { $0.id == id })?.pendingPrompt != now.pendingPrompt
        }
    }

    /// How long "Sent" stands while the session still waits on the same prompt (Cat Office took it, but the dialog
    /// didn't, or the next prompt is the same): then the buttons come back.
    public static let sentFor: TimeInterval = 10

    /// A "Sent" from `sentAt` no longer applies (the session still waits on the same prompt; a changed prompt or a
    /// session no longer waiting is `stale`).
    public static func sentIsStale(sentAt: Date, now: Date) -> Bool {
        now.timeIntervalSince(sentAt) > sentFor
    }
}

/// One ticket per answer click, per agent: only the latest click's send may set the agent's answer state (an older
/// send finishing late doesn't overwrite a newer click's "Sent" or error).
public struct AnswerTickets: Sendable {
    private var latest: [String: Int] = [:]
    private var counter = 0
    public init() {}

    public mutating func issue(for id: String) -> Int {
        counter += 1
        latest[id] = counter
        return counter
    }

    public func isLatest(_ ticket: Int, for id: String) -> Bool { latest[id] == ticket }
}

extension SessionLog {
    /// Each tracked session with its project for the log: an office agent's repo (a helper's parent's), else its
    /// folder's name; a terminal session's folder name.
    public static func entries(tracked: [TrackedSession], agents: [OfficeAgent],
                               fallback: [LiveSession]) -> [(key: String, project: String, status: AgentStatus)] {
        func project(_ a: OfficeAgent) -> String {
            if a.isSubagent, let parent = agents.first(where: { !$0.isSubagent && $0.name == a.parentName }) { return project(parent) }
            if let r = a.repoName, !r.isEmpty { return r }
            return (a.cwd as NSString).lastPathComponent
        }
        return tracked.map { t in
            let name = agents.first { $0.key == t.key }.map(project)
                ?? fallback.first { $0.key == t.key }.map { ($0.cwd as NSString).lastPathComponent }
            return (t.key, name.flatMap { $0.isEmpty ? nil : $0 } ?? t.name, t.status)
        }
    }
}


/// The app a session's terminal belongs to, found from its process's ancestors' commands: Terminal or iTerm (the two
/// "Show terminal" can bring forward), else nil (VS Code, Orca, others).
public enum TerminalHost: Equatable, Sendable {
    case terminal, iterm

    public var bundleId: String { self == .terminal ? "com.apple.Terminal" : "com.googlecode.iterm2" }

    public static func of(ancestorCommands: [String]) -> TerminalHost? {
        for command in ancestorCommands {
            if command.contains("/Terminal.app/Contents/MacOS/") { return .terminal }
            if command.contains("/iTerm.app/Contents/MacOS/") { return .iterm }
        }
        return nil
    }
}

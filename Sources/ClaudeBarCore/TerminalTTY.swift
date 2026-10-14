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
/// or on its way there (`lingering`, a moment after leaving the cat). Leaving both closes it.
public enum StickyCard {
    public static func shown<ID: Equatable>(hovered: ID?, card: ID?, onCard: Bool, lingering: Bool) -> ID? {
        hovered ?? ((onCard || lingering) ? card : nil)
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

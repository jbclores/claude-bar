import Foundation

/// What each status is called, as Cat Office calls it (src/agents/live/status.ts STATUS_LABEL: "Needs you", "Running",
/// "Idle", "Ended"), or as a teammate's own Cat Office renamed them (shared on its snapshot as `statusLabels`).
public struct StatusWords: Equatable, Sendable {
    public var waiting: String
    public var working: String
    public var idle: String
    public var ended: String

    public init(waiting: String, working: String, idle: String, ended: String) {
        self.waiting = waiting; self.working = working; self.idle = idle; self.ended = ended
    }

    /// Cat Office's own words: what ClaudeBar says without a Cat Office, or with one that doesn't share them.
    public static let standard = StatusWords(waiting: "Needs you", working: "Running", idle: "Idle", ended: "Ended")

    /// The words in use now (the app sets them from the snapshot, else the last ones seen, else `standard`).
    nonisolated(unsafe) public static var current = StatusWords.standard

    /// From `{ waiting, working, idle, ended }`: all four, each a non-empty short line; else nil.
    public init?(_ dictionary: [String: Any]) {
        func word(_ key: String) -> String? {
            guard let s = (dictionary[key] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines), !s.isEmpty, s.count <= 40
            else { return nil }
            return s
        }
        guard let w = word("waiting"), let r = word("working"), let i = word("idle"), let e = word("ended") else { return nil }
        self.init(waiting: w, working: r, idle: i, ended: e)
    }

    /// As kept between launches.
    public var dictionary: [String: String] { ["waiting": waiting, "working": working, "idle": idle, "ended": ended] }

    /// "Running": on its own.
    public func word(_ status: AgentStatus) -> String {
        switch status {
        case .waiting: waiting
        case .working: working
        case .idle: idle
        case .ended: ended
        }
    }

    /// "running": inside a line ("Fix the bug  running 3m").
    public func inline(_ status: AgentStatus) -> String {
        let w = word(status)
        return w.prefix(1).lowercased() + w.dropFirst()
    }
}

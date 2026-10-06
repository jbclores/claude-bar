import Foundation

public struct FinishedEvent: Equatable, Sendable {
    public var key: String
    public var name: String
    public var task: String?

    public init(key: String, name: String, task: String?) {
        self.key = key
        self.name = name
        self.task = task
    }
}

/// Watches status changes between updates: which sessions need the user ("your turn"), since when each status
/// holds, and which office agents just finished.
public struct AttentionTracker: Sendable {
    public private(set) var attention: Set<String> = []
    /// Session key → when its current status began (the first update counts as the start).
    public private(set) var since: [String: Date] = [:]
    private var previous: [String: AgentStatus]?
    private var acknowledgedWaiting: Set<String> = []

    public init() {}

    /// Records the sessions' statuses now. Returns office agents that went from working to idle or ended
    /// (never on the first update, so launching doesn't send a burst).
    public mutating func update(_ sessions: [TrackedSession], now: Date) -> [FinishedEvent] {
        let first = previous == nil
        let before = previous ?? [:]
        var next: [String: AgentStatus] = [:]
        var events: [FinishedEvent] = []
        for s in sessions {
            next[s.key] = s.status
            let was = before[s.key]
            if was != s.status { since[s.key] = now }
            if s.status != .waiting { acknowledgedWaiting.remove(s.key) }
            switch s.status {
            case .waiting:
                if !acknowledgedWaiting.contains(s.key) { attention.insert(s.key) }
            case .working:
                attention.remove(s.key)
            case .idle, .ended:
                if !first, was == .working, s.isOffice {
                    events.append(FinishedEvent(key: s.key, name: s.name, task: s.task))
                    if s.status == .idle { attention.insert(s.key) }
                } else if was == .waiting {
                    attention.remove(s.key)
                }
                if s.status == .ended { attention.remove(s.key) }
            }
        }
        let present = Set(next.keys)
        attention.formIntersection(present)
        acknowledgedWaiting.formIntersection(present)
        since = since.filter { present.contains($0.key) }
        previous = next
        return events
    }

    /// The user looked: clear everything until each session changes again.
    public mutating func acknowledge() {
        let waiting = Set((previous ?? [:]).filter { $0.value == .waiting }.keys)
        acknowledgedWaiting.formUnion(attention.intersection(waiting))
        attention.removeAll()
    }
}

import Foundation

/// The desk an agent's cat works at in Cat Office (reported by the patched page): design, mirrored, turned.
public struct AgentDesk: Equatable, Sendable, Decodable {
    public var id: String
    public var flip: Bool
    public var rear: Bool

    public init(id: String, flip: Bool, rear: Bool) {
        self.id = id
        self.flip = flip
        self.rear = rear
    }
}

/// One agent from Cat Office's live feed (its `LiveAgent`), reduced to what ClaudeBar shows.
public struct OfficeAgent: Equatable, Sendable, Identifiable {
    public var id: String
    public var name: String
    /// "office" for Cat Office's own workers, "external" for other sessions.
    public var owner: String
    public var status: AgentStatus
    public var waitReason: String?
    /// Normalized folder.
    public var cwd: String
    public var repoName: String?
    /// Normalized project folder Cat Office worked out from what the agent touches (may differ from `cwd`).
    public var repoRoot: String?
    public var branch: String?
    public var model: String?
    public var task: String?
    public var lastAction: String?
    public var waitingSince: Date?
    /// When Cat Office last saw anything from the session (its updatedAt), if it says.
    public var updatedAt: Date?
    public var sessionId: String?
    /// The cat the browser shows for this agent (sent by the patched Cat Office).
    public var cat: String?
    /// The desk its cat works at in Cat Office, once the page has reported it.
    public var desk: AgentDesk?
    /// "subagent" for a helper an agent started (Cat Office: kind), else the session kind.
    public var kind: String?
    /// The agent that started this helper.
    public var parentName: String?
    /// The helper's type, e.g. "Explore".
    public var agentType: String?
    /// What the helper was asked to do.
    public var agentDescription: String?
    public var isSubagent: Bool { kind == "subagent" }
    /// Where its cat is and what it's doing, once the patched Cat Office page shares it (nil from an older patch or no page).
    public var place: MirrorPlace?
    /// Where `task` came from: "custom" (renamed), "ai", "description", or "prompt" (the first message).
    public var titleSource: String?
    /// What a waiting session waits on (a question, a tool to allow, a plan), if Cat Office says and it is understood.
    public var pendingPrompt: PendingPrompt?
    /// The session's process id, if Cat Office says.
    public var pid: Int32?

    /// What to call the agent: a custom or AI title, else its project, else the first words of its task, else
    /// its name.
    public var label: String { label(max: 28) }

    /// `label` with titles cut at `max` characters (a first message at `max` − 4): longer where there's room (the office list).
    public func label(max: Int) -> String {
        if isSubagent, let d = agentDescription, !d.isEmpty { return Format.shortTitle(d, max: max) }
        if let task, !task.isEmpty, let source = titleSource, source != "prompt" { return Format.shortTitle(task, max: max) }
        if let repoName, !repoName.isEmpty { return repoName }
        if let task, !task.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return Format.shortTitle(task, max: max - 4) }
        return name
    }

    public var isOffice: Bool { owner == "office" }
    /// A spare cat of the browser's office (OfficeMirror.spareAgent), not a session.
    public var isSpare: Bool { owner == OfficeMirror.spareOwner }
    /// The key this agent shares with snapshots and Claude Code's session files.
    public var key: String { sessionId ?? id }

    /// Since when it has had its status, for "idle 3h": an idle or ended session's last activity in Cat Office (ClaudeBar's
    /// own clock, `tracked`, restarts whenever it reconnects); waiting since its waitingSince; working since ClaudeBar saw
    /// it start (Cat Office has no time for that).
    public func statusSince(tracked: Date?) -> Date? {
        switch status {
        case .idle, .ended: updatedAt ?? tracked
        case .waiting: waitingSince ?? tracked
        case .working: tracked
        }
    }

    public init(id: String, name: String, owner: String = "external", status: AgentStatus, waitReason: String? = nil,
                cwd: String, repoName: String? = nil, repoRoot: String? = nil, branch: String? = nil, model: String? = nil, task: String? = nil,
                lastAction: String? = nil, waitingSince: Date? = nil, sessionId: String? = nil, cat: String? = nil) {
        self.id = id
        self.name = name
        self.owner = owner
        self.status = status
        self.waitReason = waitReason
        self.cwd = Paths.normalize(cwd)
        self.repoName = repoName
        self.repoRoot = repoRoot.map(Paths.normalize)
        self.branch = branch
        self.model = model
        self.task = task
        self.lastAction = lastAction
        self.waitingSince = waitingSince
        self.sessionId = sessionId
        self.cat = cat
    }
}

extension OfficeAgent: Decodable {
    private struct Repo: Decodable {
        var name: String
        var root: String?
    }
    private struct Action: Decodable { var label: String }

    enum CodingKeys: String, CodingKey {
        case id, name, owner, status, waitReason, cwd, repo, branch, model, task, lastAction, waitingSince, sessionId, cat
        case titleSource, desk, kind, parentName, agentType, description, place, updatedAt, pendingPrompt, pid
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let id = try c.decode(String.self, forKey: .id)
        let repo = try? c.decodeIfPresent(Repo.self, forKey: .repo)
        self.init(
            id: id,
            name: try c.decodeIfPresent(String.self, forKey: .name) ?? id,
            owner: try c.decodeIfPresent(String.self, forKey: .owner) ?? "external",
            status: AgentStatus(rawValue: try c.decodeIfPresent(String.self, forKey: .status) ?? "") ?? .idle,
            waitReason: try c.decodeIfPresent(String.self, forKey: .waitReason),
            cwd: try c.decodeIfPresent(String.self, forKey: .cwd) ?? "",
            repoName: repo?.name,
            repoRoot: repo?.root,
            branch: try c.decodeIfPresent(String.self, forKey: .branch),
            model: try c.decodeIfPresent(String.self, forKey: .model),
            task: try c.decodeIfPresent(String.self, forKey: .task),
            lastAction: (try? c.decodeIfPresent(Action.self, forKey: .lastAction))??.label,
            waitingSince: try c.decodeIfPresent(Double.self, forKey: .waitingSince).map { Date(timeIntervalSince1970: $0 / 1000) },
            sessionId: try c.decodeIfPresent(String.self, forKey: .sessionId),
            cat: try c.decodeIfPresent(String.self, forKey: .cat)
        )
        titleSource = try? c.decodeIfPresent(String.self, forKey: .titleSource)
        desk = (try? c.decodeIfPresent(AgentDesk.self, forKey: .desk)) ?? nil
        kind = try? c.decodeIfPresent(String.self, forKey: .kind)
        parentName = try? c.decodeIfPresent(String.self, forKey: .parentName)
        agentType = try? c.decodeIfPresent(String.self, forKey: .agentType)
        agentDescription = try? c.decodeIfPresent(String.self, forKey: .description)
        place = (try? c.decodeIfPresent(MirrorPlace.self, forKey: .place)) ?? nil
        pendingPrompt = (try? c.decodeIfPresent(PendingPrompt.self, forKey: .pendingPrompt)) ?? nil
        pid = (try? c.decodeIfPresent(Int32.self, forKey: .pid)) ?? nil
        updatedAt = (try? c.decodeIfPresent(Double.self, forKey: .updatedAt)).flatMap { $0 }.flatMap { $0.isFinite && $0 > 0 ? Date(timeIntervalSince1970: $0 / 1000) : nil }
    }
}

/// Cat Office's feed at one moment.
public struct OfficeSnapshot: Equatable, Sendable, Decodable {
    public var agents: [OfficeAgent]
    public var claudeHindered: Bool
    /// Cats not tied to a session (Cat Office's spare cats), with `key` and `name`. Empty without a page or older patch.
    public var spares: [MirrorPlace]
    /// When the newest place was posted (ms since 1970); nil with no page open. See `MirrorPlaces.isLive`.
    public var placesAt: Double?

    public init(agents: [OfficeAgent], claudeHindered: Bool = false, spares: [MirrorPlace] = [], placesAt: Double? = nil) {
        self.agents = agents
        self.claudeHindered = claudeHindered
        self.spares = spares
        self.placesAt = placesAt
    }

    private struct Health: Decodable { var hindered: Bool? }
    enum CodingKeys: String, CodingKey { case agents, claude, spares, placesAt }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        agents = try c.decode([OfficeAgent].self, forKey: .agents)
        claudeHindered = (try? c.decodeIfPresent(Health.self, forKey: .claude))??.hindered ?? false
        // One bad spare is skipped, not the whole snapshot.
        var list = (try? c.nestedUnkeyedContainer(forKey: .spares)).map { $0 }
        var spares: [MirrorPlace] = []
        while list?.isAtEnd == false {
            if let p = try? list?.decode(MirrorPlace.self) { spares.append(p) } else { _ = try? list?.decode(Skip.self) }
        }
        self.spares = spares
        let at = (try? c.decodeIfPresent(Double.self, forKey: .placesAt)) ?? nil
        placesAt = at?.isFinite == true ? at : nil
    }
    private struct Skip: Decodable { init(from decoder: Decoder) throws {} }

    /// The snapshot without the browser's places (each agent's `place`, `spares`, `placesAt`).
    public var withoutPlaces: OfficeSnapshot {
        var s = self
        for i in s.agents.indices { s.agents[i].place = nil }
        s.spares = []
        s.placesAt = nil
        return s
    }

    /// Only the browser's places differ (a Cat Office page posts them every 2 s): nothing the status, the menu bar
    /// title or the menu bar cat read has changed.
    public func sameExceptPlaces(_ other: OfficeSnapshot) -> Bool { withoutPlaces == other.withoutPlaces }
}

extension LiveSession {
    public init(office a: OfficeAgent) {
        // Where the agent is really working: Cat Office's project folder when it knows one.
        self.init(key: a.key, cwd: a.repoRoot ?? a.cwd, status: a.status, name: a.name, model: a.model, isOffice: a.isOffice, task: a.task)
        isSubagent = a.isSubagent
    }
}

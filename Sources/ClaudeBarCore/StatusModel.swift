import Foundation

public enum RowState: Equatable, Sendable {
    case live(AgentStatus, count: Int)
    case stale(since: Date)
    case noSessions
    case missing
}

public struct ProjectRow: Equatable, Sendable, Identifiable {
    public var id: String { path }
    public var path: String
    public var name: String
    public var branch: String?
    public var model: String?
    public var contextPct: Double?
    public var state: RowState
    public var needsAttention: Bool
    /// Helpers (sub-agents) running in the project, beside its sessions.
    public var helpers: Int = 0
}

public struct OfficeRow: Equatable, Sendable, Identifiable {
    public var id: String
    public var name: String
    /// OfficeAgent.label: custom/AI title, project, first task words, or the name.
    public var label: String
    public var status: AgentStatus
    public var since: Date?
    /// Repo name, else the folder's name.
    public var place: String
    public var branch: String?
    /// The task, else the last action.
    public var detail: String?
    public var lastAction: String?
    /// A helper started by `parentName` (listed under it).
    public var isSubagent: Bool = false
    public var parentName: String?
    public var agentType: String?
    public var needsAttention: Bool
}

public struct UsageSummary: Equatable, Sendable {
    public var fiveHourPct: Double?
    public var fiveHourResetsAt: Date?
    public var sevenDayPct: Double?
    public var sevenDayResetsAt: Date?
    public var asOf: Date?
    public var workingCount: Int

    public static let empty = UsageSummary(workingCount: 0)

    public init(fiveHourPct: Double? = nil, fiveHourResetsAt: Date? = nil, sevenDayPct: Double? = nil,
                sevenDayResetsAt: Date? = nil, asOf: Date? = nil, workingCount: Int) {
        self.fiveHourPct = fiveHourPct
        self.fiveHourResetsAt = fiveHourResetsAt
        self.sevenDayPct = sevenDayPct
        self.sevenDayResetsAt = sevenDayResetsAt
        self.asOf = asOf
        self.workingCount = workingCount
    }
}

public struct StatusInput: Sendable {
    public var projects: [Project]
    public var snapshots: [Snapshot]
    public var fallbackSessions: [LiveSession]
    /// Nil when Cat Office can't be reached.
    public var office: OfficeSnapshot?
    /// Project path → branch.
    public var branches: [String: String]
    /// Project paths that exist on disk.
    public var existing: Set<String>
    /// Session keys that need the user.
    public var attention: Set<String>
    /// Session key → when its current status began (as far as ClaudeBar has seen).
    public var statusSince: [String: Date]
    /// The shared ~/.cat-office/plan-usage.json reading; the newer of it and the snapshots wins.
    public var planUsage: UsageSummary?

    public init(projects: [Project], snapshots: [Snapshot] = [], fallbackSessions: [LiveSession] = [],
                office: OfficeSnapshot? = nil, branches: [String: String] = [:], existing: Set<String> = [],
                attention: Set<String> = [], statusSince: [String: Date] = [:], planUsage: UsageSummary? = nil) {
        self.projects = projects
        self.snapshots = snapshots
        self.fallbackSessions = fallbackSessions
        self.office = office
        self.branches = branches
        self.existing = existing
        self.attention = attention
        self.statusSince = statusSince
        self.planUsage = planUsage
    }
}

public struct StatusOutput: Equatable, Sendable {
    public var usage: UsageSummary
    public var projects: [ProjectRow]
    /// Nil when Cat Office can't be reached.
    public var office: [OfficeRow]?
    public var claudeHindered: Bool

    public static let empty = StatusOutput(usage: .empty, projects: [], office: nil, claudeHindered: false)
}

/// A session as AttentionTracker sees it.
public struct TrackedSession: Equatable, Sendable {
    public var key: String
    public var name: String
    public var status: AgentStatus
    public var isOffice: Bool
    public var task: String?

    public init(key: String, name: String, status: AgentStatus, isOffice: Bool, task: String? = nil) {
        self.key = key
        self.name = name
        self.status = status
        self.isOffice = isOffice
        self.task = task
    }
}

public enum StatusModel {
    /// Running sessions from both sources. Cat Office's view wins for a session it knows; ended ones are dropped.
    public static func liveSessions(fallback: [LiveSession], office: OfficeSnapshot?) -> [LiveSession] {
        var byKey: [String: LiveSession] = [:]
        var order: [String] = []
        for s in fallback {
            if byKey[s.key] == nil { order.append(s.key) }
            byKey[s.key] = s
        }
        for a in office?.agents ?? [] {
            if a.status == .ended {
                byKey[a.key] = nil
                continue
            }
            if byKey[a.key] == nil { order.append(a.key) }
            byKey[a.key] = LiveSession(office: a)
        }
        var seen = Set<String>()
        return order.compactMap { key in seen.insert(key).inserted ? byKey[key] : nil }
    }

    /// Every session to watch for status changes, ended office agents included.
    public static func trackedSessions(fallback: [LiveSession], office: OfficeSnapshot?) -> [TrackedSession] {
        var out: [TrackedSession] = []
        var seen = Set<String>()
        for a in office?.agents ?? [] where seen.insert(a.key).inserted {
            out.append(TrackedSession(key: a.key, name: a.name, status: a.status, isOffice: a.isOffice, task: a.task))
        }
        for s in fallback where seen.insert(s.key).inserted {
            out.append(TrackedSession(key: s.key, name: s.name, status: s.status, isOffice: s.isOffice, task: s.task))
        }
        return out
    }

    /// The pinned project a path belongs to: the longest project path containing it.
    public static func owner(of path: String, in projects: [Project]) -> Project? {
        projects.filter { Paths.isInside(path, $0.path) }.max { $0.path.count < $1.path.count }
    }

    public static func build(_ input: StatusInput) -> StatusOutput {
        let live = liveSessions(fallback: input.fallbackSessions, office: input.office)

        var snapsByProject: [String: [Snapshot]] = [:]
        var newestByKey: [String: Snapshot] = [:]
        for s in input.snapshots {
            if let p = owner(of: Paths.normalize(s.cwd), in: input.projects) { snapsByProject[p.path, default: []].append(s) }
            if (newestByKey[s.sessionId]?.updatedAt ?? .distantPast) < s.updatedAt { newestByKey[s.sessionId] = s }
        }
        // A session counts where its latest snapshot says it is, else where it started.
        var liveByProject: [String: [LiveSession]] = [:]
        for s in live {
            let path = newestByKey[s.key].map { Paths.normalize($0.cwd) } ?? s.cwd
            if let p = owner(of: path, in: input.projects) { liveByProject[p.path, default: []].append(s) }
        }

        let rows = input.projects.map { p -> ProjectRow in
            let snaps = snapsByProject[p.path] ?? []
            let newest = snaps.max { $0.updatedAt < $1.updatedAt }
            let all = liveByProject[p.path] ?? []
            let helperCount = all.filter(\.isSubagent).count
            // Helpers are counted beside the sessions; a project with only helpers still shows them.
            let sessions = all.contains { !$0.isSubagent } ? all.filter { !$0.isSubagent } : all
            var row = ProjectRow(
                path: p.path, name: p.name, branch: input.branches[p.path],
                model: (newest?.model ?? sessions.compactMap(\.model).first).map(Format.modelName),
                contextPct: newest?.contextPct, state: .noSessions,
                needsAttention: sessions.contains { input.attention.contains($0.key) })
            row.helpers = helperCount
            if !input.existing.contains(p.path) {
                row.state = .missing
                row.helpers = 0
                row.branch = nil
                row.model = nil
                row.contextPct = nil
            } else if let top = sessions.max(by: { $0.status.urgency < $1.status.urgency }) {
                row.state = .live(top.status, count: sessions.count)
            } else if let newest {
                row.state = .stale(since: newest.updatedAt)
            }
            return row
        }

        let usageSnap = input.snapshots
            .filter { $0.fiveHourPct != nil || $0.sevenDayPct != nil }
            .max { $0.updatedAt < $1.updatedAt }
        let fromSnapshot = usageSnap.map {
            UsageSummary(fiveHourPct: $0.fiveHourPct, fiveHourResetsAt: $0.fiveHourResetsAt,
                         sevenDayPct: $0.sevenDayPct, sevenDayResetsAt: $0.sevenDayResetsAt, asOf: $0.updatedAt, workingCount: 0)
        }
        var usage = [fromSnapshot, input.planUsage].compactMap { $0 }
            .max { ($0.asOf ?? .distantPast) < ($1.asOf ?? .distantPast) } ?? .empty
        usage.workingCount = live.filter { $0.status == .working }.count

        let officeRows = input.office.map { snapshot in
            let alive = snapshot.agents.filter { $0.status != .ended }
            let byName = { (x: OfficeAgent, y: OfficeAgent) in x.name.localizedCaseInsensitiveCompare(y.name) == .orderedAscending }
            let parents = alive.filter(\.isOffice).sorted(by: byName)
            let helpers = alive.filter(\.isSubagent).sorted(by: byName)
            // Each office cat, then the helpers it started; helpers whose parent isn't listed come last.
            var ordered: [OfficeAgent] = []
            for p in parents { ordered.append(p); ordered += helpers.filter { $0.parentName == p.name } }
            ordered += helpers.filter { h in !parents.contains { $0.name == h.parentName } }
            return ordered
                .map { a in
                    OfficeRow(
                        id: a.key, name: a.name, label: a.label, status: a.status,
                        since: a.statusSince(tracked: input.statusSince[a.key]),
                        place: a.repoName ?? (a.cwd as NSString).lastPathComponent,
                        branch: a.branch, detail: a.task ?? a.lastAction, lastAction: a.lastAction,
                        isSubagent: a.isSubagent, parentName: a.parentName, agentType: a.agentType,
                        needsAttention: input.attention.contains(a.key))
                }
        }

        return StatusOutput(usage: usage, projects: rows, office: officeRows, claudeHindered: input.office?.claudeHindered ?? false)
    }
}

import Foundation

/// The cat shown as the menu bar icon: the agent that matters most right now, in the pose that says why.
public struct MenuBarCat: Equatable, Sendable {
    public var agentId: String
    public var cat: String
    public var pose: CatPose

    public init(agentId: String, cat: String, pose: CatPose) {
        self.agentId = agentId
        self.cat = cat
        self.pose = pose
    }

    /// Needs you (waiting, or in `attention`) waves; else working types; else idle sleeps. Within a level the
    /// `current` agent stays while it still qualifies (no jumping between cats); otherwise the newest change wins
    /// (`waitingSince`, else `since`), then the name. Nil when no agent is shown (none, or all ended).
    public static func pick(agents: [OfficeAgent], attention: Set<String>, catIds: [String],
                            since: [String: Date] = [:], current: String? = nil) -> MenuBarCat? {
        func level(_ a: OfficeAgent) -> Int {
            if a.status == .waiting || (a.status != .ended && attention.contains(a.key)) { return 3 }
            switch a.status {
            case .working: return 2
            case .idle: return 1
            case .waiting, .ended: return 0
            }
        }
        let ranked = agents.filter { level($0) > 0 }
        guard let top = ranked.map(level).max() else { return nil }
        let candidates = ranked.filter { level($0) == top }
        let chosen = candidates.first { $0.id == current } ?? candidates.min { x, y in
            let tx = x.waitingSince ?? since[x.key] ?? .distantPast
            let ty = y.waitingSince ?? since[y.key] ?? .distantPast
            return tx != ty ? tx > ty : x.name.localizedCaseInsensitiveCompare(y.name) == .orderedAscending
        }
        guard let chosen else { return nil }
        let pose: CatPose = top == 3 ? .waving : top == 2 ? .typing : .sleeping
        return MenuBarCat(agentId: chosen.id, cat: CatPicker.cat(for: chosen, catIds: catIds), pose: pose)
    }
}

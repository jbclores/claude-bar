import Foundation

/// agent.registry.ts AgentSeed: a spare cat, its desk (or none: it hot-desks) and the floor it starts the day on.
public struct SpareCat: Equatable, Sendable {
    public struct Desk: Equatable, Sendable {
        public var floor: Int
        public var spotId: String
    }

    public var id: String
    public var name: String
    public var role: String
    public var catId: String
    public var desk: Desk?
    public var floor: Int
}

/// agent.registry.ts createRoster.
public enum SpareRoster {
    /// A cat in cats.json (CatSpriteManifest.cats): its sprite set id, name, and role when made in the cat builder.
    public struct Cat: Decodable, Equatable, Sendable {
        public var id: String
        public var name: String
        public var role: String?

        public init(id: String, name: String, role: String? = nil) {
            self.id = id; self.name = name; self.role = role
        }
    }

    /// cats.json, as far as the roster reads it.
    public struct Manifest: Decodable, Sendable {
        public var cats: [Cat]
    }

    /// agent.registry.ts AGENT_NAMES 17-19: names of the first cats; later cats go by the name in cats.json.
    public static let agentNames = ["Mochi", "Tofu", "Biscuit", "Pumpkin", "Pepper", "Latte", "Nori", "Mango", "Olive", "Sesame"]

    /// agent.registry.ts ROLE_CYCLE 21-23.
    public static let roleCycle = ["project-manager", "system-analyst", "ui-ux", "frontend", "backend", "qa"]

    /// agent.types.ts ROLE_LABELS 85-92.
    public static let roleLabels = [
        "project-manager": "Project Manager", "system-analyst": "System Analyst", "ui-ux": "UI/UX Designer",
        "frontend": "Frontend Developer", "backend": "Backend Developer", "qa": "QA Engineer",
    ]

    /// A spare cat's role, in words: "spare:agent-N" (or "agent-N") is the roster's Nth cat, its role as `roster` gives it.
    public static func roleLabel(spareKey: String, cats: [Cat]) -> String? {
        let id = spareKey.hasPrefix("spare:") ? String(spareKey.dropFirst("spare:".count)) : spareKey
        guard id.hasPrefix("agent-"), let n = Int(id.dropFirst("agent-".count)), n >= 1, n <= cats.count else { return nil }
        let i = n - 1
        let role = cats[i].role.flatMap { roleCycle.contains($0) ? $0 : nil } ?? roleCycle[i % roleCycle.count]
        return roleLabels[role]
    }

    /// floors.ts LOUNGE_FLOOR.
    static let loungeFloor = 1

    /// agent.registry.ts 35-59: one cat per sprite set, each with its own desk on the own-office floors while desks
    /// last, handed out alternating floors (round-robin over the floors' desk lists, in floor order); a cats.json role
    /// that is one of ours (agent.types.ts ROLE_LABELS) wins, the others cycle through the roles.
    public static func roster(floors: [SimFloor], cats: [Cat]) -> [SpareCat] {
        let desks = floors.filter(\.ownOffice).flatMap { f in f.spots.filter { $0.kind == "desk" }.map { SpareCat.Desk(floor: f.id, spotId: $0.id) } }
        // Spread cats across the office floors: alternate floors when picking desks.
        var queues: [[SpareCat.Desk]] = []
        var queueOf: [Int: Int] = [:]
        for d in desks {
            if let q = queueOf[d.floor] { queues[q].append(d) } else { queueOf[d.floor] = queues.count; queues.append([d]) }
        }
        var ordered: [SpareCat.Desk] = []
        var i = 0
        while ordered.count < desks.count {
            for q in queues where i < q.count { ordered.append(q[i]) }
            i += 1
        }

        let lounge = floors.contains { $0.id == loungeFloor } ? loungeFloor : floors.first?.id ?? loungeFloor
        return cats.enumerated().map { i, cat in
            let desk = i < ordered.count ? ordered[i] : nil
            return SpareCat(
                id: "agent-\(i + 1)",
                name: i < agentNames.count ? agentNames[i] : cat.name,
                role: cat.role.flatMap { roleCycle.contains($0) ? $0 : nil } ?? roleCycle[i % roleCycle.count],
                catId: cat.id,
                desk: desk,
                floor: desk?.floor ?? lounge)
        }
    }
}

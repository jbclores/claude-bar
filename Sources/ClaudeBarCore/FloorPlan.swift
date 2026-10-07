// Sources/ClaudeBarCore/FloorPlan.swift
import CoreGraphics
import Foundation

/// Where cats go in Cat Office's building (src/world/floors.ts, MissionControl.tsx): idle → Lounge; working or
/// waiting → their project's floor (the most specific matching repo root), else the Desk pool; helpers → their
/// parent's floor.
public enum FloorPlan {
    public static func floorId(for agent: OfficeAgent, among agents: [OfficeAgent], in building: Building) -> Int? {
        guard agent.status != .ended else { return nil }
        if agent.isSubagent {
            if let parent = agents.first(where: { $0.name == agent.parentName && !$0.isSubagent && $0.status != .ended }) {
                return floorId(for: parent, among: agents, in: building)
            }
            return building.deskPool?.id ?? building.lounge?.id
        }
        if agent.status == .idle { return building.lounge?.id ?? building.floors.first?.id }
        let place = agent.repoRoot ?? agent.cwd
        let match = building.floors
            .filter { $0.repoRoot.map { Paths.isInside(place, $0) } ?? false }
            .max { ($0.repoRoot?.count ?? 0) < ($1.repoRoot?.count ?? 0) }
        return match?.id ?? building.deskPool?.id ?? building.lounge?.id
    }
}

/// Who sits where on one floor.
public struct FloorSeating: Equatable, Sendable {
    public static let loungeSpots = 10
    public static let nearbyShown = 2
    public static let queueShown = 3

    /// The agent id at each of the floor's desks (aligned to Floor.desks).
    public var desks: [String?] = []
    /// Parent agent id → helpers standing beside its desk or seat.
    public var nearby: [String: [String]] = [:]
    public var nearbyOverflow: [String: Int] = [:]
    /// Cats with no desk, standing at the right edge.
    public var queue: [String] = []
    public var queueOverflow = 0
    /// The Lounge's spots (Lounge floor only).
    public var lounge: [String?] = []
    public var loungeOverflow = 0

    public init() {}
}

extension FloorPlan {
    public static func deskPosition(_ index: Int) -> (row: Int, column: Int) { (index / 6, index % 6) }

    public static func seating(on floor: Floor, agents: [OfficeAgent], previous: FloorSeating?) -> FloorSeating {
        var s = FloorSeating()
        let byName = { (x: OfficeAgent, y: OfficeAgent) in x.name.localizedCaseInsensitiveCompare(y.name) == .orderedAscending }
        let mains = agents.filter { !$0.isSubagent }.sorted(by: byName)
        let helpers = agents.filter(\.isSubagent).sorted(by: byName)

        func beside(_ helper: OfficeAgent, _ parentId: String) {
            if (s.nearby[parentId]?.count ?? 0) < FloorSeating.nearbyShown { s.nearby[parentId, default: []].append(helper.id) }
            else { s.nearbyOverflow[parentId, default: 0] += 1 }
        }
        func parentId(of helper: OfficeAgent) -> String? { mains.first { $0.name == helper.parentName }?.id }

        if floor.isLounge {
            s.lounge = StableSlots.assign(mains.map(\.id), previous: previous?.lounge ?? [], count: FloorSeating.loungeSpots)
            s.loungeOverflow = max(0, mains.count - FloorSeating.loungeSpots)
            for h in helpers {
                if let p = parentId(of: h), s.lounge.contains(p) { beside(h, p) }
                else if s.queue.count < FloorSeating.queueShown { s.queue.append(h.id) } else { s.queueOverflow += 1 }
            }
            return s
        }

        var seats = [String?](repeating: nil, count: floor.desks.count)
        let here = Set(agents.map(\.id))
        // 1. Keep last time's desks.
        for (i, id) in (previous?.desks ?? []).prefix(seats.count).enumerated() where id.map(here.contains) == true { seats[i] = id }
        func seated(_ id: String) -> Bool { seats.contains(id) }
        func free(_ i: Int) -> Bool { seats[i] == nil }
        // 2. Main agents: their reported desk design, else the first free desk; else the queue.
        var unseated: [OfficeAgent] = []
        for m in mains where !seated(m.id) {
            if let d = m.desk, let i = floor.desks.indices.first(where: { free($0) && floor.desks[$0].design == d.id && floor.desks[$0].flip == d.flip && floor.desks[$0].rear == d.rear }) {
                seats[i] = m.id
            } else {
                unseated.append(m)
            }
        }
        for m in unseated {
            if let i = seats.indices.first(where: free) { seats[i] = m.id }
            else if s.queue.count < FloorSeating.queueShown { s.queue.append(m.id) } else { s.queueOverflow += 1 }
        }
        // 3. Helpers: the free desk nearest their parent's desk, else beside the parent, else the queue.
        for h in helpers where !seated(h.id) {
            let p = parentId(of: h)
            let parentDesk = p.flatMap { pid in seats.firstIndex(of: pid) }
            let nearest = seats.indices.filter(free).min { x, y in
                guard let pd = parentDesk else { return x < y }
                let (pr, pc) = deskPosition(pd), (xr, xc) = deskPosition(x), (yr, yc) = deskPosition(y)
                return abs(xr - pr) + abs(xc - pc) < abs(yr - pr) + abs(yc - pc)
            }
            if let i = nearest { seats[i] = h.id }
            else if let p, parentDesk != nil { beside(h, p) }
            else if s.queue.count < FloorSeating.queueShown { s.queue.append(h.id) } else { s.queueOverflow += 1 }
        }
        s.desks = seats
        return s
    }
}

public enum FloorActivity: Equatable, Sendable { case empty, idle, working, needsYou }

extension FloorPlan {
    /// A start or finish this recent makes Follow go to its floor.
    static let recentChange: TimeInterval = 60

    public static func cats(on floorId: Int, agents: [OfficeAgent], in building: Building) -> [OfficeAgent] {
        agents.filter { floorId == self.floorId(for: $0, among: agents, in: building) }
    }

    public static func activity(of building: Building, agents: [OfficeAgent], attention: Set<String>) -> [Int: FloorActivity] {
        var out: [Int: FloorActivity] = [:]
        for f in building.floors {
            let here = cats(on: f.id, agents: agents, in: building)
            if here.contains(where: { $0.status == .waiting || attention.contains($0.key) }) { out[f.id] = .needsYou }
            else if here.contains(where: { $0.status == .working }) { out[f.id] = .working }
            else { out[f.id] = here.isEmpty ? .empty : .idle }
        }
        return out
    }

    /// Follow: a cat that needs you (newest first), else the most recent start or finish (within a minute), else
    /// the busiest floor, else the Lounge.
    public static func followTarget(building: Building, agents: [OfficeAgent], attention: Set<String>, since: [String: Date], now: Date) -> Int {
        let alive = agents.filter { $0.status != .ended }
        let floorOf = { (a: OfficeAgent) in floorId(for: a, among: agents, in: building) }
        let needy = alive.filter { $0.status == .waiting || attention.contains($0.key) }
            .max { ($0.waitingSince ?? since[$0.key] ?? .distantPast) < ($1.waitingSince ?? since[$1.key] ?? .distantPast) }
        if let needy, let f = floorOf(needy) { return f }
        let changed: [(OfficeAgent, Date)] = alive.compactMap { a in since[a.key].map { (a, $0) } }
            .filter { now.timeIntervalSince($0.1) <= recentChange }
        // Same instant (every cat first seen at launch): a working cat wins.
        let recent = changed.max { (x: (OfficeAgent, Date), y: (OfficeAgent, Date)) -> Bool in
            x.1 != y.1 ? x.1 < y.1 : (x.0.status != .working && y.0.status == .working)
        }
        if let (a, _) = recent, let f = floorOf(a) { return f }
        let busy = Dictionary(grouping: alive.filter { $0.status == .working }.compactMap(floorOf), by: { $0 })
            .max { $0.value.count < $1.value.count || ($0.value.count == $1.value.count && $0.key > $1.key) }
        return busy?.key ?? building.lounge?.id ?? building.floors.first?.id ?? 1
    }
}

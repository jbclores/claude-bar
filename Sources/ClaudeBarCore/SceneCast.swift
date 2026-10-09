import CoreGraphics
import Foundation

/// Who's on a built floor and where they sit (FloorPlan.seating over the floor's built desks and seats); cats the
/// mirror has on this floor are where the browser has them instead (OfficeMirror.places(on:)).
public struct SceneCast: Equatable, Sendable {
    public var seating: FloorSeating
    public var agents: [OfficeAgent]
    /// The desk id at each of `seating.desks`.
    public var deskIds: [String]
    public var lounge: Bool
    /// Agent id → its mirrored place on this floor; empty while the mirror isn't live.
    public var mirrored: [String: MirrorPlace]
    /// The browser's spare cats on this floor (OfficeMirror.spares(on:)): drawn, never counted.
    public var spares: [MirrorPlace]

    public init(seating: FloorSeating, agents: [OfficeAgent], deskIds: [String], lounge: Bool, mirrored: [String: MirrorPlace] = [:],
                spares: [MirrorPlace] = []) {
        self.spares = spares
        self.seating = seating
        self.agents = agents
        self.deskIds = deskIds
        self.lounge = lounge
        self.mirrored = mirrored
    }
}

extension SceneCast {
    /// A built floor's cast as both office views draw it: the cats on it with `mirror` (what the office draws), seated
    /// by `seatings` (SimHost.seatings, the one seating the sim's taken desks and seats come from; the floor seated
    /// afresh if it has none yet), the mirror's places and spares on it.
    public static func on(floor: Floor, room: BuiltRoom, building: Building, agents: [OfficeAgent], mirror: OfficeMirror,
                          seatings: [Int: FloorSeating]) -> SceneCast {
        let f = SimHost.seatFloor(floor, room)
        let here = FloorPlan.cats(on: floor.id, agents: agents, in: building, mirror: mirror)
        let seating = seatings[floor.id] ?? FloorPlan.seating(on: f, agents: here, previous: nil, seats: room.seats.count)
        return SceneCast(seating: seating, agents: here, deskIds: f.desks.map(\.id), lounge: floor.isLounge,
                         mirrored: mirror.places(on: floor.id, agents: agents, in: building),
                         spares: mirror.spares(on: floor.id, in: building))
    }
}

/// One cat placed on a built floor, in world terms.
public struct SceneCat: Equatable, Sendable {
    /// `mirrored`: where the browser has it (its own spot, pose and facing). `spare`: a spare cat of the browser's
    /// office, there too (no status ring).
    public enum Kind: Sendable { case desk, seat, helper, queue, mirrored, spare }
    public let agent: OfficeAgent
    public let kind: Kind
    public let at: FloorPoint
    /// World px above its floor point.
    public let lift: Double
    /// 1, or 0.8 for a helper beside its parent.
    public let size: Double
    public let pose: CatPose
    public let direction: String
    public let perch: String?
    /// The desk it works at (world px), for the screen's glow at night.
    public let desk: CGRect?
    /// Asleep in a seat facing front-right: the sleeping sprite (drawn facing front-left) mirrored, as Cat Office's
    /// applyActivityPose sleepMirror.
    public var sleepMirrored = false

    /// Status ring and waiting glow: not for a cat asleep on a seat (the Lounge's, or a mirrored nap).
    public var showsRing: Bool { kind != .seat && kind != .spare && !(kind == .mirrored && pose == .sleeping) }
}

extension SceneCast {
    /// Helpers stand beside their parent this far apart (floor u, v), at this size.
    static let helperStep = (u: 0.04, v: -0.02)
    static let helperSize = 0.8
    /// Lounge cats with no seat sleep in a cluster: 3 wide, this far apart (floor u, v), up to this many.
    static let clusterStep = 0.03
    static let clusterShown = 6

    /// Every cat's place, plus "+N" notes (text, floor point).
    public func layout(in room: BuiltRoom) -> (cats: [SceneCat], notes: [(String, FloorPoint)]) {
        // Mirrored cats are drawn where the browser has them; the rules below place the rest (they keep their seats in
        // `seating`, so a cat whose mirror stops goes back to the same one).
        let byId = Dictionary(agents.filter { mirrored[$0.id] == nil }.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        var cats: [SceneCat] = [], notes: [(String, FloorPoint)] = []
        var anchor: [String: FloorPoint] = [:]
        var drawn = Set<String>()
        for agent in agents {
            guard let place = mirrored[agent.id], drawn.insert(agent.id).inserted else { continue }
            let cat = Self.mirroredCat(agent, place, in: room)
            cats.append(cat)
            anchor[agent.id] = cat.at
        }
        var spareKeys = Set<String>()
        for place in spares {
            guard let key = place.key, spareKeys.insert(key).inserted else { continue }
            cats.append(Self.mirroredCat(OfficeMirror.spareAgent(place), place, in: room, kind: .spare))
        }
        // The desks and seats mirrored cats use: a rule-placed cat there moves to another (Self.clear).
        let busy = Set(mirrored.values.compactMap(\.spotId)).union(spares.compactMap(\.spotId))
        var displaced: [String] = []

        if lounge {
            // A cat left without a seat sleeps in the cluster with the rest.
            var unseated: [String] = []
            let loungeSlots = Self.clear(seating.lounge, ids: { room.seats.indices.contains($0) ? room.seats[$0].id : nil },
                                         busy: busy, ruled: byId, displaced: &unseated)
            for (i, id) in loungeSlots.enumerated() {
                guard let id, let agent = byId[id], room.seats.indices.contains(i) else { continue }
                let spot = room.seats[i]
                // simulation-engine.ts perches: only a raised spot puts the cat up on its prop (room.ts spotOwner).
                cats.append(SceneCat(agent: agent, kind: .seat, at: spot.standAt, lift: spot.lift, size: 1, pose: .sleeping,
                                     direction: "front-left", perch: spot.lift > 0 ? spot.owner : nil, desk: nil))
                anchor[id] = spot.standAt
            }
            // The rest cluster on the first rug spot, else the floor's centre.
            let rugs = Set(room.rugs.map(\.id))
            let base = room.seats.first { rugs.contains($0.owner) }?.standAt ?? FloorPoint(u: 0.5, v: 0.5)
            let seated = Set(loungeSlots.compactMap { $0 })
            let extra = agents.filter { !$0.isSubagent && !seated.contains($0.id) && mirrored[$0.id] == nil }
                .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
            for (j, agent) in extra.prefix(Self.clusterShown).enumerated() {
                let at = FloorPoint(u: base.u + Double(j % 3 - 1) * Self.clusterStep, v: base.v + Double(j / 3) * Self.clusterStep)
                cats.append(SceneCat(agent: agent, kind: .seat, at: at, lift: 0, size: 1, pose: .sleeping,
                                     direction: "front-left", perch: nil, desk: nil))
                anchor[agent.id] = at
            }
            if extra.count > Self.clusterShown {
                notes.append(("+\(extra.count - Self.clusterShown) asleep",
                              FloorPoint(u: base.u, v: base.v + Double((Self.clusterShown + 2) / 3) * Self.clusterStep)))
            }
        } else {
            let desks = Dictionary(room.desks.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
            let deskSlots = Self.clear(seating.desks, ids: { deskIds.indices.contains($0) ? deskIds[$0] : nil },
                                       busy: busy, ruled: byId, displaced: &displaced)
            for (i, id) in deskSlots.enumerated() {
                guard let id, let agent = byId[id], deskIds.indices.contains(i), let desk = desks[deskIds[i]] else { continue }
                var seated = agent
                seated.desk = AgentDesk(id: desk.design, flip: desk.flip, rear: desk.rear)
                let scene = DeskScene(seated)
                cats.append(SceneCat(agent: agent, kind: .desk, at: desk.standAt, lift: 0, size: 1, pose: scene.pose,
                                     direction: agent.status == .working ? desk.facing : scene.direction, perch: nil, desk: desk.rect))
                anchor[id] = desk.standAt
            }
        }
        // Helpers beside their parent.
        for (parent, helpers) in seating.nearby.sorted(by: { $0.key < $1.key }) {
            guard let base = anchor[parent] else { continue }
            func beside(_ k: Int) -> FloorPoint {
                FloorPoint(u: base.u + Self.helperStep.u * Double(k + 1), v: base.v + Self.helperStep.v * Double(k + 1))
            }
            for (k, id) in helpers.enumerated() {
                guard let agent = byId[id] else { continue }
                cats.append(SceneCat(agent: agent, kind: .helper, at: beside(k), lift: 0, size: Self.helperSize, pose: .standing,
                                     direction: "front-left", perch: nil, desk: nil))
            }
            if let more = seating.nearbyOverflow[parent] { notes.append(("+\(more)", beside(helpers.count))) }
        }
        // The queue at the elevator's waiting places.
        let door = room.elevator?.standAt ?? FloorPoint(u: 0.5, v: 0.5)
        // Mirrored cats the rules queued are drawn where the browser has them: they leave no gap and don't count. Cats
        // left without a desk by mirrored cats queue after the rest (FloorPlan.seating's overflow).
        let queue = seating.queue.filter { byId[$0] != nil } + displaced
        let queueOverflow = seating.queueOverflow + max(0, queue.count - FloorSeating.queueShown)
        for (i, id) in queue.prefix(FloorSeating.queueShown).enumerated() {
            guard let agent = byId[id] else { continue }
            cats.append(SceneCat(agent: agent, kind: .queue, at: ElevatorTrip.waitingPlace(door, index: i), lift: 0,
                                 size: agent.isSubagent ? Self.helperSize : 1, pose: .standing,
                                 direction: "front-left", perch: nil, desk: nil))
        }
        if queueOverflow > 0 {
            let last = ElevatorTrip.waitingPlace(door, index: 2)
            notes.append(("+\(queueOverflow)", FloorPoint(u: last.u + ElevatorTrip.waitSpread.u, v: last.v + ElevatorTrip.waitSpread.v)))
        }
        return (cats, notes)
    }

    /// `slots` (agent id per desk or seat) with no rule-placed cat (in `ruled`) on a desk or seat a mirrored cat uses
    /// (`busy`, by spot id): it moves to the first slot that is neither busy nor holding a rule-placed cat (empty, or
    /// a mirrored cat's rule slot), else it leaves the slots (`displaced`). Unchanged with nothing busy.
    static func clear(_ slots: [String?], ids: (Int) -> String?, busy: Set<String>, ruled: [String: OfficeAgent],
                      displaced: inout [String]) -> [String?] {
        guard !busy.isEmpty else { return slots }
        var out = slots
        func taken(_ i: Int) -> Bool { out[i].map { ruled[$0] != nil } ?? false }
        func isBusy(_ i: Int) -> Bool { ids(i).map(busy.contains) ?? false }
        for i in out.indices where taken(i) && isBusy(i) {
            let id = out[i]!
            out[i] = nil
            if let j = out.indices.first(where: { !taken($0) && !isBusy($0) && ids($0) != nil }) { out[j] = id } else { displaced.append(id) }
        }
        return out
    }

    /// A cat where the browser has it: its point (u, v), lifted on the seat it uses (`spotId` names a spot of this
    /// room with a lift, as the Lounge seats it: simulation-engine.ts perches), facing `direction`, in its pose
    /// (CatPose(place)). Riding the elevator to this floor, it waits at the elevator. At its desk it gets the
    /// desk's glow.
    static func mirroredCat(_ agent: OfficeAgent, _ place: MirrorPlace, in room: BuiltRoom, kind: SceneCat.Kind = .mirrored) -> SceneCat {
        let riding = place.phase == "elevator" && place.floor != room.floorId
        let at = riding ? room.elevator?.standAt ?? FloorPoint(u: place.u, v: place.v) : FloorPoint(u: place.u, v: place.v)
        let spot = riding ? nil : place.spotId.flatMap { id in
            (room.seats + room.props.flatMap(\.spots) + room.rugSpots).first { $0.id == id }
        }
        let lift = spot.map { max(0, $0.lift) } ?? 0
        let desk = riding ? nil : place.spotId.flatMap { id in room.desks.first { $0.id == id }?.rect }
        let pose = CatPose(place)
        return SceneCat(agent: agent, kind: kind, at: at, lift: lift, size: 1, pose: pose,
                        direction: place.direction, perch: lift > 0 ? spot?.owner : nil, desk: desk,
                        sleepMirrored: pose == .sleeping && spot?.pose == "sit" && place.direction == "front-right")
    }
}


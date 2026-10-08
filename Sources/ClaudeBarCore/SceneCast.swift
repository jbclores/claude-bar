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

    public init(seating: FloorSeating, agents: [OfficeAgent], deskIds: [String], lounge: Bool, mirrored: [String: MirrorPlace] = [:]) {
        self.seating = seating
        self.agents = agents
        self.deskIds = deskIds
        self.lounge = lounge
        self.mirrored = mirrored
    }
}

/// One cat placed on a built floor, in world terms.
public struct SceneCat: Equatable, Sendable {
    /// `mirrored`: where the browser has it (its own spot, pose and facing).
    public enum Kind: Sendable { case desk, seat, helper, queue, mirrored }
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

    /// Status ring and waiting glow: not for a cat asleep on a seat (the Lounge's, or a mirrored nap).
    public var showsRing: Bool { kind != .seat && !(kind == .mirrored && pose == .sleeping) }
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
        for agent in agents {
            guard let place = mirrored[agent.id], cats.allSatisfy({ $0.agent.id != agent.id }) else { continue }
            let cat = Self.mirroredCat(agent, place, in: room)
            cats.append(cat)
            anchor[agent.id] = cat.at
        }

        if lounge {
            for (i, id) in seating.lounge.enumerated() {
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
            let seated = Set(seating.lounge.compactMap { $0 })
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
            for (i, id) in seating.desks.enumerated() {
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
        for (i, id) in seating.queue.enumerated() {
            guard let agent = byId[id] else { continue }
            cats.append(SceneCat(agent: agent, kind: .queue, at: ElevatorTrip.waitingPlace(door, index: i), lift: 0,
                                 size: agent.isSubagent ? Self.helperSize : 1, pose: .standing,
                                 direction: "front-left", perch: nil, desk: nil))
        }
        if seating.queueOverflow > 0 {
            let last = ElevatorTrip.waitingPlace(door, index: 2)
            notes.append(("+\(seating.queueOverflow)", FloorPoint(u: last.u + ElevatorTrip.waitSpread.u, v: last.v + ElevatorTrip.waitSpread.v)))
        }
        return (cats, notes)
    }

    /// A cat where the browser has it: its point (u, v), lifted on the seat it uses (`spotId` names a spot of this
    /// room with a lift, as the Lounge seats it: simulation-engine.ts perches), facing `direction`, in its pose
    /// (CatPose(place)). Riding the elevator to this floor, it waits at the elevator. At its desk it gets the
    /// desk's glow.
    static func mirroredCat(_ agent: OfficeAgent, _ place: MirrorPlace, in room: BuiltRoom) -> SceneCat {
        let riding = place.phase == "elevator" && place.floor != room.floorId
        let at = riding ? room.elevator?.standAt ?? FloorPoint(u: place.u, v: place.v) : FloorPoint(u: place.u, v: place.v)
        let spot = riding ? nil : place.spotId.flatMap { id in
            (room.seats + room.props.flatMap(\.spots) + room.rugSpots).first { $0.id == id }
        }
        let lift = spot.map { max(0, $0.lift) } ?? 0
        let desk = riding ? nil : place.spotId.flatMap { id in room.desks.first { $0.id == id }?.rect }
        return SceneCat(agent: agent, kind: .mirrored, at: at, lift: lift, size: 1, pose: CatPose(place),
                        direction: place.direction, perch: lift > 0 ? spot?.owner : nil, desk: desk)
    }
}


import Foundation

/// A cat the simulation runs: an idle session's cat (`id` = the agent id) or a spare cat (`id` = its roster id).
public struct SimCat: Equatable, Sendable {
    public var id: String
    public var isSpare: Bool
    /// The cat's own name (spares).
    public var name: String?
    /// Its sprite set.
    public var catId: String?
    /// Its own desk (agent.registry.ts: a spare's desk, SpareRoster), the only desk it works at. A spare without one
    /// hot-desks on Robin's office floors; a session's cat, idle, takes only the Lounge's lounge spots (OfficeSim.decide).
    public var deskSpotId: String?
    /// Where it joins the simulation (where it stands now); nil: at its desk, else the Lounge's middle.
    public var floor: Int?
    public var at: FloorPoint?

    public init(id: String, isSpare: Bool, name: String? = nil, catId: String? = nil, deskSpotId: String? = nil,
                floor: Int? = nil, at: FloorPoint? = nil) {
        self.id = id; self.isSpare = isSpare; self.name = name; self.catId = catId; self.deskSpotId = deskSpotId
        self.floor = floor; self.at = at
    }

    /// A spare cat of the roster, starting the day at its desk.
    public init(spare: SpareCat) {
        self.init(id: spare.id, isSpare: true, name: spare.name, catId: spare.catId, deskSpotId: spare.desk?.spotId)
    }
}

/// Cat Office's office life for ClaudeBar's idle cats (simulation-engine.ts SimulationEngine, without fires, panic,
/// parties, meetings and directives): each cat chooses a spot (SimChoice), walks there along the walking grid at
/// Cat Office's speed (the elevator for another floor), uses it for a duration drawn from its activity's range while
/// its needs gain, then chooses again. Stepped STEP (1/30 sim minute) at a time, as the engine steps. Its output is
/// step 1's mirror type, so the layout, walks, rides and hover cards draw it as they draw the browser's office.
public final class OfficeSim {
    // MARK: simulation-engine.ts constants

    /// simulation-engine.ts WALK_SPEED_PX: world px per sim minute.
    static let walkSpeedPx = 190.0
    /// simulation-engine.ts ELEVATOR_FADE / ELEVATOR_RIDE_BASE / ELEVATOR_RIDE_PER_FLOOR (sim minutes).
    static let elevatorFade = 0.7
    static let elevatorRideBase = 1.4
    static let elevatorRidePerFloor = 0.7
    /// simulation-engine.ts HOP_MINUTES: hopping onto or off a step or seat.
    static let hopMinutes = 0.18
    /// simulation-engine.ts SLOT_OFFSETS: extra occupants of a shared spot without slots.
    static let slotOffsets: [FloorPoint] = [
        .init(u: 0, v: 0), .init(u: 0.06, v: 0), .init(u: 0, v: 0.06), .init(u: -0.06, v: 0),
        .init(u: 0, v: -0.06), .init(u: 0.06, v: 0.06), .init(u: -0.06, v: -0.06), .init(u: 0.06, v: -0.06),
    ]
    /// simulation-engine.ts REACH_GESTURES.
    static let reachGestures = ["left-up", "right-up"]
    /// room.ts ELEVATOR_WAIT_SPREAD.
    static let elevatorWaitSpread = FloorPoint(u: 0.014, v: 0.035)
    /// activities.ts ELEVATOR_BADGE.
    static let elevatorBadge = "Taking the elevator"
    /// Catch-up after the office was closed: at most this many sim minutes (spec section 3).
    public static let catchUpCap = 30.0
    /// The most one `step` call simulates (the engine caps each frame: tick's min(realSeconds, 0.25) and
    /// MAX_STEPS_PER_TICK, simulation-engine.ts 874-883); longer gaps are catch-up's.
    public static let stepCap = 30.0

    // MARK: state

    /// simulation-engine.ts Phase.
    enum Phase: Equatable {
        case waiting(t: Double)
        case deciding
        case hoppingDown
        case walking
        case elevatorOut(t: Double, to: Int)
        case elevatorRide(t: Double, to: Int)
        case elevatorIn(t: Double)
        case using(t: Double, total: Double)

        /// The phase's own name (for tests and the mirror's phase).
        var label: String {
            switch self {
            case .waiting: "waiting"
            case .deciding: "deciding"
            case .hoppingDown, .walking: "walking"
            case .elevatorOut, .elevatorRide, .elevatorIn: "elevator"
            case .using: "using"
            }
        }

        /// places-share.ts PHASES: deciding and waiting are standing about.
        var shared: String {
            switch label {
            case "walking", "using", "elevator": label
            default: "idle"
            }
        }
    }

    /// simulation-engine.ts Target.
    struct Target {
        var floor: Int
        var spot: RoomSpot
        var def: SimActivity
        var slot: Int
        var point: FloorPoint
    }

    /// simulation-engine.ts Runtime's hop.
    struct Hop {
        var from: Double
        var to: Double
        var k: Double
        var fromPos: FloorPoint?
        var toPos: FloorPoint?
    }

    /// simulation-engine.ts Runtime plus the Agent fields the simulation reads and shows.
    final class Runtime {
        var cat: SimCat
        let index: Int
        var floor: Int
        var position: FloorPoint
        var direction: String
        var state: SimCatState = .idle
        var gesture = "both-down"
        var expression = "default"
        var pose = "stand"
        var usingSpotId: String?
        /// The badge shown (Agent.activity's label), nil for none.
        var badge: String?
        var needs: SimNeeds
        var phase: Phase
        var path: [FloorPoint] = []
        var target: Target?
        var lastWorkMinute = 0.0
        var lastSpotId: String?
        var arrivalLeft = 0.0
        let speedPx: Double
        var travelled = 0.0
        var hop: Hop?
        var groundLift = 0.0
        var perch: String?
        var gestureLeft = 0.0

        init(cat: SimCat, index: Int, floor: Int, position: FloorPoint, direction: String, needs: SimNeeds, phase: Phase, speedPx: Double) {
            self.cat = cat; self.index = index; self.floor = floor; self.position = position; self.direction = direction
            self.needs = needs; self.phase = phase; self.speedPx = speedPx
        }
    }

    private var rng: SimRng
    /// Steps taken: the sim time is steps × STEP (counted, so 900 steps are exactly 30 minutes).
    private var steps = 0
    /// Sim minutes asked for but not yet stepped (less than a step).
    private var pending = 0.0
    private var nextIndex = 0
    private(set) var runtimes: [Runtime] = []
    /// simulation-engine.ts occupancy: spot id → the cat in each slot.
    private(set) var occupancy: [String: [String?]] = [:]
    /// Spots taken outside the simulation (working and waiting sessions' desks): never free.
    private(set) var taken: Set<String> = []
    /// How many times a cat has chosen (decide), for tests.
    private(set) var decisions = 0

    private var building: Building?
    private var floors: [SimFloor] = []
    private var grids: [Int: NavGrid] = [:]
    /// Each floor's elevator spot (simulation-engine.ts elevators).
    private var elevators: [Int: RoomSpot] = [:]

    /// Sim minutes simulated so far.
    public var time: Double { Double(steps) / 30 }

    public init(seed: UInt32) {
        rng = SimRng(seed: seed)
    }

    /// The floors as the simulation walks them: every floor of `building` with a built room, in the building's order,
    /// with the room's spots (BuiltRoom.spots, the browser's).
    public static func floors(building: Building, rooms: [Int: BuiltRoom]) -> [SimFloor] {
        building.floors.compactMap { f in rooms[f.id].map { SimFloor(id: f.id, ownOffice: f.isOwnOffice, frame: $0.frame, spots: $0.spots) } }
    }

    func floor(_ id: Int) -> SimFloor? { floors.first { $0.id == id } }

    // MARK: cats

    /// Cats to simulate now: idle session agents and, when on, spares. A cat left out (its session started working,
    /// the switch went off) leaves at once and frees its spot; a new one joins (simulation-engine.ts createRuntime).
    /// `takenSpotIds`: spots the simulation's cats can't have (working and waiting sessions' desks); a cat headed for
    /// or at one of them leaves it and stands a moment before choosing again.
    public func setCats(_ cats: [SimCat], building: Building, rooms: [Int: BuiltRoom], grids: [Int: NavGrid], takenSpotIds: Set<String> = []) {
        self.building = building
        self.taken = takenSpotIds
        self.floors = Self.floors(building: building, rooms: rooms)
        self.grids = grids
        elevators = [:]
        for f in floors { if let e = f.spots.first(where: { $0.kind == "elevator" }) { elevators[f.id] = e } }

        let wanted = Dictionary(cats.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        for rt in runtimes where wanted[rt.cat.id] == nil { release(rt) }
        runtimes = runtimes.filter { wanted[$0.cat.id] != nil }
        // Spots gone with a changed building are free; claims on them are dropped.
        let spotIds = Set(floors.flatMap { $0.spots.map(\.id) })
        occupancy = occupancy.filter { spotIds.contains($0.key) }
        for rt in runtimes {
            rt.cat = wanted[rt.cat.id]!
            if floor(rt.floor) == nil || grids[rt.floor] == nil {
                // Its floor is gone: it stands in the Lounge and chooses again.
                release(rt)
                place(rt, onFloor: fallbackFloor(), at: nil)
                idle(rt, badge: nil, 0.2, 1)
            } else if let t = rt.target, taken.contains(t.spot.id) || floor(t.floor)?.spots.contains(where: { $0.id == t.spot.id }) != true {
                release(rt)
                idle(rt, badge: nil, 0.2, 1)
            }
        }
        let have = Set(runtimes.map(\.cat.id))
        var added = Set<String>()
        for cat in cats where !have.contains(cat.id) && added.insert(cat.id).inserted {
            runtimes.append(createRuntime(cat))
        }
    }

    /// simulation-engine.ts createRuntime: needs from range(55, 95), waiting range(0.2, 1.5), its own walking speed;
    /// a cat with its own desk (and no place to join from) starts the day at it, for range(4, 50) minutes.
    private func createRuntime(_ cat: SimCat) -> Runtime {
        let needs = SimNeeds.starting(rng: &rng)
        let desk = cat.at == nil ? cat.deskSpotId.flatMap { id in
            floors.lazy.compactMap { f in f.spots.first { $0.id == id && $0.kind == "desk" }.map { (floor: f.id, spot: $0) } }.first
        } : nil
        let floorId = desk?.floor ?? cat.floor.flatMap { floor($0) != nil ? $0 : nil } ?? fallbackFloor()
        let waiting = rng.range(0.2, 1.5)
        let speed = Self.walkSpeedPx * rng.range(0.85, 1.15)
        let rt = Runtime(cat: cat, index: nextIndex, floor: floorId, position: FloorPoint(u: 0.5, v: 0.5),
                         direction: desk?.spot.facing ?? "front-left", needs: needs, phase: .waiting(t: waiting), speedPx: speed)
        nextIndex += 1
        if let desk {
            rt.position = desk.spot.standAt
        } else {
            place(rt, onFloor: floorId, at: cat.at)
        }
        // The day starts with everyone already at their desk, staggered so they don't all leave together.
        if let desk, let slot = reserve(desk.spot, rt.cat.id), let def = SimActivities.activity(for: desk.spot) {
            rt.target = Target(floor: desk.floor, spot: desk.spot, def: def, slot: slot, point: desk.spot.standAt)
            let left = rng.range(4, 50)
            rt.phase = .using(t: left, total: left)
            applyActivityPose(rt, def, desk.spot, facing: desk.spot.facing)
            rt.groundLift = desk.spot.lift
        }
        return rt
    }

    /// Puts a cat on `floorId` at `at` (on open floor; else the nearest open cell's centre), or with no point at the
    /// open cell nearest the floor's middle (createRuntime's fallback).
    private func place(_ rt: Runtime, onFloor floorId: Int, at: FloorPoint?) {
        rt.floor = floorId
        rt.path = []
        rt.hop = nil
        rt.perch = nil
        rt.groundLift = 0
        guard let nav = grids[floorId] else { rt.position = at ?? FloorPoint(u: 0.5, v: 0.5); return }
        let p = at ?? FloorPoint(u: 0.5, v: 0.5)
        if at != nil, nav.isOpenAt(p) { rt.position = p; return }
        rt.position = nav.nearestOpenCell(p).map { nav.cellCenter($0.ui, $0.vi) } ?? p
    }

    /// simulation-engine.ts fallbackFloor: the Lounge, else the first floor.
    private func fallbackFloor() -> Int {
        floor(SpareRoster.loungeFloor) != nil ? SpareRoster.loungeFloor : floors.first?.id ?? SpareRoster.loungeFloor
    }

    /// Starts each listed cat from its mirrored place (simulation-engine.ts restorePlaces): at its spot, taken at once
    /// with the minutes it had left there; else standing where it stood (on its ride's floor, at the elevator, if it was
    /// riding), choosing soon. Cats the mirror doesn't have carry on.
    public func seed(from mirror: OfficeMirror) {
        let spares = Dictionary(mirror.spares.compactMap { p in p.key.map { ($0, p) } }, uniquingKeysWith: { a, _ in a })
        let back: [(Runtime, MirrorPlace)] = runtimes.compactMap { rt in
            guard let p = rt.cat.isSpare ? spares["spare:\(rt.cat.id)"] : mirror.places[rt.cat.id] else { return nil }
            let floorId = p.phase == "elevator" ? p.ridingTo ?? p.floor : p.floor
            return floor(floorId) != nil && grids[floorId] != nil ? (rt, p) : nil
        }
        // Their own places are free for the others first.
        for (rt, _) in back { release(rt) }
        for (rt, p) in back {
            let riding = p.phase == "elevator" && p.ridingTo.map { floor($0) != nil } == true
            let floorId = riding ? p.ridingTo! : p.floor
            guard let f = floor(floorId) else { continue }
            place(rt, onFloor: floorId, at: nil)
            rt.travelled = 0
            let spot = riding ? nil : p.spotId.flatMap { id in f.spots.first { $0.id == id && $0.kind != "elevator" } }
            if let spot, let def = SimActivities.activity(for: spot), let slot = reserve(spot, rt.cat.id) {
                let point = slotPoint(floorId, spot, slot)
                rt.target = Target(floor: floorId, spot: spot, def: def, slot: slot, point: point)
                rt.position = point
                arrive(rt)
                land(rt)
                if case let .using(_, total) = rt.phase, let left = p.minutesLeft, left > 0 {
                    rt.phase = .using(t: left, total: max(total, left))
                }
                continue
            }
            if riding, let e = elevators[floorId] {
                place(rt, onFloor: floorId, at: elevatorPoint(floorId, e.standAt, rt.index))
            } else {
                place(rt, onFloor: floorId, at: FloorPoint(u: p.u, v: p.v))
            }
            rt.direction = p.direction
            idle(rt, badge: nil, 0.2, 1)
        }
    }

    // MARK: time

    /// Advances sim time by `minutes` (1 sim minute = 1 real second at ×1), in steps of 1/30 minute; a remainder under
    /// a step waits for the next call. At most `stepCap` minutes per call (the rest is dropped); non-finite or
    /// negative steps nothing.
    public func step(minutes: Double) {
        guard minutes.isFinite, minutes > 0 else { return }
        pending = min(pending + minutes, Self.stepCap)
        let n = Int((pending * 30 + 1e-9).rounded(.down))
        guard n > 0 else { return }
        pending = max(0, pending - Double(n) / 30)
        for _ in 0..<n { tick() }
    }

    /// Opening the office after a while: steps `min(minutes, 30)` sim minutes at once, in the same small steps. The
    /// cats end wherever that leaves them (the walks it took are never drawn).
    public func catchUp(minutes: Double) {
        guard minutes.isFinite, minutes > 0 else { return }
        step(minutes: min(minutes, Self.catchUpCap))
    }

    /// simulation-engine.ts step: needs decay, then each cat moves on.
    private func tick() {
        steps += 1
        let dt = SimNeeds.step
        for rt in runtimes {
            decayNeeds(rt, dt)
            stepAgent(rt, dt)
        }
    }

    /// simulation-engine.ts decayNeeds 1100-1112.
    private func decayNeeds(_ rt: Runtime, _ dt: Double) {
        rt.needs.decay(state: rt.state, dt: dt)
        if rt.phase.label != "using" { rt.expression = rt.needs.lowest < 15 ? "sad" : "default" }
    }

    /// simulation-engine.ts stepAgent 1115-1162.
    private func stepAgent(_ rt: Runtime, _ dt: Double) {
        stepHop(rt, dt)
        switch rt.phase {
        case let .waiting(t):
            let left = t - dt
            rt.phase = left <= 0 ? .deciding : .waiting(t: left)
        case .deciding:
            decide(rt)
        case .hoppingDown:
            if rt.hop == nil {
                rt.perch = nil
                startWalking(rt)
            }
        case .walking:
            walk(rt, dt)
        case let .elevatorOut(t, to):
            let left = t - dt
            if left <= 0 {
                let floors = abs(to - rt.floor)
                rt.phase = .elevatorRide(t: Self.elevatorRideBase + Self.elevatorRidePerFloor * Double(floors), to: to)
            } else {
                rt.phase = .elevatorOut(t: left, to: to)
            }
        case let .elevatorRide(t, to):
            let left = t - dt
            if left <= 0 { arriveByElevator(rt, to) } else { rt.phase = .elevatorRide(t: left, to: to) }
        case let .elevatorIn(t):
            let left = t - dt
            if left <= 0 { routeToTarget(rt) } else { rt.phase = .elevatorIn(t: left) }
        case let .using(t, total):
            use(rt, t: t, total: total, dt)
        }
    }

    // MARK: choosing

    /// simulation-engine.ts decide 1167-1203. A spare has no directive: it chooses freely, working only at its own desk
    /// (or hot-desking without one, decision-engine.ts). A session's cat is idle: directive `idle` (decideDirected
    /// 2094-2113) takes only lounge activities on the Lounge floor, no desk.
    private func decide(_ rt: Runtime) {
        decisions += 1
        let choice = SimChoice.choose(
            floors: floors, floorId: rt.floor, position: rt.position, needs: rt.needs,
            minutesSinceWork: time - rt.lastWorkMinute, lastSpotId: rt.lastSpotId,
            ownDeskId: rt.cat.isSpare ? rt.cat.deskSpotId : nil, rng: &rng,
            isFree: { [unowned self] in self.isFree($0) },
            canReach: { [unowned self] in self.canReach(rt, $0, $1) },
            only: rt.cat.isSpare ? nil : { floor, spot in
                floor.id == SpareRoster.loungeFloor && SimActivities.activity(for: spot)?.lounge == true
            })
        // decideDirected 2094-2113: an idle session's cat with nothing to take stands 2–4 minutes.
        guard let choice else {
            rt.cat.isSpare ? idle(rt, badge: nil, 3, 6) : idle(rt, badge: nil, 2, 4)
            return
        }
        guard let slot = reserve(choice.spot, rt.cat.id) else {
            rt.cat.isSpare ? idle(rt, badge: "Waiting", 1, 2) : idle(rt, badge: nil, 2, 4)
            return
        }
        rt.travelled = 0
        rt.target = Target(floor: choice.floorId, spot: choice.spot, def: choice.activity, slot: slot,
                           point: slotPoint(choice.floorId, choice.spot, slot))
        routeToTarget(rt)
    }

    /// simulation-engine.ts canReach 1205-1212 (no hazards): same floor, connected on the walking grid; another floor,
    /// both floors' elevators connected to the cat and to the spot.
    private func canReach(_ rt: Runtime, _ floorId: Int, _ spot: RoomSpot) -> Bool {
        guard let here = grids[rt.floor] else { return false }
        if floorId == rt.floor { return Self.connected(here, rt.position, spot.standAt) }
        guard let there = grids[floorId], let from = elevators[rt.floor], let to = elevators[floorId] else { return false }
        return Self.connected(here, rt.position, from.standAt) && Self.connected(there, to.standAt, spot.standAt)
    }

    /// nav-grid.ts connected.
    static func connected(_ nav: NavGrid, _ a: FloorPoint, _ b: FloorPoint) -> Bool {
        let ra = nav.regionOf(a)
        return ra != 0 && ra == nav.regionOf(b)
    }

    /// simulation-engine.ts idle 1214-1222: stand, then choose again after range(min, max) minutes.
    private func idle(_ rt: Runtime, badge: String?, _ min: Double, _ max: Double) {
        rt.state = .idle
        rt.gesture = "both-down"
        rt.pose = "stand"
        rt.usingSpotId = nil
        rt.badge = badge
        rt.phase = .waiting(t: rng.range(min, max))
    }

    // MARK: reservations (simulation-engine.ts 1035-1080)

    private func slotsOf(_ spot: RoomSpot) -> [String?] {
        occupancy[spot.id] ?? Array(repeating: nil, count: max(1, spot.capacity))
    }

    private func isFree(_ spot: RoomSpot) -> Bool { !taken.contains(spot.id) && slotsOf(spot).contains { $0 == nil } }

    /// Reserve a slot on a spot; the slot index, or nil when full.
    private func reserve(_ spot: RoomSpot, _ id: String) -> Int? {
        if taken.contains(spot.id) { return nil }
        var slots = slotsOf(spot)
        guard let i = slots.firstIndex(where: { $0 == nil }) else { return nil }
        slots[i] = id
        occupancy[spot.id] = slots
        return i
    }

    private func release(_ rt: Runtime) {
        if let t = rt.target, var slots = occupancy[t.spot.id], slots.indices.contains(t.slot), slots[t.slot] == rt.cat.id {
            slots[t.slot] = nil
            occupancy[t.spot.id] = slots
        }
        rt.target = nil
    }

    /// simulation-engine.ts slotPoint.
    private func slotPoint(_ floorId: Int, _ spot: RoomSpot, _ slot: Int) -> FloorPoint {
        if spot.slots.indices.contains(slot) { return spot.slots[slot] }
        let off = Self.slotOffsets[slot % Self.slotOffsets.count]
        let p = FloorPoint(u: spot.standAt.u + off.u, v: spot.standAt.v + off.v)
        return slot > 0 && grids[floorId]?.isOpenAt(p) == true ? p : spot.standAt
    }

    /// simulation-engine.ts elevatorPoint: cats wait spread out in front of the doors.
    private func elevatorPoint(_ floorId: Int, _ standAt: FloorPoint, _ index: Int) -> FloorPoint {
        let k = Double(index % 3 - 1)
        let p = FloorPoint(u: standAt.u + k * Self.elevatorWaitSpread.u, v: standAt.v + k * Self.elevatorWaitSpread.v)
        return grids[floorId]?.isOpenAt(p) == true ? p : standAt
    }

    // MARK: walking

    /// simulation-engine.ts routeToTarget 1225-1290: a path to the target (or, on another floor, to this floor's
    /// elevator); none: release and stand, "Lost".
    private func routeToTarget(_ rt: Runtime) {
        guard let t = rt.target else { rt.phase = .deciding; return }
        let sameFloor = t.floor == rt.floor
        let goal = sameFloor ? t.point : elevators[rt.floor].map { elevatorPoint(rt.floor, $0.standAt, rt.index) }
        guard let goal, let path = grids[rt.floor]?.findPath(from: rt.position, to: goal) else {
            release(rt)
            idle(rt, badge: "Lost", 1.5, 3)
            return
        }
        rt.path = path
        rt.gesture = "both-down"
        rt.pose = "stand"
        rt.usingSpotId = nil
        rt.badge = sameFloor ? "Heading to the \(t.spot.label.lowercased())" : Self.elevatorBadge
        let leaves = pathLeaves(rt, path)
        // Re-chose the spot it is standing at: use it again without a walk or a hop.
        if sameFloor && !leaves {
            if let last = path.last { rt.position = last }
            rt.path = []
            arrive(rt)
            return
        }
        // Off the step or seat first, then walk; off a prop, the hop lands on the floor next to it, where the path starts.
        if rt.groundLift > 0 && leaves {
            startHop(rt, to: 0, toPos: rt.perch != nil ? path.first : nil)
            rt.phase = .hoppingDown
            return
        }
        startWalking(rt)
    }

    private func startWalking(_ rt: Runtime) {
        rt.phase = .walking
        rt.state = .walking
    }

    private func pathLeaves(_ rt: Runtime, _ path: [FloorPoint]) -> Bool {
        guard let f = floor(rt.floor) else { return false }
        return path.contains { f.pxDistance(rt.position, $0) > 1 }
    }

    /// simulation-engine.ts walk 1331-1356: speed × dt world px along the path; an elbow ends the step's walk.
    private func walk(_ rt: Runtime, _ dt: Double) {
        guard let f = floor(rt.floor) else { return }
        var budget = rt.speedPx * dt
        while budget > 0, let next = rt.path.first {
            let seg = f.pxDistance(rt.position, next)
            // A step too small to see (onto a spot's exact point) doesn't turn the cat.
            if seg >= NavGrid.minLegPx { rt.direction = Self.direction(from: rt.position, to: next) }
            if seg <= budget {
                let from = rt.position
                rt.position = next
                rt.path.removeFirst()
                budget -= seg
                rt.travelled += seg
                if let after = rt.path.first, Self.stepAxis(from, next) != Self.stepAxis(next, after) { break }
            } else {
                let k = budget / seg
                rt.travelled += budget
                rt.position = FloorPoint(u: rt.position.u + (next.u - rt.position.u) * k, v: rt.position.v + (next.v - rt.position.v) * k)
                budget = 0
            }
        }
        if rt.path.isEmpty { arrive(rt) }
    }

    /// simulation-engine.ts stepAxis.
    static func stepAxis(_ a: FloorPoint, _ b: FloorPoint) -> Character { abs(b.u - a.u) >= abs(b.v - a.v) ? "u" : "v" }

    /// floor-math.ts getDirectionFromMovement with DEFAULT_DIRECTION_MAPPING.
    static func direction(from: FloorPoint, to: FloorPoint) -> String {
        let du = to.u - from.u, dv = to.v - from.v
        if abs(du) >= abs(dv) { return du > 0 ? "front-left" : "back-right" }
        return dv > 0 ? "front-right" : "back-left"
    }

    // MARK: hops (simulation-engine.ts startHop / stepHop / land)

    private func startHop(_ rt: Runtime, to: Double, toPos: FloorPoint? = nil) {
        let moves = toPos != nil && floor(rt.floor).map { $0.pxDistance(rt.position, toPos!) > 0.5 } == true
        if rt.hop == nil && abs(rt.groundLift - to) < 0.01 && !moves { return }
        rt.hop = Hop(from: rt.groundLift, to: to, k: 0, fromPos: moves ? rt.position : nil, toPos: moves ? toPos : nil)
    }

    private func stepHop(_ rt: Runtime, _ dt: Double) {
        guard var hop = rt.hop else { return }
        hop.k = min(1, hop.k + dt / Self.hopMinutes)
        let eased = 1 - (1 - hop.k) * (1 - hop.k)
        rt.groundLift = hop.from + (hop.to - hop.from) * eased
        if let a = hop.fromPos, let b = hop.toPos {
            rt.position = FloorPoint(u: a.u + (b.u - a.u) * eased, v: a.v + (b.v - a.v) * eased)
        }
        if hop.k >= 1 {
            rt.groundLift = hop.to
            rt.hop = nil
        } else {
            rt.hop = hop
        }
    }

    private func land(_ rt: Runtime) {
        guard let hop = rt.hop else { return }
        rt.groundLift = hop.to
        if let p = hop.toPos { rt.position = p }
        rt.hop = nil
    }

    // MARK: arriving and using

    /// simulation-engine.ts arrive 1358-1400: at another floor's target, step into the elevator; else use the spot for
    /// range(duration) minutes.
    private func arrive(_ rt: Runtime) {
        guard let t = rt.target else { rt.phase = .deciding; return }
        if t.floor != rt.floor {
            rt.state = .ridingElevator
            rt.pose = "stand"
            rt.usingSpotId = nil
            rt.direction = "back-left"
            rt.badge = Self.elevatorBadge
            rt.phase = .elevatorOut(t: Self.elevatorFade, to: t.floor)
            return
        }
        let def = t.def
        let total = rng.range(def.duration.min, def.duration.max)
        rt.phase = .using(t: total, total: total)
        // slotFacing: RoomSpot keeps no per-slot facing, so every occupant faces the spot's way.
        rt.direction = t.spot.facing
        applyActivityPose(rt, def, t.spot, facing: t.spot.facing)
        if t.spot.lift > 0 && t.spot.kind != "desk" {
            // perches: up onto the seat from the floor next to it.
            rt.perch = t.spot.id
            startHop(rt, to: t.spot.lift, toPos: t.point)
        } else {
            startHop(rt, to: t.spot.lift)
        }
        if let arrival = def.arrival {
            rt.gesture = arrival.gesture
            rt.state = arrival.state
            rt.arrivalLeft = arrival.seconds
        }
    }

    /// simulation-engine.ts applyActivityPose 1402-1430 (the cat's own sleeping sprites aside: a nap in a seat facing
    /// front is drawn asleep).
    private func applyActivityPose(_ rt: Runtime, _ def: SimActivity, _ spot: RoomSpot, facing: String) {
        rt.pose = spot.kind == "meeting" ? "stand" : spot.pose ?? "stand"
        if rt.pose == "sit" && def.asleep && facing.hasPrefix("front") { rt.pose = "sleep" }
        rt.usingSpotId = spot.id
        rt.state = def.state
        rt.gesture = def.gesture
        rt.expression = def.expression
        rt.badge = def.label
        rt.arrivalLeft = 0
    }

    /// simulation-engine.ts arriveByElevator 1432-1445.
    private func arriveByElevator(_ rt: Runtime, _ toFloor: Int) {
        let to = floor(toFloor) != nil ? toFloor : fallbackFloor()
        rt.floor = to
        rt.travelled += 1
        rt.position = elevators[to].map { elevatorPoint(to, $0.standAt, rt.index) } ?? FloorPoint(u: 0.5, v: 0.5)
        rt.direction = "front-right"
        rt.state = .walking
        rt.phase = .elevatorIn(t: Self.elevatorFade)
    }

    /// simulation-engine.ts use 1447-1516 for a cat with no directive: the arrival pose runs out, a cat standing at a
    /// desk now and then reaches for the keyboard, the needs gain gain / total × dt, and when the time is up it leaves
    /// the spot and stands a moment before choosing again.
    private func use(_ rt: Runtime, t: Double, total: Double, _ dt: Double) {
        guard let target = rt.target else { rt.phase = .deciding; return }
        if rt.arrivalLeft > 0 {
            rt.arrivalLeft -= dt
            if rt.arrivalLeft <= 0 {
                rt.gesture = target.def.gesture
                rt.state = target.def.state
            }
        }
        if target.def.kind == "desk" && rt.pose == "stand" && rt.arrivalLeft <= 0 {
            rt.gestureLeft -= dt
            if rt.gestureLeft <= 0 {
                let reach = rt.gesture == "both-down" && rng.chance(0.4)
                rt.gesture = reach ? rng.pick(Self.reachGestures) : "both-down"
                rt.gestureLeft = reach ? rng.range(0.6, 1.4) : rng.range(1.5, 4)
            }
        }
        rt.needs = rt.needs.gained(target.def, total: total, dt: dt)
        let left = t - dt
        rt.phase = .using(t: left, total: total)
        if left > 0 { return }

        if target.def.kind == "desk" { rt.lastWorkMinute = time }
        rt.lastSpotId = target.spot.id
        release(rt)
        rt.expression = "default"
        idle(rt, badge: nil, 0.3, 1.5)
    }

    // MARK: output

    /// The layout's input, as step 1's mirror type (places-share.ts buildPlaces): session cats' places by agent id,
    /// and, with `showSpares`, the spare cats under "spare:<id>" with their names. `at` is the sim time in ms.
    /// `forDrawing` (what the office draws): a walking cat is already where its walk on this floor ends (the spot, or
    /// the elevator), so the view walks it there once, along the same walking grid at its own pace, as it walks a
    /// mirrored cat to its next place; `at` is 0, so stepping alone changes nothing drawn.
    public func output(showSpares: Bool, forDrawing: Bool = false) -> OfficeMirror {
        var mirror = OfficeMirror(places: [:])
        for rt in runtimes {
            if rt.cat.isSpare && !showSpares { continue }
            let p = place(of: rt, forDrawing: forDrawing)
            if rt.cat.isSpare { mirror.spares.append(p) } else { mirror.places[rt.cat.id] = p }
        }
        return mirror
    }

    private func place(of rt: Runtime, forDrawing: Bool) -> MirrorPlace {
        let walking = rt.phase == .walking || rt.phase == .hoppingDown
        let ahead = forDrawing && walking ? rt.path.last : nil
        let at = ahead ?? rt.position
        // Facing the way it comes in at the end (the last point at least a visible leg back), as it will on arrival.
        var direction = rt.direction
        if let end = ahead, let f = floor(rt.floor),
           let from = ([rt.position] + rt.path.dropLast()).last(where: { f.pxDistance($0, end) >= NavGrid.minLegPx }) {
            direction = Self.direction(from: from, to: end)
        }
        let spot = rt.usingSpotId.flatMap { id in floor(rt.floor)?.spots.first { $0.id == id } }
        let def = spot.flatMap { $0.kind == "elevator" ? nil : SimActivities.activity(for: $0) }
        let phase = rt.phase.shared
        let kind = def?.kind ?? (phase == "elevator" ? "elevator" : "other")
        var ridingTo: Int?
        var minutesLeft: Double?
        switch rt.phase {
        case let .elevatorOut(_, to), let .elevatorRide(_, to): ridingTo = to
        case let .using(t, _): minutesLeft = t.rounded(.up)
        default: break
        }
        return MirrorPlace(
            floor: rt.floor, u: at.u, v: at.v, direction: direction, state: rt.state.rawValue,
            gesture: rt.gesture, expression: rt.expression, asleep: def?.asleep == true || rt.pose == "sleep",
            activity: rt.badge.map { .init(kind: kind, label: $0) }, spotId: rt.usingSpotId, minutesLeft: minutesLeft,
            phase: phase, ridingTo: ridingTo, catId: rt.cat.catId, at: forDrawing ? 0 : time * 60_000,
            name: rt.cat.isSpare ? rt.cat.name : nil, key: rt.cat.isSpare ? "spare:\(rt.cat.id)" : nil)
    }
}

import Foundation

/// The app's side of the office simulation (spec section 3): which cats OfficeSim runs, when it steps, and whose places
/// the office draws. AppState owns one and steps it with a timer only while the office (Office tab or hover peek) is on
/// screen; one sim minute per real second, as Cat Office at ×1.
public final class SimHost {
    public let sim: OfficeSim
    /// The office is on screen: only then does the sim step (`tick`).
    public private(set) var visible = false
    /// A Cat Office page shares its places: the mirror wins and the sim pauses.
    public private(set) var live = false
    /// When the sim was last brought up to now (stepped, caught up, seeded, or the clock started).
    public private(set) var lastStep: Date
    /// Bumped when the cats were put where the sim has them without walking there (the catch-up on opening, a render's
    /// advance): the office places them instead of walking every cat at once.
    public private(set) var placement = 0
    /// The cats it runs now: idle sessions' cats, then the spares (with the switch on).
    public private(set) var cats: [SimCat] = []
    /// The desks working and waiting cats sit at, as FloorPlan seats them: the sim's cats keep off them.
    public private(set) var takenSpotIds: Set<String> = []
    /// The browser's places while live, to start the sim from when they stop.
    private var lastLive: OfficeMirror?
    /// What the office draws now (the last `mirror` result): seatings count each cat on the floor it's drawn on.
    private var drawn = OfficeMirror.off
    private var agents: [OfficeAgent] = []
    private var building = Building.fallback
    private var rooms: [Int: BuiltRoom] = [:]
    private var grids: [Int: NavGrid] = [:]
    /// A tick this long after the last one (the Mac slept with the office open) is a catch-up and a placement.
    public static let stall: TimeInterval = 2
    /// Each cat's minutes left at its spot (OfficeMirror.minutesLeft of what the office draws), kept out of `mirror`'s
    /// result so a countdown changes nothing the layout compares: the hover card reads these.
    public private(set) var minutesLeft: [String: Double] = [:]
    /// Who sits where on each floor: the one seating both office views draw rule-placed cats with (see `reseat`).
    public private(set) var seatings: [Int: FloorSeating] = [:]

    public init(seed: UInt32, now: Date) {
        sim = OfficeSim(seed: seed)
        lastStep = now
    }

    /// The cats to run from the feed's agents: each idle main agent's cat (helpers stay with their parent, by the
    /// rules), and, with `showSpares`, the spare roster from cats.json. A session that stops working joins where it
    /// stands, at its desk on its floor; one already running keeps going. Working and waiting cats' desks are taken.
    public func update(agents: [OfficeAgent], building: Building, rooms: [Int: BuiltRoom], grids: [Int: NavGrid],
                       spares: [SpareRoster.Cat], showSpares: Bool) {
        // Where each rule-placed cat sat until now: a cat that stops working stands up from there.
        var deskOf: [String: (floor: Int, at: FloorPoint)] = [:]
        for (floorId, seating) in seatings {
            guard let room = rooms[floorId] else { continue }
            let desks = Dictionary(room.desks.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
            for (i, id) in seatedDesks(floorId, seating, building, room) { if let d = desks[id] { deskOf[i] = (floorId, d.standAt) } }
        }
        self.agents = agents
        self.building = building
        self.rooms = rooms
        self.grids = grids
        reseat()

        let running = Dictionary(cats.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        // No built floor yet (the catalogue is still loading): nobody to run; they join once the rooms are in.
        guard !OfficeSim.floors(building: building, rooms: rooms).isEmpty else {
            cats = []
            sim.setCats([], building: building, rooms: rooms, grids: grids, takenSpotIds: takenSpotIds)
            return
        }
        var wanted: [SimCat] = agents.filter { $0.status == .idle && !$0.isSubagent }.map { a in
            if let cat = running[a.id], !cat.isSpare { return cat }
            let desk = deskOf[a.id]
            return SimCat(id: a.id, isSpare: false, floor: desk?.floor, at: desk?.at)
        }
        if showSpares {
            wanted += SpareRoster.roster(floors: OfficeSim.floors(building: building, rooms: rooms), cats: spares).map(SimCat.init(spare:))
        }
        cats = wanted
        sim.setCats(wanted, building: building, rooms: rooms, grids: grids, takenSpotIds: takenSpotIds)
    }

    /// Who sits where on every floor, as both office views draw it (FloorPlan.seating over the cats on the floor with
    /// what the office draws now, each floor kept from last time; a built floor over its built desks and seats), and
    /// the desks the rule-placed cats there use: taken for the sim. True when the taken desks changed.
    @discardableResult
    private func reseat() -> Bool {
        var next: [Int: FloorSeating] = [:]
        var taken = Set<String>()
        for f in building.floors {
            let here = FloorPlan.cats(on: f.id, agents: agents, in: building, mirror: drawn)
            guard let room = rooms[f.id] else {
                next[f.id] = FloorPlan.seating(on: f, agents: here, previous: seatings[f.id])
                continue
            }
            let seating = FloorPlan.seating(on: Self.seatFloor(f, room), agents: here, previous: seatings[f.id], seats: room.seats.count)
            next[f.id] = seating
            guard !f.isLounge else { continue }
            // A cat drawn where the office has it (mirrored) isn't at its rule desk.
            for (agent, desk) in seatedDesks(f.id, seating, building, room) where drawn.places[agent] == nil { taken.insert(desk) }
        }
        seatings = next
        defer { takenSpotIds = taken }
        return taken != takenSpotIds
    }

    /// (agent id, desk id) for each cat seated at one of the floor's built desks.
    private func seatedDesks(_ floorId: Int, _ seating: FloorSeating, _ building: Building, _ room: BuiltRoom) -> [(String, String)] {
        guard let f = building.floor(id: floorId) else { return [] }
        let ids = Self.seatFloor(f, room).desks.map(\.id)
        return seating.desks.enumerated().compactMap { i, id in id.flatMap { a in ids.indices.contains(i) ? (a, ids[i]) : nil } }
    }

    /// The floor as seated on its built room: only the desks the room could place (unknown designs are skipped).
    public static func seatFloor(_ floor: Floor, _ room: BuiltRoom) -> Floor {
        let ids = Set(room.desks.map(\.id))
        var f = floor
        f.desks = floor.desks.filter { ids.contains($0.id) }
        return f
    }

    /// The office opened or closed. Opening simulates the time since the last step at once (catch-up: at most 30 sim
    /// minutes), a placement; nothing runs while closed. While the mirror is live there is nothing to catch up.
    public func setVisible(_ on: Bool, now: Date) {
        guard on != visible else { return }
        visible = on
        guard on else { return }
        if !live {
            sim.catchUp(minutes: max(0, now.timeIntervalSince(lastStep)))
            placement += 1
        }
        lastStep = now
    }

    /// The step timer: the time since the last step, while the office is open and the mirror isn't live.
    public func tick(now: Date) {
        guard visible, !live else { return }
        let gap = now.timeIntervalSince(lastStep)
        if gap > Self.stall {
            sim.catchUp(minutes: gap)
            placement += 1
        } else {
            sim.step(minutes: gap)
        }
        lastStep = now
    }

    /// What the office draws: the browser's places while they're live (`live`), else the sim's (OfficeSim.output
    /// forDrawing). The first time they aren't, the sim starts from the browser's last places. Either way without
    /// minutes left (OfficeMirror.withoutMinutes): those are in `minutesLeft`.
    public func mirror(_ browser: OfficeMirror, live isLive: Bool, now: Date) -> OfficeMirror {
        if isLive {
            live = true
            lastLive = browser
            minutesLeft = browser.minutesLeft
            let out = browser.withoutMinutes
            drawing(out)
            return out
        }
        if live {
            live = false
            if let last = lastLive { sim.seed(from: last) }
            lastLive = nil
            lastStep = now
        }
        var full = sim.output(showSpares: true, forDrawing: true)
        if drawing(full.withoutMinutes) {
            // Desks were freed or taken: a sim cat headed for one now taken leaves it.
            full = sim.output(showSpares: true, forDrawing: true)
            drawing(full.withoutMinutes)
        }
        minutesLeft = full.minutesLeft
        return full.withoutMinutes
    }

    /// Notes what the office draws now and seats the floors with it; true when that changed the taken desks (passed on
    /// to the sim).
    @discardableResult
    private func drawing(_ out: OfficeMirror) -> Bool {
        guard out != drawn else { return false }
        drawn = out
        guard reseat() else { return false }
        sim.setCats(cats, building: building, rooms: rooms, grids: grids, takenSpotIds: takenSpotIds)
        return true
    }

    /// Renders only (CLAUDEBAR_SIM_ADVANCE): `minutes` simulated at once, past catch-up's cap, as a placement.
    public func advance(minutes: Double, now: Date) {
        var left = minutes.isFinite ? minutes : 0
        while left > 0 {
            sim.catchUp(minutes: min(left, OfficeSim.catchUpCap))
            left -= OfficeSim.catchUpCap
        }
        placement += 1
        lastStep = now
    }
}

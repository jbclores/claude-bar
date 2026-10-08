import Foundation
import Testing
@testable import ClaudeBarCore

/// OfficeSim on the user fixture building, with fixed seeds.
@Suite struct OfficeSimTests {
    let building: Building
    let rooms: [Int: BuiltRoom]
    let grids: [Int: NavGrid]

    init() throws {
        building = try #require(Building.parse(building: fixture("rooms/user/building.json"), parts: fixture("rooms/user/room-parts.json")))
        let catalogue = try RoomCatalogueTests().catalogue("user")
        var rooms: [Int: BuiltRoom] = [:], grids: [Int: NavGrid] = [:]
        for f in building.floors {
            guard let room = RoomGeometry.build(floor: f, catalogue: catalogue) else { continue }
            rooms[f.id] = room
            grids[f.id] = NavGrid(floor: f, room: room)
        }
        self.rooms = rooms
        self.grids = grids
    }

    /// `rooms` with only the floors listed, each floor's spots cut down by `keep`.
    func only(_ floors: [Int], keep: (Int, RoomSpot) -> Bool = { _, _ in true }) -> [Int: BuiltRoom] {
        var out: [Int: BuiltRoom] = [:]
        for id in floors {
            guard var r = rooms[id] else { continue }
            r.spots = r.spots.filter { keep(id, $0) }
            out[id] = r
        }
        return out
    }

    func runtime(_ sim: OfficeSim, _ id: String) -> OfficeSim.Runtime? { sim.runtimes.first { $0.cat.id == id } }

    func routeLength(_ sim: OfficeSim, floor: Int, from: FloorPoint, path: [FloorPoint]) -> Double {
        var at = from, total = 0.0
        for p in path { total += sim.floor(floor)!.pxDistance(at, p); at = p }
        return total
    }

    @Test func spotsCarryTheirLabelAndCapacity() throws {
        let all = rooms.values.flatMap(\.spots)
        let coffee = try #require(all.first { $0.label == "Coffee counter" })
        #expect(coffee.capacity == 2 && coffee.slots.count == 2)
        let desk = try #require(all.first { $0.kind == "desk" })
        #expect(desk.capacity == 1 && !desk.label.isEmpty)
        #expect(all.filter { $0.kind != "elevator" }.allSatisfy { !$0.label.isEmpty })
    }

    /// choose → walk (route length / walk speed) → use (a duration in the activity's range, gains applied) → choose again.
    @Test func oneCatsFullCycle() throws {
        let sim = OfficeSim(seed: 7)
        sim.setCats([SimCat(id: "s1", isSpare: true, name: "Mochi", catId: "cat-1", floor: 1, at: FloorPoint(u: 0.5, v: 0.5))],
                    building: building, rooms: only([1]), grids: grids)
        let dt = 1.0 / 30
        // Choose and set off.
        var guardSteps = 0
        while runtime(sim, "s1")!.phase.label != "walking" {
            sim.step(minutes: dt); guardSteps += 1
            try #require(guardSteps < 30 * 10, "never set off")
        }
        let rt = try #require(runtime(sim, "s1"))
        let target = try #require(rt.target)
        #expect(target.floor == 1)
        // The walk takes the route's length at the cat's speed (Cat Office's 190 px per sim minute, × its own 0.85…1.15).
        #expect(rt.speedPx >= 190 * 0.85 && rt.speedPx <= 190 * 1.15)
        let length = routeLength(sim, floor: 1, from: rt.position, path: rt.path)
        let legs = rt.path.count
        #expect(length > 0)
        var walked = 0
        while rt.phase.label == "walking" { sim.step(minutes: dt); walked += 1; try #require(walked < 30 * 60) }
        let expected = length / rt.speedPx
        // Each step walks speed × dt; an elbow ends a step's walk early (simulation-engine.ts 1348), so at most one step more per leg.
        #expect(Double(walked) * dt >= expected - 1e-9)
        #expect(Double(walked) * dt <= expected + Double(legs + 1) * dt)
        // Using: a duration within the activity's range.
        guard case let .using(_, total) = rt.phase else { Issue.record("not using after the walk: \(rt.phase)"); return }
        let def = target.def
        #expect(total >= def.duration.min && total <= def.duration.max)
        #expect(rt.usingSpotId == target.spot.id)
        let out = sim.output(showSpares: true).spares.first
        #expect(out?.phase == "using" && out?.spotId == target.spot.id && out?.activity?.kind == def.kind)
        #expect(out?.minutesLeft == total.rounded(.up))
        // Needs: each step decays (in the cat's state) then gains gain / total × dt, as the engine does.
        var want = rt.needs
        var used = 0
        while rt.phase.label == "using" {
            let state = rt.state
            want.decay(state: state, dt: dt)
            want = want.gained(def, total: total, dt: dt)
            sim.step(minutes: dt); used += 1
            try #require(used < 30 * 60)
        }
        #expect(abs(Double(used) * dt - total) <= dt + 1e-9)
        for key in SimNeedKey.allCases { #expect(abs(rt.needs[key] - want[key]) < 1e-9, "\(key)") }
        #expect(rt.lastSpotId == target.spot.id)
        #expect(rt.target == nil && rt.phase.label == "waiting")
        // Chooses again.
        var again = 0
        while rt.target == nil { sim.step(minutes: dt); again += 1; try #require(again < 30 * 10, "never chose again") }
        #expect(sim.decisions >= 2)
    }

    /// A spot on another floor: walk to the elevator, ride (phase elevator, ridingTo), then use the spot there.
    @Test func anotherFloorTakesTheElevator() throws {
        let sim = OfficeSim(seed: 3)
        // Floor 1 has nothing to use: every choice is on floor 2.
        let rooms = only([1, 2], keep: { floor, s in floor == 2 || s.kind == "elevator" })
        // A spare: an idle session's cat stays on the Lounge floor (directive idle).
        sim.setCats([SimCat(id: "a1", isSpare: true, floor: 1, at: FloorPoint(u: 0.5, v: 0.5))], building: building, rooms: rooms, grids: grids)
        var sawRide = false, sawWalkToLift = false
        for _ in 0..<(30 * 30) {
            sim.step(minutes: 1.0 / 30)
            let p = try #require(sim.output(showSpares: true).spares.first)
            if p.phase == "walking" && p.floor == 1 { sawWalkToLift = true }
            if p.phase == "elevator" && p.ridingTo == 2 {
                #expect(p.floor == 1 && p.activity?.kind == "elevator" && p.activity?.label == "Taking the elevator")
                #expect(p.state == "riding-elevator")
                sawRide = true
            }
            if p.phase == "using" {
                #expect(p.floor == 2)
                break
            }
        }
        #expect(sawWalkToLift && sawRide)
        #expect(runtime(sim, "a1")?.floor == 2)
        #expect(runtime(sim, "a1")?.phase.label == "using")
    }

    /// Two cats never take the same place on a spot: claims never exceed a spot's capacity.
    @Test func claimsNeverExceedCapacity() throws {
        // One single-cat spot on the floor, three cats.
        let one = try #require(rooms[1]?.spots.first { $0.kind != "elevator" && $0.kind != "desk" && $0.capacity == 1 })
        let sim = OfficeSim(seed: 11)
        let cats = (1...3).map { SimCat(id: "c\($0)", isSpare: true, floor: 1, at: FloorPoint(u: 0.5, v: 0.5)) }
        sim.setCats(cats, building: building, rooms: only([1], keep: { _, s in s.id == one.id || s.kind == "elevator" }), grids: grids)
        var used = 0
        for _ in 0..<(30 * 90) {
            sim.step(minutes: 1.0 / 30)
            let claims = sim.runtimes.compactMap(\.target?.spot.id)
            #expect(claims.filter { $0 == one.id }.count <= 1)
            used = max(used, sim.output(showSpares: true).spares.filter { $0.spotId == one.id }.count)
        }
        #expect(used == 1)

        // The whole building, several cats: no spot ever holds more cats than it takes, and no slot two cats.
        let busy = OfficeSim(seed: 5)
        busy.setCats((1...10).map { SimCat(id: "b\($0)", isSpare: $0 % 2 == 0, floor: 1, at: FloorPoint(u: 0.5, v: 0.5)) },
                     building: building, rooms: rooms, grids: grids)
        let capacity = Dictionary(rooms.values.flatMap(\.spots).map { ($0.id, $0.capacity) }, uniquingKeysWith: { a, _ in a })
        for _ in 0..<(4 * 60) {
            busy.step(minutes: 0.25)
            var held: [String: Int] = [:]
            var slots = Set<String>()
            for rt in busy.runtimes {
                guard let t = rt.target else { continue }
                held[t.spot.id, default: 0] += 1
                #expect(slots.insert("\(t.spot.id)#\(t.slot)").inserted)
            }
            for (id, n) in held { #expect(n <= max(1, capacity[id] ?? 1), "\(id)") }
        }
    }

    /// A floor with nothing free: the cat stands, waits 3–6 minutes and tries again (simulation-engine.ts 1179-1182).
    @Test func noFreeSpotWaitsAndRetries() throws {
        let sim = OfficeSim(seed: 2)
        sim.setCats([SimCat(id: "w", isSpare: true, floor: 1, at: FloorPoint(u: 0.5, v: 0.5))], building: building,
                    rooms: only([1], keep: { _, s in s.kind == "elevator" }), grids: grids)
        for _ in 0..<2 { sim.step(minutes: 30) } // at most 30 per call
        #expect(abs(sim.time - 60) < 1e-9)
        // First decision within 1.5 min, then one per 3–6 min.
        #expect(sim.decisions >= 10 && sim.decisions <= 21)
        let p = try #require(sim.output(showSpares: true).spares.first)
        #expect(p.phase == "idle" && p.spotId == nil && p.activity == nil && p.floor == 1)
    }

    /// setCats without a cat (its session started working): gone from the output, its spot free again.
    @Test func droppedMidWalkLeavesTheOutput() throws {
        let sim = OfficeSim(seed: 9)
        let a = SimCat(id: "a", isSpare: false, floor: 1, at: FloorPoint(u: 0.5, v: 0.5))
        let b = SimCat(id: "b", isSpare: false, floor: 1, at: FloorPoint(u: 0.4, v: 0.6))
        sim.setCats([a, b], building: building, rooms: rooms, grids: grids)
        var n = 0
        while runtime(sim, "a")?.phase.label != "walking" { sim.step(minutes: 1.0 / 30); n += 1; try #require(n < 30 * 20) }
        let spot = try #require(runtime(sim, "a")?.target?.spot.id)
        sim.setCats([b], building: building, rooms: rooms, grids: grids)
        let out = sim.output(showSpares: false)
        #expect(out.places["a"] == nil && out.places["b"] != nil)
        #expect(!(sim.occupancy[spot] ?? []).contains("a"))
        sim.step(minutes: 5)
        #expect(sim.output(showSpares: false).places["a"] == nil)
    }

    /// seed(from:): each cat carries on at its mirrored spot with its activity and minutes left (restorePlaces).
    @Test func seedKeepsActivitySpotAndMinutesLeft() throws {
        let sim = OfficeSim(seed: 4)
        let spot = try #require(rooms[1]?.spots.first { $0.kind == "bookshelf" } ?? rooms[1]?.spots.first { $0.kind == "sofa" })
        let def = try #require(SimActivities.activity(for: spot))
        sim.setCats([SimCat(id: "s1", isSpare: false, floor: 1, at: FloorPoint(u: 0.5, v: 0.5)),
                     SimCat(id: "agent-2", isSpare: true, name: "Tofu", catId: "cat-2", floor: 1, at: FloorPoint(u: 0.5, v: 0.5))],
                    building: building, rooms: rooms, grids: grids)
        var mirror = OfficeMirror(places: [
            "s1": MirrorPlace(floor: 1, u: spot.standAt.u, v: spot.standAt.v, direction: spot.facing, state: def.state.rawValue,
                              activity: .init(kind: def.kind, label: def.label), spotId: spot.id, minutesLeft: 7, phase: "using", at: 0),
        ])
        mirror.spares = [MirrorPlace(floor: 1, u: 0.3, v: 0.3, direction: "front-left", state: "walking", phase: "walking", at: 0,
                                     name: "Tofu", key: "spare:agent-2")]
        sim.seed(from: mirror)
        #expect(sim.time == 0)
        let out = sim.output(showSpares: true)
        let p = try #require(out.places["s1"])
        #expect(p.spotId == spot.id && p.phase == "using" && p.minutesLeft == 7)
        #expect(p.activity == .init(kind: def.kind, label: def.label))
        #expect(p.floor == 1 && abs(p.u - spot.standAt.u) < 1e-9 && abs(p.v - spot.standAt.v) < 1e-9)
        guard case let .using(t, total) = runtime(sim, "s1")!.phase else { Issue.record("not using"); return }
        #expect(t == 7 && total >= 7)
        // The spare stands where the mirror had it (on open floor) and chooses soon.
        let spare = try #require(out.spares.first { $0.key == "spare:agent-2" })
        #expect(spare.phase == "idle" && spare.name == "Tofu" && spare.catId == "cat-2")
        sim.step(minutes: 1.5)
        #expect(sim.output(showSpares: false).places["s1"]?.minutesLeft == 6)
        sim.step(minutes: 6)
        #expect(runtime(sim, "s1")?.lastSpotId == spot.id)
    }

    @Test func catchUpIsCappedAtThirtyMinutes() {
        let sim = OfficeSim(seed: 1)
        sim.setCats([SimCat(id: "x", isSpare: false, floor: 1, at: FloorPoint(u: 0.5, v: 0.5))], building: building, rooms: rooms, grids: grids)
        sim.catchUp(minutes: 120)
        #expect(sim.time == 30)
        sim.catchUp(minutes: 2.5)
        #expect(sim.time == 32.5)
        sim.catchUp(minutes: -4)
        #expect(sim.time == 32.5)
        // Cats end somewhere drawable: on a floor the building has, on its floor.
        let p = sim.output(showSpares: false).places["x"]
        #expect(p.map { building.floor(id: $0.floor) != nil && (0...1).contains($0.u) && (0...1).contains($0.v) } == true)
    }

    @Test func onlyStepAdvancesTime() {
        let sim = OfficeSim(seed: 1)
        #expect(sim.time == 0)
        sim.setCats([SimCat(id: "x", isSpare: true)], building: building, rooms: rooms, grids: grids)
        _ = sim.output(showSpares: true)
        sim.seed(from: .off)
        sim.setCats([SimCat(id: "x", isSpare: true), SimCat(id: "y", isSpare: false)], building: building, rooms: rooms, grids: grids)
        #expect(sim.time == 0)
        sim.step(minutes: 0.5)
        #expect(sim.time == 0.5)
        sim.step(minutes: 0.01) // less than a step: kept for the next call
        #expect(sim.time == 0.5)
        sim.step(minutes: 0.03)
        #expect(abs(sim.time - (0.5 + 1.0 / 30)) < 1e-12)
    }

    @Test func sparesOnlyWithTheSwitch() throws {
        let sim = OfficeSim(seed: 8)
        let roster = SpareRoster.roster(floors: OfficeSim.floors(building: building, rooms: rooms),
                                        cats: try JSONDecoder().decode(SpareRoster.Manifest.self, from: fixture("rooms/user/cats.json")).cats)
        let spare = try #require(roster.first)
        sim.setCats([SimCat(spare: spare), SimCat(id: "sess", isSpare: false, floor: 1, at: FloorPoint(u: 0.5, v: 0.5))],
                    building: building, rooms: rooms, grids: grids)
        let off = sim.output(showSpares: false)
        #expect(off.spares.isEmpty && Set(off.places.keys) == ["sess"])
        let on = sim.output(showSpares: true)
        #expect(Set(on.places.keys) == ["sess"])
        let p = try #require(on.spares.first)
        #expect(on.spares.count == 1 && p.key == "spare:\(spare.id)" && p.name == spare.name && p.catId == spare.catId)
        // A spare with a desk starts the day at it (simulation-engine.ts createRuntime 1024-1031).
        if let desk = spare.desk {
            #expect(p.spotId == desk.spotId && p.floor == desk.floor && p.phase == "using" && p.activity?.kind == "desk")
        }
        // An idle session's cat never sits down to work: directive idle takes only Lounge activities on floor 1.
        let many = OfficeSim(seed: 21)
        many.setCats((1...6).map { SimCat(id: "s\($0)", isSpare: false, floor: 2, at: FloorPoint(u: 0.5, v: 0.5)) },
                     building: building, rooms: rooms, grids: grids)
        var targets = 0
        for _ in 0..<(2 * 120) {
            many.step(minutes: 0.5)
            for rt in many.runtimes {
                guard let t = rt.target else { continue }
                targets += 1
                #expect(t.spot.kind != "desk" && t.floor == 1 && t.def.lounge, "\(t.spot.id) on \(t.floor)")
            }
        }
        #expect(targets > 0)
    }

    /// simulation-engine.ts 2094-2113: an idle session's cat on the Lounge floor stays there.
    @Test func idleSessionsStayOnTheLoungeFloor() {
        let sim = OfficeSim(seed: 13)
        sim.setCats((1...8).map { SimCat(id: "i\($0)", isSpare: false, floor: 1, at: FloorPoint(u: 0.5, v: 0.5)) },
                    building: building, rooms: rooms, grids: grids)
        var used = Set<String>()
        for _ in 0..<(30 * 60) {
            sim.step(minutes: 1.0 / 30)
            for (_, p) in sim.output(showSpares: false).places {
                #expect(p.floor == 1 && p.phase != "elevator")
                if let k = p.activity?.kind, p.phase == "using" { used.insert(k) }
            }
        }
        #expect(!used.isEmpty && used.allSatisfy { SimActivities.all[$0]?.lounge == true })
    }

    /// A working or waiting session's desk is taken: a spare there leaves it and doesn't come back while it is.
    @Test func takenDesksAreLeftAndAvoided() throws {
        let sim = OfficeSim(seed: 6)
        let roster = SpareRoster.roster(floors: OfficeSim.floors(building: building, rooms: rooms),
                                        cats: try JSONDecoder().decode(SpareRoster.Manifest.self, from: fixture("rooms/user/cats.json")).cats)
        let spare = try #require(roster.first { $0.desk != nil })
        let desk = try #require(spare.desk?.spotId)
        sim.setCats([SimCat(spare: spare)], building: building, rooms: rooms, grids: grids)
        #expect(sim.output(showSpares: true).spares.first?.spotId == desk)
        sim.setCats([SimCat(spare: spare)], building: building, rooms: rooms, grids: grids, takenSpotIds: [desk])
        #expect(sim.runtimes.first?.target == nil)
        #expect(sim.output(showSpares: true).spares.first?.spotId == nil)
        for _ in 0..<(4 * 180) {
            sim.step(minutes: 0.25)
            #expect(sim.runtimes.first?.target?.spot.id != desk)
        }
        // A spare joining with its desk taken doesn't start the day at it.
        let fresh = OfficeSim(seed: 6)
        fresh.setCats([SimCat(spare: spare)], building: building, rooms: rooms, grids: grids, takenSpotIds: [desk])
        #expect(fresh.runtimes.first?.target?.spot.id != desk)
    }

    /// A spare joining with its own desk taken (a working cat sits there) doesn't stand on that desk's spot: it starts
    /// on open floor on its desk's floor, away from the desk.
    @Test func aSpareWhoseDeskIsTakenStartsOffIt() throws {
        let roster = SpareRoster.roster(floors: OfficeSim.floors(building: building, rooms: rooms),
                                        cats: try JSONDecoder().decode(SpareRoster.Manifest.self, from: fixture("rooms/user/cats.json")).cats)
        let withDesks = roster.filter { $0.desk != nil }
        try #require(!withDesks.isEmpty)
        for spare in withDesks {
            let id = try #require(spare.desk?.spotId)
            let (floorId, desk) = try #require(rooms.lazy.compactMap { f, r in r.spots.first { $0.id == id }.map { (f, $0) } }.first)
            let sim = OfficeSim(seed: 6)
            sim.setCats([SimCat(spare: spare)], building: building, rooms: rooms, grids: grids, takenSpotIds: [id])
            let rt = try #require(sim.runtimes.first)
            let f = try #require(sim.floor(floorId))
            #expect(rt.floor == floorId && rt.target == nil)
            #expect(f.pxDistance(rt.position, desk.standAt) > 8, "\(spare.id) stands on its taken desk \(id)")
            #expect(grids[floorId]?.isOpenAt(rt.position) == true)
        }
    }

    /// No two cats are drawn on one seat: at every tick, no two cats' drawn points (forDrawing: a walker at its walk's
    /// end) sit on the same slot point of a spot (its own slots, else the spot's point and its offset slot points),
    /// unless both hold slots of that spot (a closed offset cell puts a slot on the spot's point, shared as in Cat
    /// Office; one that just left it stands there a moment, as it would have alone). The whole building with every spare; one floor with a single seat two cats take turns at (one leaves
    /// it, the other comes); and a capacity-2 spot with a closed slot-1 cell among three cats.
    @Test func noTwoCatsDrawnOnOneSeat() throws {
        let cats = try JSONDecoder().decode(SpareRoster.Manifest.self, from: fixture("rooms/user/cats.json")).cats
        let roster = SpareRoster.roster(floors: OfficeSim.floors(building: building, rooms: rooms), cats: cats)
        let seat = try #require(rooms[1]?.spots.first { $0.capacity == 1 && $0.kind != "desk" && $0.kind != "elevator" && SimActivities.activity(for: $0) != nil })
        let pair = (0..<2).map { SimCat(id: "p\($0)", isSpare: true, floor: 1, at: FloorPoint(u: 0.5, v: 0.5)) }
        let blocked = try blockedPair()
        let trio = (0..<3).map { SimCat(id: "t\($0)", isSpare: false, floor: 1, at: FloorPoint(u: 0.5, v: 0.5)) }
        let runs: [(cats: [SimCat], rooms: [Int: BuiltRoom], minutes: Int)] = [
            ((0..<4).map { SimCat(id: "s\($0)", isSpare: false, floor: 1, at: FloorPoint(u: 0.5, v: 0.5)) } + roster.map(SimCat.init(spare:)), rooms, 120),
            (pair, only([1]) { _, s in s.id == seat.id || s.kind == "elevator" }, 240),
            (trio, blocked.rooms, 240),
        ]
        for (i, run) in runs.enumerated() {
            for seed in [UInt32(1), 2, 3] {
                let sim = OfficeSim(seed: seed)
                sim.setCats(run.cats, building: building, rooms: run.rooms, grids: grids)
                for _ in 0..<(4 * run.minutes) { // the app's ticks
                    sim.step(minutes: 0.25)
                    let out = sim.output(showSpares: true, forDrawing: true)
                    let drawn: [(id: String, p: MirrorPlace)] = out.places.map { ($0.key, $0.value) }
                        + out.spares.map { (String(($0.key ?? "").dropFirst("spare:".count)), $0) }
                    for (fid, room) in run.rooms {
                        let f = try #require(sim.floor(fid))
                        for spot in room.spots where spot.kind != "elevator" {
                            let holders = Set((sim.occupancy[spot.id] ?? []).compactMap { $0 })
                            let points = spot.slots.isEmpty ? (0..<max(1, spot.capacity)).map { sim.slotPoint(fid, spot, $0) } : spot.slots
                            for p in points {
                                let on = drawn.filter { $0.p.floor == fid && $0.p.phase != "elevator" && f.pxDistance(FloorPoint(u: $0.p.u, v: $0.p.v), p) < 1 }
                                                                // A cat that just finished here still stands on its point while it decides or waits (as in Cat Office).
                                let strangers = on.filter { c in
                                    let rt = sim.runtimes.first { $0.cat.id == c.id }
                                    let justLeft = rt?.lastSpotId == spot.id && ["waiting", "deciding"].contains(rt?.phase.label ?? "")
                                    return !holders.contains(c.id) && !justLeft
                                }
                                #expect(on.count <= 1 || strangers.isEmpty, "run \(i) seed \(seed) t \(sim.time): \(on.map(\.id)) on \(spot.id)")
                            }
                        }
                    }
                }
            }
        }
    }

    /// The Lounge with only its elevator and one lounge spot made capacity 2 without own slots, its slot-1 offset cell
    /// closed (so slot 1 is the spot's own point).
    func blockedPair() throws -> (spot: RoomSpot, rooms: [Int: BuiltRoom]) {
        let nav = try #require(grids[1])
        var spot = try #require(rooms[1]?.spots.first { s in
            s.kind != "elevator" && s.lift == 0 && SimActivities.activity(for: s)?.lounge == true
                && !nav.isOpenAt(FloorPoint(u: s.standAt.u + OfficeSim.slotOffsets[1].u, v: s.standAt.v + OfficeSim.slotOffsets[1].v))
        })
        spot.capacity = 2
        spot.slots = []
        var r = only([1]) { _, s in s.kind == "elevator" }
        r[1]?.spots.append(spot)
        return (spot, r)
    }

    /// A capacity-2 spot without own slots whose second slot's offset cell is closed: Cat Office (simulation-engine.ts
    /// slotPoint) puts slot 1 on the spot's own point, and reserve takes any empty slot, so two cats share it there.
    @Test func aBlockedSecondSlotStillHoldsTwo() throws {
        let (spot, r) = try blockedPair()
        let sim = OfficeSim(seed: 3)
        sim.setCats((0..<2).map { SimCat(id: "c\($0)", isSpare: false, floor: 1, at: FloorPoint(u: 0.5, v: 0.5)) },
                    building: building, rooms: r, grids: grids)
        #expect(sim.slotPoint(1, spot, 1) == spot.standAt)
        var both = false
        for _ in 0..<(30 * 60) {
            sim.step(minutes: 1.0 / 30)
            if sim.occupancy[spot.id]?.allSatisfy({ $0 != nil }) == true { both = true; break }
        }
        #expect(both, "the second slot was never taken")
    }

    /// A spare riding the elevator to its desk when the desk becomes taken finishes the ride (it doesn't pop back to
    /// the floor it left) and chooses again on arrival.
    @Test func aRideToADeskTakenMidRideFinishes() throws {
        let roster = SpareRoster.roster(floors: OfficeSim.floors(building: building, rooms: rooms),
                                        cats: try JSONDecoder().decode(SpareRoster.Manifest.self, from: fixture("rooms/user/cats.json")).cats)
        let spare = try #require(roster.first { s in s.desk.map { d in rooms.contains { $0.key != 1 && $0.value.spots.contains { $0.id == d.spotId } } } == true })
        let desk = try #require(spare.desk?.spotId)
        let deskFloor = try #require(rooms.first { $0.value.spots.contains { $0.id == desk } }?.key)
        // The Lounge with only its elevator; the desk's floor with only the elevator and the desk: the desk is its one choice.
        let r = only([1, deskFloor]) { f, s in s.kind == "elevator" || (f == deskFloor && s.id == desk) }
        var cat = SimCat(spare: spare)
        cat.floor = 1; cat.at = FloorPoint(u: 0.5, v: 0.5)
        let sim = OfficeSim(seed: 4)
        sim.setCats([cat], building: building, rooms: r, grids: grids)
        var n = 0
        while true {
            sim.step(minutes: 1.0 / 30); n += 1
            try #require(n < 30 * 120, "never rode to its desk")
            if case .elevatorRide = runtime(sim, spare.id)!.phase { break }
        }
        let rt = try #require(runtime(sim, spare.id))
        #expect(rt.target?.spot.id == desk && rt.floor == 1)
        sim.setCats([cat], building: building, rooms: r, grids: grids, takenSpotIds: [desk])
        let p = try #require(sim.output(showSpares: true).spares.first)
        #expect(p.phase == "elevator" && p.ridingTo == deskFloor, "popped back: \(p.phase) on \(p.floor)")
        #expect(rt.target == nil && sim.occupancy[desk]?.contains(spare.id) != true)
        // It rides on, comes out on the desk's floor and stands there, choosing again.
        while rt.phase.label == "elevator" { sim.step(minutes: 1.0 / 30); n += 1; try #require(n < 30 * 240) }
        #expect(rt.floor == deskFloor && rt.target?.spot.id != desk)
        let after = try #require(sim.output(showSpares: true).spares.first)
        #expect(after.floor == deskFloor)
    }

    /// Like the engine's per-frame cap: one call steps at most 30 minutes; nonsense steps nothing.
    @Test func stepIsCapped() {
        let sim = OfficeSim(seed: 1)
        sim.setCats([SimCat(id: "x", isSpare: true, floor: 1, at: FloorPoint(u: 0.5, v: 0.5))], building: building, rooms: rooms, grids: grids)
        let start = Date()
        sim.step(minutes: 1e9)
        #expect(Date().timeIntervalSince(start) < 5)
        #expect(sim.time > 0 && sim.time <= 30 + 1e-9)
        let t = sim.time
        sim.step(minutes: .nan)
        sim.step(minutes: -5)
        sim.step(minutes: .infinity)
        #expect(sim.time == t)
        sim.step(minutes: 1.0 / 30)
        #expect(abs(sim.time - (t + 1.0 / 30)) < 1e-9) // the excess was dropped, not kept
    }

    /// The drawn output: a walking cat is where its walk ends (the view walks it there along the same grid), `at` is
    /// fixed, so stepping alone makes no new mirror; everything else is the plain output.
    @Test func drawnOutputPutsWalkersAtTheirWalksEnd() throws {
        let sim = OfficeSim(seed: 7)
        sim.setCats([SimCat(id: "s1", isSpare: true, name: "Mochi", catId: "cat-1", floor: 1, at: FloorPoint(u: 0.5, v: 0.5))],
                    building: building, rooms: only([1]), grids: grids)
        var n = 0
        while runtime(sim, "s1")!.phase.label != "walking" { sim.step(minutes: 1.0 / 30); n += 1; try #require(n < 300) }
        sim.step(minutes: 1.0 / 30)
        let rt = try #require(runtime(sim, "s1"))
        let end = try #require(rt.path.last)
        let plain = try #require(sim.output(showSpares: true).spares.first)
        let drawn = try #require(sim.output(showSpares: true, forDrawing: true).spares.first)
        #expect(plain.u != end.u || plain.v != end.v)
        #expect(drawn.u == end.u && drawn.v == end.v && drawn.phase == "walking" && drawn.at == 0)
        // Far enough from the end that two more steps leave it walking (each step walks at most speed × dt).
        try #require(routeLength(sim, floor: 1, from: rt.position, path: rt.path) > rt.speedPx * 3 / 30)
        let mid = sim.output(showSpares: true, forDrawing: true)
        sim.step(minutes: 2.0 / 30)
        try #require(runtime(sim, "s1")!.phase.label == "walking")
        #expect(sim.output(showSpares: true, forDrawing: true) == mid)
        // Not walking: the same place as the plain output but for `at`.
        while runtime(sim, "s1")!.phase.label == "walking" { sim.step(minutes: 1.0 / 30); n += 1; try #require(n < 3000) }
        var p = try #require(sim.output(showSpares: true).spares.first)
        p.at = 0
        #expect(sim.output(showSpares: true, forDrawing: true).spares.first == p)
    }
}

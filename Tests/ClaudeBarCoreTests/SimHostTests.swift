import Foundation
import Testing
@testable import ClaudeBarCore

/// SimHost (the app's side of the simulation, spec section 3) on the user fixture building.
@Suite struct SimHostTests {
    let building: Building
    let rooms: [Int: BuiltRoom]
    let grids: [Int: NavGrid]
    let t0 = Date(timeIntervalSince1970: 1_800_000_000)

    init() throws {
        let s = try OfficeSimTests()
        building = s.building
        rooms = s.rooms
        grids = s.grids
    }

    var claudeBar: Floor { building.floors.first { $0.name == "claude-bar" }! }

    func agent(_ id: String, _ status: AgentStatus, project: Bool = false) -> OfficeAgent {
        OfficeAgent(id: id, name: id, owner: "office", status: status, cwd: project ? claudeBar.repoRoot! : "/elsewhere",
                    repoRoot: project ? claudeBar.repoRoot : nil, sessionId: id)
    }

    func update(_ host: SimHost, _ agents: [OfficeAgent], spares: [SpareRoster.Cat] = [], showSpares: Bool = false) {
        host.update(agents: agents, building: building, rooms: rooms, grids: grids, spares: spares, showSpares: showSpares)
    }

    /// Spec section 3: nothing runs while the office is closed; opening catches up (seconds → sim minutes, at most 30)
    /// and counts as a placement; while open, each tick steps the time since the last.
    @Test func nothingRunsWhileClosed() {
        let host = SimHost(seed: 3, now: t0)
        update(host, [agent("a", .idle)])
        host.tick(now: t0.addingTimeInterval(10))
        #expect(host.sim.time == 0 && !host.visible && host.placement == 0)
        host.setVisible(true, now: t0.addingTimeInterval(20))
        #expect(host.visible && host.sim.time == 20 && host.placement == 1)
        host.tick(now: t0.addingTimeInterval(20.5))
        #expect(abs(host.sim.time - 20.5) < 1e-9)
        host.setVisible(true, now: t0.addingTimeInterval(21)) // already open: nothing
        #expect(abs(host.sim.time - 20.5) < 1e-9 && host.placement == 1)
        host.setVisible(false, now: t0.addingTimeInterval(21))
        host.tick(now: t0.addingTimeInterval(100))
        #expect(abs(host.sim.time - 20.5) < 1e-9 && !host.visible)
        // An hour closed: 30 sim minutes at once.
        host.setVisible(true, now: t0.addingTimeInterval(3600))
        #expect(abs(host.sim.time - 50.5) < 1e-9 && host.placement == 2)
    }

    /// The live mirror wins and the sim pauses; when it ends, the sim starts from the last mirrored places.
    @Test func liveMirrorWinsThenSeedsTheSim() throws {
        let host = SimHost(seed: 5, now: t0)
        update(host, [agent("a", .idle)])
        let spot = try #require(rooms[1]?.spots.first { $0.kind == "bookshelf" } ?? rooms[1]?.spots.first { $0.kind == "sofa" })
        let def = try #require(SimActivities.activity(for: spot))
        let browser = OfficeMirror(places: [
            "a": MirrorPlace(floor: 1, u: spot.standAt.u, v: spot.standAt.v, direction: spot.facing, state: def.state.rawValue,
                             activity: .init(kind: def.kind, label: def.label), spotId: spot.id, minutesLeft: 7, phase: "using", at: 0),
        ])
        #expect(host.mirror(browser, live: true, now: t0) == browser)
        host.setVisible(true, now: t0.addingTimeInterval(5))
        host.tick(now: t0.addingTimeInterval(10))
        #expect(host.sim.time == 0 && host.placement == 0 && host.live)
        let out = host.mirror(.off, live: false, now: t0.addingTimeInterval(10))
        let p = try #require(out.places["a"])
        #expect(!host.live && p.spotId == spot.id && p.phase == "using" && p.minutesLeft == 7)
        host.tick(now: t0.addingTimeInterval(11.5))
        #expect(abs(host.sim.time - 1.5) < 1e-9)
        #expect(host.mirror(.off, live: false, now: t0.addingTimeInterval(11.5)).places["a"]?.minutesLeft == 6)
    }

    /// The sim's cats: idle main agents (not working, waiting, helpers or ended), plus the roster with the switch on;
    /// the desks working and waiting cats sit at (as FloorPlan seats them) are taken.
    @Test func idleSessionsAndSparesWithTheSwitch() throws {
        let host = SimHost(seed: 2, now: t0)
        var helper = agent("h", .idle)
        helper.kind = "subagent"; helper.parentName = "i"
        let agents = [agent("i", .idle), agent("w", .working, project: true), agent("q", .waiting, project: true), helper, agent("e", .ended)]
        update(host, agents)
        #expect(host.cats.map(\.id) == ["i"] && host.cats.allSatisfy { !$0.isSpare })
        let desks = Set(try #require(rooms[claudeBar.id]).desks.map(\.id))
        #expect(host.takenSpotIds.count == 2 && host.takenSpotIds.isSubset(of: desks))
        #expect(Set(host.sim.output(showSpares: true).places.keys) == ["i"])

        let cats = try JSONDecoder().decode(SpareRoster.Manifest.self, from: fixture("rooms/user/cats.json")).cats
        update(host, agents, spares: cats, showSpares: true)
        let roster = SpareRoster.roster(floors: OfficeSim.floors(building: building, rooms: rooms), cats: cats)
        #expect(host.cats.filter(\.isSpare).map(\.id) == roster.map(\.id) && !roster.isEmpty)
        let out = host.mirror(.off, live: false, now: t0)
        #expect(out.spares.count == roster.count && Set(out.places.keys) == ["i"])
        // A spare never starts at a working cat's desk.
        #expect(out.spares.allSatisfy { $0.spotId.map { !host.takenSpotIds.contains($0) } ?? true })
        update(host, agents, spares: cats, showSpares: false)
        #expect(host.cats.map(\.id) == ["i"] && host.mirror(.off, live: false, now: t0).spares.isEmpty)
        // No rooms built yet: nobody runs.
        let early = SimHost(seed: 2, now: t0)
        early.update(agents: agents, building: building, rooms: [:], grids: [:], spares: cats, showSpares: true)
        #expect(early.cats.isEmpty && early.mirror(.off, live: false, now: t0) == OfficeMirror(places: [:]))
    }

    /// A session that stops working joins the sim where it stands: at its desk on its floor; the desk is free again.
    @Test func aCatThatStopsWorkingJoinsAtItsDesk() throws {
        let host = SimHost(seed: 4, now: t0)
        update(host, [agent("w", .working, project: true)])
        let desk = try #require(host.takenSpotIds.first)
        let placed = try #require(rooms[claudeBar.id]?.desks.first { $0.id == desk })
        update(host, [agent("w", .idle, project: true)])
        let cat = try #require(host.cats.first)
        #expect(cat.id == "w" && cat.floor == claudeBar.id && cat.at == placed.standAt && host.takenSpotIds.isEmpty)
        let p = try #require(host.mirror(.off, live: false, now: t0).places["w"])
        #expect(p.floor == claudeBar.id && abs(p.u - placed.standAt.u) < 0.05 && abs(p.v - placed.standAt.v) < 0.05)
        // Already in the sim: a later update doesn't move it.
        update(host, [agent("w", .idle, project: true)])
        #expect(host.cats.first == cat)
    }

    /// Renders only: advance N sim minutes at once (in catch-up's steps), as a placement.
    @Test func advanceIsAPlacement() {
        let host = SimHost(seed: 1, now: t0)
        update(host, [agent("a", .idle)])
        host.advance(minutes: 75, now: t0)
        #expect(abs(host.sim.time - 75) < 1e-9 && host.placement == 1)
    }
    /// One seating for everyone: the desk the views draw a working cat at (SimHost.seatings) is the one taken, and no
    /// spare takes it, even when it is a spare's own desk (no pool floor: the desk pool is the Office, an own-office floor).
    @Test func aWorkingCatsDeskIsTheOneDrawnAndNoSpareTakesIt() throws {
        var b = building
        b.floors.removeAll { $0.pool }
        var r = rooms, g = grids
        for id in rooms.keys where b.floor(id: id) == nil { r[id] = nil; g[id] = nil }
        let pool = try #require(b.deskPool)
        #expect(pool.isOwnOffice)
        let cats = try JSONDecoder().decode(SpareRoster.Manifest.self, from: fixture("rooms/user/cats.json")).cats
        let host = SimHost(seed: 11, now: t0)
        host.update(agents: [agent("w", .working)], building: b, rooms: r, grids: g, spares: cats, showSpares: true)
        let seating = try #require(host.seatings[pool.id])
        let ids = SimHost.seatFloor(pool, try #require(r[pool.id])).desks.map(\.id)
        let i = try #require(seating.desks.firstIndex(of: "w"))
        let desk = ids[i]
        #expect(host.takenSpotIds == [desk])
        let roster = SpareRoster.roster(floors: OfficeSim.floors(building: b, rooms: r), cats: cats)
        try #require(roster.contains { $0.desk?.spotId == desk }, "the working cat's desk is a spare's own desk")
        host.setVisible(true, now: t0)
        for k in 1...240 {
            let now = t0.addingTimeInterval(Double(k) * 0.25)
            host.tick(now: now)
            let out = host.mirror(.off, live: false, now: now)
            #expect(!out.spares.contains { $0.spotId == desk })
            #expect(!host.sim.runtimes.contains { $0.target?.spot.id == desk })
            #expect(host.seatings[pool.id]?.desks.firstIndex(of: "w") == i && host.takenSpotIds == [desk])
        }
    }

    /// A long stall with the office open (the Mac slept): the gap is a catch-up and a placement, not walks.
    @Test func aLongStallWhileOpenIsAPlacement() {
        let host = SimHost(seed: 3, now: t0)
        update(host, [agent("a", .idle)])
        host.setVisible(true, now: t0)
        host.tick(now: t0.addingTimeInterval(0.5))
        #expect(host.placement == 1 && abs(host.sim.time - 0.5) < 1e-9)
        host.tick(now: t0.addingTimeInterval(0.5 + 600))
        #expect(host.placement == 2 && abs(host.sim.time - 30.5) < 1e-9)
        host.tick(now: t0.addingTimeInterval(601))
        #expect(host.placement == 2 && abs(host.sim.time - 31) < 1e-9)
    }
}

import Foundation
import Testing
@testable import ClaudeBarCore

/// A mirrored place (decoded the way the bridge sends it).
func mirrorPlace(floor: Int, u: Double, v: Double, direction: String = "front-left", state: String = "idle",
                 gesture: String = "both-down", asleep: Bool = false, kind: String? = nil, spotId: String? = nil,
                 phase: String = "using", ridingTo: Int? = nil, at: Double = 1_791_266_000_000) -> MirrorPlace {
    let activity = kind.map { #"{"kind":"\#($0)","label":"Doing"}"# } ?? "null"
    let json = """
    {"floor":\(floor),"u":\(u),"v":\(v),"direction":"\(direction)","state":"\(state)","gesture":"\(gesture)","expression":"default",
     "asleep":\(asleep),"activity":\(activity),"spotId":\(spotId.map { "\"\($0)\"" } ?? "null"),"minutesLeft":null,
     "phase":"\(phase)","ridingTo":\(ridingTo.map(String.init) ?? "null"),"catId":"tuxedo","at":\(at)}
    """
    return try! JSONDecoder().decode(MirrorPlace.self, from: Data(json.utf8))
}

@Suite struct OfficeMirrorTests {
    let building = FloorAssignmentTests().building
    let now = Date(timeIntervalSince1970: 1_791_266_000)
    var nowMs: Double { now.timeIntervalSince1970 * 1000 }

    func agent(_ name: String, _ status: AgentStatus, repoRoot: String? = "/w/claude-bar", place: MirrorPlace? = nil,
               parent: String? = nil) -> OfficeAgent {
        var a = FloorAssignmentTests().agent(name, status, repoRoot: repoRoot, parent: parent)
        a.place = place
        return a
    }

    /// The mirror from a snapshot whose places were posted `age` seconds ago.
    func mirror(_ agents: [OfficeAgent], age: Double = 2, spares: [MirrorPlace] = []) -> OfficeMirror {
        OfficeMirror(OfficeSnapshot(agents: agents, spares: spares, placesAt: nowMs - age * 1000), now: now)
    }

    func floor(_ a: OfficeAgent, _ all: [OfficeAgent], _ m: OfficeMirror) -> Int? {
        FloorPlan.floorId(for: a, among: all, in: building, mirror: m)
    }

    @Test func aLiveMirrorPutsTheCatOnItsFloor() {
        let a = agent("a", .working, place: mirrorPlace(floor: 4, u: 0.3, v: 0.6))
        #expect(floor(a, [a], mirror([a])) == 4)
        #expect(mirror([a]).places["a"] != nil)
    }

    @Test func aStaleMirrorOrNoPlaceIsTodaysRule() {
        let a = agent("a", .working, place: mirrorPlace(floor: 4, u: 0.3, v: 0.6))
        let rule = FloorPlan.floorId(for: a, among: [a], in: building)
        #expect(rule == 12)
        #expect(floor(a, [a], mirror([a], age: 10.5)) == rule, "older than 10 s")
        #expect(floor(a, [a], OfficeMirror(OfficeSnapshot(agents: [a]), now: now)) == rule, "no placesAt (no page, older patch)")
        #expect(OfficeMirror(nil, now: now) == .off)
        let b = agent("b", .working)
        #expect(floor(b, [a, b], mirror([a, b])) == 12, "a session without a place keeps the rule")
    }

    @Test func anUnknownFloorOrOffTheFloorIsTodaysRule() {
        for p in [mirrorPlace(floor: 99, u: 0.3, v: 0.6), mirrorPlace(floor: 4, u: 1.2, v: 0.6), mirrorPlace(floor: 4, u: 0.3, v: -0.15)] {
            let a = agent("a", .idle, place: p)
            #expect(floor(a, [a], mirror([a])) == 1, "the Lounge, as for an idle cat today")
            #expect(mirror([a]).places(on: 4, agents: [a], in: building).isEmpty)
        }
    }

    @Test func aSpotJustPastTheEdgeCounts() {
        // The Lounge's window seat stands at u −0.015.
        let a = agent("a", .idle, place: mirrorPlace(floor: 4, u: -0.015, v: 0.72))
        #expect(floor(a, [a], mirror([a])) == 4)
    }

    @Test func endedStaysHidden() {
        let a = agent("a", .ended, place: mirrorPlace(floor: 4, u: 0.3, v: 0.6))
        #expect(floor(a, [a], mirror([a])) == nil)
        #expect(mirror([a]).places(on: 4, agents: [a], in: building).isEmpty)
    }

    @Test func aRideCountsOnTheFloorItIsRidingTo() {
        let a = agent("a", .idle, place: mirrorPlace(floor: 4, u: 0.1, v: 0.2, phase: "elevator", ridingTo: 12))
        #expect(floor(a, [a], mirror([a])) == 12)
        let lost = agent("a", .idle, place: mirrorPlace(floor: 4, u: 0.1, v: 0.2, phase: "elevator", ridingTo: 99))
        #expect(floor(lost, [lost], mirror([lost])) == 4, "riding to an unknown floor: where it is")
    }

    @Test func aHelperWithoutAPlaceFollowsItsMirroredParent() {
        let parent = agent("office-p", .working, place: mirrorPlace(floor: 4, u: 0.3, v: 0.6))
        let helper = agent("h", .working, parent: "office-p")
        #expect(floor(helper, [parent, helper], mirror([parent, helper])) == 4)
    }

    @Test func countsActivityAndFollowUseTheMirror() {
        let a = agent("a", .working, place: mirrorPlace(floor: 4, u: 0.3, v: 0.6, state: "working"))
        let m = mirror([a])
        #expect(FloorPlan.cats(on: 4, agents: [a], in: building, mirror: m).map(\.id) == ["a"])
        #expect(FloorPlan.cats(on: 12, agents: [a], in: building, mirror: m).isEmpty)
        let act = FloorPlan.activity(of: building, agents: [a], attention: [], mirror: m)
        #expect(act[4] == .working && act[12] == .empty)
        #expect(FloorPlan.followTarget(building: building, agents: [a], attention: [], since: [:], now: now, mirror: m) == 4)
        #expect(FloorPlan.followTarget(building: building, agents: [a], attention: [], since: [:], now: now) == 12, "no mirror: the rule")
    }

    @Test func sparesNeverCount() {
        let a = agent("a", .working)
        var spare = mirrorPlace(floor: 4, u: 0.3, v: 0.6, state: "working")
        spare.key = "spare:agent-1"
        spare.name = "Mochi"
        let m = mirror([a], spares: [spare, spare])
        #expect(m.places.isEmpty)
        #expect(FloorPlan.cats(on: 4, agents: [a], in: building, mirror: m).isEmpty)
        #expect(FloorPlan.activity(of: building, agents: [a], attention: [], mirror: m)[4] == .empty)
        #expect(FloorPlan.followTarget(building: building, agents: [a], attention: [], since: [:], now: now, mirror: m) == 12)
    }

    @Test func poses() {
        func pose(_ state: String, _ direction: String, asleep: Bool = false, kind: String? = nil, gesture: String = "both-down") -> CatPose {
            CatPose(mirrorPlace(floor: 1, u: 0.5, v: 0.5, direction: direction, state: state, gesture: gesture, asleep: asleep, kind: kind))
        }
        #expect(pose("working", "back-right", kind: "desk") == .typing)
        #expect(pose("working", "front-left", kind: "desk") == .standing, "no front-facing typing sprite (as at a turned desk)")
        #expect(pose("working", "back-left", kind: "printer") == .standing)
        #expect(pose("resting", "front-right", kind: "window-seat") == .sitting)
        #expect(pose("resting", "back-left", kind: "window-seat") == .standing, "cat.sprite.ts: a back-facing sit stands")
        #expect(pose("resting", "back-left", asleep: true, kind: "sofa") == .sleeping)
        #expect(pose("idle", "front-left") == .standing)
        #expect(pose("idle", "front-left", gesture: "right-up") == .waving)
    }

    @Test func theSitSprite() {
        let c = CatCatalog(catIds: ["gray"], standingPath: "assets/cats/{cat}/{direction}/{gesture}.png",
                           typePath: "assets/cats/{cat}/{direction}/type.png", sleepPath: "assets/cats/{cat}/sleep.png")
        #expect(c.path(cat: "gray", pose: .sitting, direction: "front-right") == "assets/cats/gray/front-right/sit.png")
        let parsed = CatCatalog.parse(Data(#"{"cats":[{"id":"gray"}],"sitPath":"x/{cat}/{direction}/sit2.png"}"#.utf8))
        #expect(parsed?.path(cat: "gray", pose: .sitting) == "x/gray/front-left/sit2.png")
    }
}

@Suite struct MirroredSceneTests {
    func built(_ id: Int) throws -> BuiltRoom { try BuiltRoomTests().built(id) }

    func agent(_ name: String, _ status: AgentStatus) -> OfficeAgent {
        OfficeAgent(id: name, name: name, owner: "office", status: status, cwd: "/w", sessionId: name)
    }

    func cast(_ room: BuiltRoom, lounge: Bool, agents: [OfficeAgent], mirrored: [String: MirrorPlace]) -> SceneCast {
        var floor = Floor(id: room.floorId, name: "f", repoRoot: nil, floorTexture: nil, wallTexture: nil,
                          desks: room.desks.map { FloorDesk(id: $0.id, design: $0.design, flip: $0.flip, rear: $0.rear) },
                          elevator: nil, hasLoungeSign: lounge)
        if lounge { floor.desks = [] }
        let seating = FloorPlan.seating(on: floor, agents: agents, previous: nil, seats: room.seats.count)
        return SceneCast(seating: seating, agents: agents, deskIds: floor.desks.map(\.id), lounge: lounge, mirrored: mirrored)
    }

    @Test func aMirroredCatIsAtItsPointInItsPose() throws {
        let room = try built(1)
        let seat = try #require(room.seats.first { $0.lift > 0 })
        let a = agent("a", .idle), b = agent("b", .idle), c = agent("c", .idle)
        let mirrored = [
            "a": mirrorPlace(floor: 1, u: seat.standAt.u, v: seat.standAt.v, direction: "front-right", state: "resting", asleep: true,
                             kind: seat.kind, spotId: seat.id),
            "b": mirrorPlace(floor: 1, u: 0.42, v: 0.37, direction: "back-left"),
        ]
        let cats = cast(room, lounge: true, agents: [a, b, c], mirrored: mirrored).layout(in: room).cats
        let ca = try #require(cats.first { $0.agent.id == "a" })
        #expect(ca.at == seat.standAt && ca.lift == seat.lift && ca.perch == seat.owner)
        #expect(ca.pose == .sleeping && ca.direction == "front-right" && ca.kind == .mirrored)
        let cb = try #require(cats.first { $0.agent.id == "b" })
        #expect(cb.at == FloorPoint(u: 0.42, v: 0.37) && cb.lift == 0 && cb.perch == nil)
        #expect(cb.pose == .standing && cb.direction == "back-left")
        #expect(cats.filter { $0.agent.id == "a" || $0.agent.id == "b" }.count == 2, "drawn once each")
        let cc = try #require(cats.first { $0.agent.id == "c" })
        #expect(cc.kind == .seat && cc.pose == .sleeping, "no place: today's lounge seat")
    }

    @Test func aMirroredCatAtADeskTypesThere() throws {
        let room = try built(2)
        let desk = try #require(room.desks.first { $0.facing.hasPrefix("back") })
        let a = agent("a", .working)
        let place = mirrorPlace(floor: 2, u: desk.standAt.u, v: desk.standAt.v, direction: desk.facing, state: "working",
                                kind: "desk", spotId: desk.id)
        let cats = cast(room, lounge: false, agents: [a], mirrored: ["a": place]).layout(in: room).cats
        let ca = try #require(cats.first)
        #expect(cats.count == 1 && ca.pose == .typing && ca.lift == 0 && ca.desk == desk.rect && ca.at == desk.standAt)
    }

    @Test func ridingInWaitsAtTheElevator() throws {
        let room = try built(2)
        let door = try #require(room.elevator?.standAt)
        let a = agent("a", .idle)
        let place = mirrorPlace(floor: 1, u: 0.1, v: 0.9, phase: "elevator", ridingTo: 2)
        let ca = try #require(cast(room, lounge: false, agents: [a], mirrored: ["a": place]).layout(in: room).cats.first)
        #expect(ca.at == door)
    }

    @Test func aRuleCatDoesNotTakeTheDeskAMirroredCatUses() throws {
        let room = try built(2)
        let a = agent("a", .working), b = agent("b", .working)
        // By the rules "a" (first by name) gets the first desk; "b" is mirrored at that desk in the browser.
        let today = cast(room, lounge: false, agents: [a, b], mirrored: [:])
        let deskX = try #require(today.seating.desks.firstIndex(of: "a")).map { today.deskIds[$0] }
        let x = try #require(room.desks.first { $0.id == deskX })
        let place = mirrorPlace(floor: 2, u: x.standAt.u, v: x.standAt.v, direction: x.facing, state: "working", kind: "desk", spotId: x.id)
        let cats = cast(room, lounge: false, agents: [a, b], mirrored: ["b": place]).layout(in: room).cats
        let ca = try #require(cats.first { $0.agent.id == "a" })
        #expect(ca.kind == .desk && ca.at != x.standAt, "another desk")
        #expect(cats.filter { $0.at == x.standAt }.map(\.agent.id) == ["b"])
        // Mirror off: as today.
        #expect(today.layout(in: room).cats.first { $0.agent.id == "a" }?.at == x.standAt)
    }

    @Test func aRuleCatDoesNotTakeTheSeatAMirroredCatUses() throws {
        let room = try built(1)
        let a = agent("a", .idle), b = agent("b", .idle)
        let today = cast(room, lounge: true, agents: [a, b], mirrored: [:])
        let i = try #require(today.seating.lounge.firstIndex(of: "a"))
        let seat = room.seats[i]
        let place = mirrorPlace(floor: 1, u: seat.standAt.u, v: seat.standAt.v, asleep: true, kind: seat.kind, spotId: seat.id)
        let cats = cast(room, lounge: true, agents: [a, b], mirrored: ["b": place]).layout(in: room).cats
        let ca = try #require(cats.first { $0.agent.id == "a" })
        #expect(ca.kind == .seat && ca.at != seat.standAt, "another seat")
        #expect(today.layout(in: room).cats.first { $0.agent.id == "a" }?.at == seat.standAt)
        // Every seat busy: the cat sleeps in the cluster, drawn once.
        var mirrored: [String: MirrorPlace] = [:], agents = [a]
        for (k, s) in room.seats.enumerated() {
            let m = agent("m\(k)", .idle)
            agents.append(m)
            mirrored[m.id] = mirrorPlace(floor: 1, u: s.standAt.u, v: s.standAt.v, asleep: true, kind: s.kind, spotId: s.id)
        }
        let full = cast(room, lounge: true, agents: agents, mirrored: mirrored).layout(in: room).cats
        #expect(full.filter { $0.agent.id == "a" }.map(\.kind) == [.seat])
        #expect(full.count == agents.count)
    }

    @Test func withEveryDeskBusyTheRuleCatQueues() throws {
        let room = try built(2)
        let a = agent("a", .working)
        var mirrored: [String: MirrorPlace] = [:], agents = [a]
        for (k, d) in room.desks.enumerated() {
            let m = agent("m\(k)", .working)
            agents.append(m)
            mirrored[m.id] = mirrorPlace(floor: 2, u: d.standAt.u, v: d.standAt.v, state: "working", kind: "desk", spotId: d.id)
        }
        let cats = cast(room, lounge: false, agents: agents, mirrored: mirrored).layout(in: room).cats
        let ca = try #require(cats.first { $0.agent.id == "a" })
        #expect(ca.kind == .queue)
        #expect(cats.count == agents.count)
    }

    @Test func aStaleMirrorLeavesTodaysLayout() throws {
        for (id, lounge) in [(1, true), (2, false)] {
            let room = try built(id)
            var agents = [agent("a", lounge ? .idle : .working), agent("b", .waiting), agent("c", .idle)]
            for i in agents.indices { agents[i].place = mirrorPlace(floor: id, u: 0.4, v: 0.4) }
            let building = Building(floors: [Floor(id: id, name: "f", repoRoot: nil, floorTexture: nil, wallTexture: nil, desks: [],
                                                   elevator: nil, hasLoungeSign: lounge)])
            let now = Date(timeIntervalSince1970: 1_791_266_000)
            let stale = OfficeMirror(OfficeSnapshot(agents: agents, placesAt: now.timeIntervalSince1970 * 1000 - 11_000), now: now)
            let mirrored = stale.places(on: id, agents: agents, in: building)
            #expect(mirrored.isEmpty)
            let cats = cast(room, lounge: lounge, agents: agents, mirrored: mirrored).layout(in: room).cats
            #expect(cats.count == 3 && !cats.contains { $0.kind == .mirrored })
            #expect(cats.allSatisfy { $0.at != FloorPoint(u: 0.4, v: 0.4) })
            let live = OfficeMirror(OfficeSnapshot(agents: agents, placesAt: now.timeIntervalSince1970 * 1000 - 2_000), now: now)
            #expect(live.places(on: id, agents: agents, in: building).count == 3)
        }
    }

    @Test func aSpareIsDrawnAtItsPlaceWithNoRing() throws {
        let room = try built(1)
        let a = agent("a", .idle)
        var c = cast(room, lounge: true, agents: [a], mirrored: [:])
        c.spares = [sparePlace("s1", name: "Mochi", floor: 1, u: 0.42, v: 0.37, catId: "calico")]
        let cats = c.layout(in: room).cats
        let s = try #require(cats.first { $0.agent.id == "spare:s1" })
        #expect(s.kind == .spare && s.at == FloorPoint(u: 0.42, v: 0.37) && s.agent.label == "Mochi" && s.agent.cat == "calico")
        #expect(!s.showsRing, "no status ring")
        #expect(cats.first { $0.agent.id == "a" }?.kind == .seat, "the session cat keeps its seat")
    }

    @Test func mirroredCatsLeaveNoGapInTheQueueAndAreNotCounted() throws {
        let room = try built(2)
        // Every desk goes to a rule cat (a00…); b0 and b1 (mirrored) and c0 queue. b0 stands at a00's desk, so a00
        // queues after the rest.
        var agents = room.desks.indices.map { agent(String(format: "a%02d", $0), .working) }
        let b0 = agent("b0", .working), b1 = agent("b1", .working), c0 = agent("c0", .working)
        agents += [b0, b1, c0]
        let d = room.desks[0]
        let mirrored = ["b0": mirrorPlace(floor: 2, u: d.standAt.u, v: d.standAt.v, state: "working", kind: "desk", spotId: d.id),
                        "b1": mirrorPlace(floor: 2, u: 0.4, v: 0.4, phase: "idle")]
        let c = cast(room, lounge: false, agents: agents, mirrored: mirrored)
        #expect(c.seating.queue == ["b0", "b1", "c0"], "the rules queue the mirrored cats too")
        let (cats, notes) = c.layout(in: room)
        let door = room.elevator?.standAt ?? FloorPoint(u: 0.5, v: 0.5)
        #expect(cats.first { $0.agent.id == "c0" }?.at == ElevatorTrip.waitingPlace(door, index: 0), "no gap before c0")
        #expect(cats.first { $0.agent.id == "a00" }?.at == ElevatorTrip.waitingPlace(door, index: 1))
        #expect(cats.filter { $0.kind == .queue }.count == 2)
        #expect(!notes.contains { $0.0.hasPrefix("+") }, "no +N: only two rule cats queue")
    }
}

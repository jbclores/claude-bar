// Tests/ClaudeBarCoreTests/FloorPlanTests.swift
import CoreGraphics
import Foundation
import Testing
@testable import ClaudeBarCore

@Suite struct FloorAssignmentTests {
    let building = Building(floors: [
        Floor(id: 1, name: "Lounge", repoRoot: nil, floorTexture: nil, wallTexture: nil, desks: [], elevator: nil, hasLoungeSign: true),
        Floor(id: 4, name: "docs", repoRoot: "/w", floorTexture: nil, wallTexture: nil, desks: [], elevator: nil, hasLoungeSign: false),
        Floor(id: 6, name: "Desk pool", repoRoot: nil, floorTexture: nil, wallTexture: nil, desks: [], elevator: nil, hasLoungeSign: false),
        Floor(id: 12, name: "claude-bar", repoRoot: "/w/claude-bar", floorTexture: nil, wallTexture: nil, desks: [], elevator: nil, hasLoungeSign: false),
    ])

    func agent(_ name: String, _ status: AgentStatus, cwd: String = "/tmp/x", repoRoot: String? = nil, parent: String? = nil) -> OfficeAgent {
        var a = OfficeAgent(id: name, name: name, owner: "office", status: status, cwd: cwd, repoRoot: repoRoot)
        if let parent { a.kind = "subagent"; a.parentName = parent }
        return a
    }

    func floor(_ a: OfficeAgent, _ all: [OfficeAgent] = []) -> Int? { FloorPlan.floorId(for: a, among: all + [a], in: building) }

    @Test func idleGoesToTheLounge() { #expect(floor(agent("a", .idle, repoRoot: "/w/claude-bar")) == 1) }

    @Test func workingAndWaitingGoToTheirProjectFloor() {
        #expect(floor(agent("a", .working, repoRoot: "/w/claude-bar")) == 12)
        #expect(floor(agent("a", .waiting, cwd: "/w/claude-bar/Sources")) == 12, "a subfolder of the project")
    }

    @Test func theMostSpecificRootWins() {
        // /w (floor 4) contains /w/claude-bar (floor 12): the longer root wins.
        #expect(floor(agent("a", .working, repoRoot: "/w/claude-bar")) == 12)
        #expect(floor(agent("a", .working, cwd: "/w/other")) == 4)
    }

    @Test func noProjectGoesToTheDeskPool() { #expect(floor(agent("a", .working, cwd: "/Users/me")) == 6) }

    @Test func helpersFollowTheirParentEvenToTheLounge() {
        let parent = agent("office-p", .idle, repoRoot: "/w/claude-bar")
        let helper = agent("h", .working, repoRoot: "/w/claude-bar", parent: "office-p")
        #expect(floor(helper, [parent]) == 1)
        let busy = agent("office-p", .working, repoRoot: "/w/claude-bar")
        #expect(floor(helper, [busy]) == 12)
    }

    @Test func helpersWithoutAParentInTheOfficeGoToTheDeskPool() {
        #expect(floor(agent("h", .working, repoRoot: "/w/claude-bar", parent: "gone")) == 6)
    }

    @Test func endedIsNotShown() { #expect(floor(agent("a", .ended)) == nil) }
}

@Suite struct FloorSeatingTests {
    let desks = [
        FloorDesk(id: "d0", design: "s1-walnut", flip: false, rear: false),
        FloorDesk(id: "d1", design: "s2-pink", flip: true, rear: false),
        FloorDesk(id: "d2", design: "s2-pink", flip: true, rear: false),
        FloorDesk(id: "d3", design: "s1-oak", flip: false, rear: false),
    ]
    var floor: Floor { Floor(id: 12, name: "claude-bar", repoRoot: "/w", floorTexture: nil, wallTexture: nil, desks: desks, elevator: nil, hasLoungeSign: false) }
    var lounge: Floor { Floor(id: 1, name: "Lounge", repoRoot: nil, floorTexture: nil, wallTexture: nil, desks: [], elevator: nil, hasLoungeSign: true) }

    func a(_ id: String, _ status: AgentStatus = .working, desk: AgentDesk? = nil, parent: String? = nil) -> OfficeAgent {
        var x = OfficeAgent(id: id, name: id, owner: "office", status: status, cwd: "/w")
        x.desk = desk
        if let parent { x.kind = "subagent"; x.parentName = parent }
        return x
    }

    @Test func helperTakesTheNearestDeskOnTheFloor() {
        // Three desks in a line on the floor; the parent at the far end, so the next desk in list order is NOT the nearest.
        let corners = FloorCorners(top: WorldPoint(x: 1000, y: 0), left: WorldPoint(x: 0, y: 500), bottom: WorldPoint(x: 1000, y: 1000), right: WorldPoint(x: 2000, y: 500))
        let desks = [FloorDesk(id: "a", design: "s1-oak", flip: false, rear: false, u: 0.1, v: 0.1),
                     FloorDesk(id: "b", design: "s1-oak", flip: false, rear: false, u: 0.9, v: 0.9),
                     FloorDesk(id: "c", design: "s1-oak", flip: false, rear: false, u: 0.85, v: 0.8)]
        var f = Floor(id: 12, name: "x", repoRoot: "/w", floorTexture: nil, wallTexture: nil, desks: desks, elevator: nil, hasLoungeSign: false)
        f.corners = corners
        let previous = FloorPlan.seating(on: f, agents: [a("p")], previous: nil)
        var placed = previous; placed.desks = [nil, "p", nil]
        let s = FloorPlan.seating(on: f, agents: [a("p"), a("h", parent: "p")], previous: placed)
        #expect(s.desks == [nil, "p", "h"])
    }

    @Test func loungeUsesTheRoomsSeatCount() {
        let s = FloorPlan.seating(on: lounge, agents: (0..<9).map { a("c\($0)", .idle) }, previous: nil, seats: 6)
        #expect(s.lounge.count == 6 && s.loungeOverflow == 3)
    }

    @Test func aNewMainAgentTakesAHelpersDesk() {
        // The parent and its 3 helpers fill all 4 desks; then a second main agent starts on this project.
        let before = FloorPlan.seating(on: floor, agents: [a("p"), a("h1", parent: "p"), a("h2", parent: "p"), a("h3", parent: "p")], previous: nil)
        #expect(before.desks.compactMap { $0 }.count == 4)
        let after = FloorPlan.seating(on: floor, agents: [a("p"), a("q"), a("h1", parent: "p"), a("h2", parent: "p"), a("h3", parent: "p")], previous: before)
        #expect(after.desks.contains("q"), "a main agent outranks a helper for a desk")
        #expect(after.desks.contains("p") && after.desks.firstIndex(of: "p") == before.desks.firstIndex(of: "p"), "the parent keeps its desk")
        #expect(after.queue.isEmpty)
        #expect((after.nearby["p"] ?? []).count == 1, "the helper that lost its desk stands beside its parent")
    }

    @Test func catsSitAtTheirReportedDeskDesign() {
        let s = FloorPlan.seating(on: floor, agents: [a("p", desk: AgentDesk(id: "s2-pink", flip: true, rear: false))], previous: nil)
        #expect(s.desks == [nil, "p", nil, nil])
    }

    @Test func twoCatsWithTheSameDesignGetTwoDesks() {
        let pink = AgentDesk(id: "s2-pink", flip: true, rear: false)
        let s = FloorPlan.seating(on: floor, agents: [a("p", desk: pink), a("q", desk: pink)], previous: nil)
        #expect(s.desks == [nil, "p", "q", nil])
    }

    @Test func catsKeepTheirDeskWhileOthersComeAndGo() {
        let first = FloorPlan.seating(on: floor, agents: [a("x"), a("y")], previous: nil)
        #expect(first.desks == ["x", "y", nil, nil])
        let next = FloorPlan.seating(on: floor, agents: [a("y"), a("z")], previous: first)
        #expect(next.desks == ["z", "y", nil, nil], "y stays at d1; z takes the free d0")
    }

    @Test func helpersTakeTheFreeDeskNearestTheirParent() {
        let s = FloorPlan.seating(on: floor, agents: [a("p", desk: AgentDesk(id: "s1-oak", flip: false, rear: false)), a("h", parent: "p")], previous: nil)
        #expect(s.desks == [nil, nil, "h", "p"])
    }

    @Test func helpersStandBesideTheirParentWhenNoDeskIsFree() {
        let agents = [a("p"), a("q"), a("r"), a("s"), a("h1", parent: "p"), a("h2", parent: "p"), a("h3", parent: "p")]
        let s = FloorPlan.seating(on: floor, agents: agents, previous: nil)
        #expect(s.desks == ["p", "q", "r", "s"])
        #expect(s.nearby["p"] == ["h1", "h2"] && s.nearbyOverflow["p"] == 1)
    }

    @Test func otherOverflowQueuesThenCounts() {
        let agents = ["a", "b", "c", "d", "e", "f", "g", "h"].map { a($0) }
        let s = FloorPlan.seating(on: floor, agents: agents, previous: nil)
        #expect(s.desks == ["a", "b", "c", "d"])
        #expect(s.queue == ["e", "f", "g"] && s.queueOverflow == 1)
    }

    @Test func loungeSeatsTenThenCountsAndHelpersSitBesideTheirParent() {
        let cats = (0..<12).map { a("c\($0)", .idle) } + [a("h", .working, parent: "c0")]
        let s = FloorPlan.seating(on: lounge, agents: cats, previous: nil)
        #expect(s.lounge.count == FloorSeating.loungeSpots && s.lounge.compactMap { $0 }.count == 10)
        #expect(s.loungeOverflow == 2)
        #expect(s.nearby["c0"] == ["h"])
    }

    @Test func deskPositionsRunInRowsOfSix() {
        #expect(FloorPlan.deskPosition(0) == (0, 0) && FloorPlan.deskPosition(5) == (0, 5) && FloorPlan.deskPosition(6) == (1, 0))
    }
}

@Suite struct FollowTests {
    let building = Building(floors: [
        Floor(id: 1, name: "Lounge", repoRoot: nil, floorTexture: nil, wallTexture: nil, desks: [], elevator: nil, hasLoungeSign: true),
        Floor(id: 6, name: "Desk pool", repoRoot: nil, floorTexture: nil, wallTexture: nil, desks: [], elevator: nil, hasLoungeSign: false),
        Floor(id: 10, name: "pnp", repoRoot: "/w/pnp", floorTexture: nil, wallTexture: nil, desks: [], elevator: nil, hasLoungeSign: false),
        Floor(id: 12, name: "claude-bar", repoRoot: "/w/claude-bar", floorTexture: nil, wallTexture: nil, desks: [], elevator: nil, hasLoungeSign: false),
    ])
    let now = Date(timeIntervalSince1970: 1_791_300_000)

    func a(_ id: String, _ status: AgentStatus, _ root: String, waitingSince: Date? = nil) -> OfficeAgent {
        OfficeAgent(id: id, name: id, owner: "office", status: status, cwd: root, repoRoot: root, waitingSince: waitingSince)
    }

    @Test func needsYouWinsNewestFirst() {
        let agents = [a("x", .working, "/w/claude-bar"), a("y", .waiting, "/w/pnp", waitingSince: now - 30), a("z", .waiting, "/w/claude-bar", waitingSince: now - 300)]
        #expect(FloorPlan.followTarget(building: building, agents: agents, attention: [], since: [:], now: now) == 10)
    }

    @Test func thenTheMostRecentStartOrFinishWithinAMinute() {
        let agents = [a("x", .working, "/w/claude-bar"), a("y", .working, "/w/claude-bar"), a("p", .working, "/w/pnp")]
        #expect(FloorPlan.followTarget(building: building, agents: agents, attention: [], since: ["p": now - 5, "x": now - 600], now: now) == 10)
    }

    @Test func sameMomentPrefersAWorkingCat() {
        // At launch every cat is first seen at the same instant: that's no change, so go where the work is.
        let agents = [a("i", .idle, "/w/pnp"), a("x", .working, "/w/claude-bar"), a("j", .idle, "/w/pnp")]
        let since = ["i": now - 3, "x": now - 3, "j": now - 3]
        #expect(FloorPlan.followTarget(building: building, agents: agents, attention: [], since: since, now: now) == 12)
        #expect(FloorPlan.followTarget(building: building, agents: agents.reversed(), attention: [], since: since, now: now) == 12)
    }

    @Test func thenTheBusiestFloorThenTheLounge() {
        let agents = [a("x", .working, "/w/claude-bar"), a("y", .working, "/w/claude-bar"), a("p", .working, "/w/pnp")]
        #expect(FloorPlan.followTarget(building: building, agents: agents, attention: [], since: [:], now: now) == 12)
        #expect(FloorPlan.followTarget(building: building, agents: [a("i", .idle, "/w/pnp")], attention: [], since: [:], now: now) == 1)
    }

    @Test func attentionCountsAsNeedsYou() {
        let agents = [a("x", .working, "/w/claude-bar"), a("done", .idle, "/w/pnp")]
        #expect(FloorPlan.followTarget(building: building, agents: agents, attention: ["done"], since: ["done": now - 2], now: now) == 1,
                "finished: it went idle, so it's in the Lounge")
    }

    @Test func stripShowsEachFloorsState() {
        let agents = [a("x", .working, "/w/claude-bar"), a("y", .waiting, "/w/pnp"), a("i", .idle, "/w/pnp")]
        let activity = FloorPlan.activity(of: building, agents: agents, attention: [])
        #expect(activity == [1: .idle, 6: .empty, 10: .needsYou, 12: .working])
        #expect(FloorPlan.cats(on: 10, agents: agents, in: building).map(\.id) == ["y"])
    }
}

@Suite struct FloorChoiceTests {
    let floors = [1, 2, 6, 12]

    @Test func aDeletedFloorTurnsFollowBackOn() {
        var c = FloorChoice()
        c.pick(9)
        c.reconcile(floors: floors)
        #expect(c.follow && c.manual == nil)
        c.pick(6)
        c.reconcile(floors: floors)
        #expect(!c.follow && c.manual == 6, "a floor that still exists stays picked")
    }

    @Test func followShowsTheTarget() {
        #expect(FloorChoice().shown(target: 12, floors: floors) == 12)
    }

    @Test func pickingAFloorTurnsFollowOff() {
        var c = FloorChoice()
        c.pick(6)
        #expect(!c.follow && c.shown(target: 12, floors: floors) == 6)
        c.resumeFollow()
        #expect(c.follow && c.shown(target: 12, floors: floors) == 12)
    }

    @Test func stepsMoveOneFloorAndStopAtTheEnds() {
        var c = FloorChoice()
        c.step(1, from: 6, floors: floors)
        #expect(c.manual == 12 && !c.follow)
        c.step(1, from: 12, floors: floors)
        #expect(c.manual == 12)
        c.step(-1, from: 1, floors: floors)
        #expect(c.manual == 1)
    }

    @Test func aDeletedFloorFallsBackToFollow() {
        var c = FloorChoice()
        c.pick(9)
        #expect(c.shown(target: 12, floors: floors) == 12, "floor 9 no longer exists")
    }
}

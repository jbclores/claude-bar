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

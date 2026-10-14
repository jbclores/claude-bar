import Foundation
import Testing
@testable import ClaudeBarCore

@Suite struct TerminalTTYTests {
    @Test func psOutputBecomesADevicePath() {
        #expect(TerminalTTY.path(psOutput: "ttys004\n") == "/dev/ttys004")
        #expect(TerminalTTY.path(psOutput: "  ttys012  ") == "/dev/ttys012")
        #expect(TerminalTTY.path(psOutput: "/dev/ttys001") == "/dev/ttys001")
    }

    @Test func noTerminalIsNil() {
        #expect(TerminalTTY.path(psOutput: "??") == nil)
        #expect(TerminalTTY.path(psOutput: "??\n") == nil)
        #expect(TerminalTTY.path(psOutput: "") == nil)
        #expect(TerminalTTY.path(psOutput: "\n") == nil)
    }
}

@Suite struct StickyCardTests {
    @Test func theHoveredCatWins() {
        #expect(StickyCard.shown(hovered: "a", card: "b", onCard: false, lingering: false) == "a")
    }

    @Test func theCardStaysWhileThePointerIsOnIt() {
        #expect(StickyCard.shown(hovered: nil, card: "a", onCard: true, lingering: false) == "a")
    }

    @Test func theCardLingersBrieflyOnTheWayToIt() {
        #expect(StickyCard.shown(hovered: nil, card: "a", onCard: false, lingering: true) == "a")
    }

    @Test func leavingBothClosesIt() {
        #expect(StickyCard.shown(hovered: nil, card: "a", onCard: false, lingering: false) == nil)
        #expect(StickyCard.shown(hovered: String?.none, card: nil, onCard: true, lingering: true) == nil)
    }
}

@Suite struct AnswerResetTests {
    func waiting(_ id: String, _ p: PendingPrompt?) -> OfficeAgent {
        var a = OfficeAgent(id: id, name: id, status: .waiting, cwd: "/tmp")
        a.pendingPrompt = p
        return a
    }

    @Test func aSamePromptKeepsTheState() {
        let before = [waiting("a", .plan("x"))]
        #expect(AnswerReset.stale(["a"], before: before, after: before).isEmpty)
    }

    @Test func aChangedPromptClearsIt() {
        let stale = AnswerReset.stale(["a"], before: [waiting("a", .plan("x"))], after: [waiting("a", .plan("y"))])
        #expect(stale == ["a"])
    }

    @Test func stoppingWaitingOrGoingAwayClearsIt() {
        var working = waiting("a", .plan("x")); working.status = .working
        #expect(AnswerReset.stale(["a"], before: [waiting("a", .plan("x"))], after: [working]) == ["a"])
        #expect(AnswerReset.stale(["a"], before: [waiting("a", .plan("x"))], after: []) == ["a"])
    }

    @Test func otherAgentsAreLeftAlone() {
        let before = [waiting("a", .plan("x")), waiting("b", .plan("z"))]
        let after = [waiting("a", .plan("x")), waiting("b", .plan("new"))]
        #expect(AnswerReset.stale(["a"], before: before, after: after).isEmpty)
    }
}

@Suite struct SessionLogEntriesTests {
    @Test func projectsComeFromTheRepoElseTheFolder() {
        var a = OfficeAgent(id: "a", name: "Ada", status: .working, cwd: "/Users/me/code/claude-bar", repoName: "claude-bar")
        a.sessionId = "s-a"
        let b = OfficeAgent(id: "b", name: "Bo", status: .idle, cwd: "/Users/me/code/turbo")
        var helper = OfficeAgent(id: "h", name: "h", status: .working, cwd: "/tmp/elsewhere")
        helper.kind = "subagent"; helper.parentName = "Ada"
        let fallback = [LiveSession(key: "t", cwd: "/Users/me/code/notes", status: .waiting, name: "notes")]
        let tracked = StatusModel.trackedSessions(fallback: fallback, office: OfficeSnapshot(agents: [a, b, helper]))
        let entries = SessionLog.entries(tracked: tracked, agents: [a, b, helper], fallback: fallback)
        #expect(entries.map(\.key) == ["s-a", "b", "h", "t"])
        #expect(entries.map(\.project) == ["claude-bar", "turbo", "claude-bar", "notes"])
        #expect(entries.map(\.status) == [.working, .idle, .working, .waiting])
    }
}

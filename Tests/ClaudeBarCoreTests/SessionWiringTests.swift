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
        #expect(StickyCard.shown(hovered: "a", hoveredFor: 0, card: "b", onCard: false, lingering: false) == "a")
    }

    @Test func theCardStaysWhileThePointerIsOnIt() {
        #expect(StickyCard.shown(hovered: nil, hoveredFor: 0, card: "a", onCard: true, lingering: false) == "a")
    }

    @Test func theCardLingersBrieflyOnTheWayToIt() {
        #expect(StickyCard.shown(hovered: nil, hoveredFor: 0, card: "a", onCard: false, lingering: true) == "a")
    }

    @Test func leavingBothClosesIt() {
        #expect(StickyCard.shown(hovered: nil, hoveredFor: 0, card: "a", onCard: false, lingering: false) == nil)
        #expect(StickyCard.shown(hovered: String?.none, hoveredFor: 0, card: nil, onCard: true, lingering: true) == nil)
    }

    /// On the way up to the card the pointer crosses other cats: the card stays on its cat unless the pointer rests on
    /// another one (StickyCard.switchAfter, ~150 ms).
    @Test func passingOverAnotherCatOnTheWayKeepsTheCard() {
        #expect(StickyCard.switchAfter == 0.15)
        #expect(StickyCard.shown(hovered: "b", hoveredFor: 0.05, card: "a", onCard: false, lingering: true) == "a")
        #expect(StickyCard.shown(hovered: "b", hoveredFor: 0.149, card: "a", onCard: false, lingering: true) == "a")
        #expect(StickyCard.shown(hovered: "b", hoveredFor: 0.15, card: "a", onCard: false, lingering: true) == "b")
        #expect(StickyCard.shown(hovered: "b", hoveredFor: 0.05, card: "a", onCard: true, lingering: false) == "a")
        #expect(StickyCard.shown(hovered: "b", hoveredFor: 0.3, card: "a", onCard: true, lingering: false) == "b")
        #expect(StickyCard.shown(hovered: "a", hoveredFor: 0, card: "a", onCard: false, lingering: true) == "a")
        #expect(StickyCard.shown(hovered: "b", hoveredFor: 0, card: String?.none, onCard: false, lingering: true) == "b", "no card yet")
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

    @Test func aSentAnswerExpiresWhileTheSamePromptWaits() {
        let t0 = Date(timeIntervalSince1970: 1_800_000_000)
        // Fresh: kept.
        #expect(!AnswerReset.sentIsStale(sentAt: t0, now: t0.addingTimeInterval(3)))
        // 11 s on, still waiting on the same prompt: the buttons come back.
        #expect(AnswerReset.sentIsStale(sentAt: t0, now: t0.addingTimeInterval(11)))
        // A different prompt: cleared at once, as before.
        #expect(AnswerReset.stale(["a"], before: [waiting("a", .plan("x"))], after: [waiting("a", .plan("y"))]) == ["a"])
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

@Suite struct AnswerTicketsTests {
    /// An older send finishing after a newer click (on a new prompt) doesn't overwrite the newer one's state.
    @Test func onlyTheLatestSendPerAgentCounts() {
        var tickets = AnswerTickets()
        let first = tickets.issue(for: "a")
        let other = tickets.issue(for: "b")
        let second = tickets.issue(for: "a")
        #expect(!tickets.isLatest(first, for: "a"))
        #expect(tickets.isLatest(second, for: "a"))
        #expect(tickets.isLatest(other, for: "b"))
        #expect(!tickets.isLatest(second, for: "b"))
    }
}

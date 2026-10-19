import Testing
import Foundation
@testable import ClaudeBarCore

@Suite struct VoiceConversationTests {
    let perm = VoiceWaiting(id: "a1", name: "claude-bar", prompt: .permission(tool: "Bash", input: "npm run build"))
    let perm2 = VoiceWaiting(id: "b2", name: "pnp-ufdms", prompt: .permission(tool: "Bash", input: "npm run build"))
    let plan = VoiceWaiting(id: "c3", name: "turborepo-lab", prompt: .plan("# Ship it"))
    let t0 = Date(timeIntervalSince1970: 1_000_000)

    func question(_ labels: [String]) -> PendingPrompt {
        .question([.init(question: "Which db?", header: "DB", multiSelect: false,
                         options: labels.map { .init(label: $0, description: "") })])
    }

    @Test func allowOneWaitingConfirmsThenSends() {
        var c = VoiceConversation()
        #expect(c.handle(VoiceCommand(intent: .allow), waiting: [perm], now: t0) == .say("Allow npm run build for claude-bar? Say yes."))
        #expect(c.handle(VoiceCommand(intent: .yes), waiting: [perm], now: t0)
            == .send(agentId: "a1", prompt: perm.prompt, button: 0, then: "Allowed."))
    }

    @Test func alwaysAllowWording() {
        var c = VoiceConversation()
        #expect(c.handle(VoiceCommand(intent: .alwaysAllow), waiting: [perm], now: t0) == .say("Always allow npm run build for claude-bar? Say yes."))
        #expect(c.handle(VoiceCommand(intent: .yes), waiting: [perm], now: t0)
            == .send(agentId: "a1", prompt: perm.prompt, button: 1, then: "Always allowed."))
    }

    @Test func denyGoesAtOnce() {
        var c = VoiceConversation()
        #expect(c.handle(VoiceCommand(intent: .deny), waiting: [perm], now: t0)
            == .send(agentId: "a1", prompt: perm.prompt, button: 2, then: "Denied for claude-bar."))
    }

    @Test func severalWaitingAsksWhichOne() {
        var c = VoiceConversation()
        #expect(c.handle(VoiceCommand(intent: .allow), waiting: [perm, perm2], now: t0) == .say("Two are waiting: claude-bar and pnp-ufdms. Which one?"))
        #expect(c.handle(VoiceCommand(intent: .name, target: "b2"), waiting: [perm, perm2], now: t0) == .say("Allow npm run build for pnp-ufdms? Say yes."))
        #expect(c.handle(VoiceCommand(intent: .yes), waiting: [perm, perm2], now: t0)
            == .send(agentId: "b2", prompt: perm2.prompt, button: 0, then: "Allowed."))
    }

    @Test func sameIntentWithTargetContinuesPick() {
        var c = VoiceConversation()
        _ = c.handle(VoiceCommand(intent: .allow), waiting: [perm, perm2], now: t0)
        #expect(c.handle(VoiceCommand(intent: .allow, target: "a1"), waiting: [perm, perm2], now: t0) == .say("Allow npm run build for claude-bar? Say yes."))
    }

    @Test func otherIntentDuringPickIsNew() {
        var c = VoiceConversation()
        _ = c.handle(VoiceCommand(intent: .allow), waiting: [perm, perm2], now: t0)
        #expect(c.handle(VoiceCommand(intent: .deny, target: "a1"), waiting: [perm, perm2], now: t0)
            == .send(agentId: "a1", prompt: perm.prompt, button: 2, then: "Denied for claude-bar."))
    }

    @Test func threeWaitingNames() {
        var c = VoiceConversation()
        let p3 = VoiceWaiting(id: "d4", name: "lab", prompt: perm.prompt)
        #expect(c.handle(VoiceCommand(intent: .deny), waiting: [perm, perm2, p3], now: t0) == .say("Three are waiting: claude-bar, pnp-ufdms and lab. Which one?"))
    }

    @Test func noDuringConfirmCancels() {
        var c = VoiceConversation()
        _ = c.handle(VoiceCommand(intent: .allow), waiting: [perm], now: t0)
        #expect(c.handle(VoiceCommand(intent: .deny), waiting: [perm], now: t0) == .say("Okay."))
        #expect(c.handle(VoiceCommand(intent: .yes), waiting: [perm], now: t0) == .say("Nothing to confirm."))
    }

    @Test func cancelDuringConfirm() {
        var c = VoiceConversation()
        _ = c.handle(VoiceCommand(intent: .allow), waiting: [perm], now: t0)
        #expect(c.handle(VoiceCommand(intent: .cancel), waiting: [perm], now: t0) == .say("Okay."))
    }

    @Test func confirmExpires() {
        var c = VoiceConversation()
        _ = c.handle(VoiceCommand(intent: .allow), waiting: [perm], now: t0)
        #expect(c.handle(VoiceCommand(intent: .yes), waiting: [perm], now: t0.addingTimeInterval(21)) == .say("Nothing to confirm."))
    }

    @Test func confirmKeepsItsPrompt() {
        var c = VoiceConversation()
        _ = c.handle(VoiceCommand(intent: .allow), waiting: [perm], now: t0)
        let other = VoiceWaiting(id: "a1", name: "claude-bar", prompt: .permission(tool: "Bash", input: "rm -rf x"))
        #expect(c.handle(VoiceCommand(intent: .yes), waiting: [other], now: t0)
            == .send(agentId: "a1", prompt: perm.prompt, button: 0, then: "Allowed."))
    }

    @Test func otherCommandDuringConfirmIsNew() {
        var c = VoiceConversation()
        _ = c.handle(VoiceCommand(intent: .allow), waiting: [perm], now: t0)
        #expect(c.handle(VoiceCommand(intent: .status), waiting: [perm], now: t0) == .status)
        #expect(c.handle(VoiceCommand(intent: .yes), waiting: [perm], now: t0) == .say("Nothing to confirm."))
    }

    @Test func wrongKind() {
        var c = VoiceConversation()
        #expect(c.handle(VoiceCommand(intent: .approve), waiting: [perm], now: t0) == .say("claude-bar is asking for permission, not a plan."))
    }

    @Test func noButtons() {
        var c = VoiceConversation()
        let two = VoiceWaiting(id: "q1", name: "lab", prompt: .question([
            .init(question: "A?", header: "A", multiSelect: false, options: [.init(label: "x", description: "")]),
            .init(question: "B?", header: "B", multiSelect: false, options: [.init(label: "y", description: "")]),
        ]))
        #expect(c.handle(VoiceCommand(intent: .option(0)), waiting: [two], now: t0) == .say("Answer that one in Cat Office."))
    }

    @Test func nothingWaiting() {
        var c = VoiceConversation()
        #expect(c.handle(VoiceCommand(intent: .allow), waiting: [], now: t0) == .say("Nothing is waiting."))
    }

    @Test func planAndOption() {
        var c = VoiceConversation()
        #expect(c.handle(VoiceCommand(intent: .approve), waiting: [plan], now: t0) == .say("Approve turborepo-lab's plan? Say yes."))
        #expect(c.handle(VoiceCommand(intent: .yes), waiting: [plan], now: t0)
            == .send(agentId: "c3", prompt: plan.prompt, button: 0, then: "Approved."))
        #expect(c.handle(VoiceCommand(intent: .reject), waiting: [plan], now: t0)
            == .send(agentId: "c3", prompt: plan.prompt, button: 1, then: "Rejected turborepo-lab's plan."))
        let q = VoiceWaiting(id: "q1", name: "lab", prompt: question(["PostgreSQL", "SQLite"]))
        #expect(c.handle(VoiceCommand(intent: .option(1)), waiting: [q], now: t0) == .say("Answer 'SQLite' for lab? Say yes."))
        #expect(c.handle(VoiceCommand(intent: .yes), waiting: [q], now: t0)
            == .send(agentId: "q1", prompt: q.prompt, button: 1, then: "Answered."))
    }

    @Test func optionOutOfRangeDoesNotFit() {
        var c = VoiceConversation()
        let q = VoiceWaiting(id: "q1", name: "lab", prompt: question(["A", "B"]))
        let r = c.handle(VoiceCommand(intent: .option(5)), waiting: [q], now: t0)
        #expect(r == .say("lab has no such choice."))
    }

    @Test func editWording() {
        var c = VoiceConversation()
        let e = VoiceWaiting(id: "e1", name: "lab", prompt: .permission(tool: "Edit", input: "/x/Login.swift\nold"))
        #expect(c.handle(VoiceCommand(intent: .allow), waiting: [e], now: t0) == .say("Allow an edit to Login.swift for lab? Say yes."))
    }

    @Test func infoAndNoise() {
        var c = VoiceConversation()
        #expect(c.handle(VoiceCommand(intent: .status), waiting: [], now: t0) == .status)
        #expect(c.handle(VoiceCommand(intent: .usage), waiting: [], now: t0) == .usage)
        #expect(c.handle(VoiceCommand(intent: .recap), waiting: [], now: t0) == .recap)
        #expect(c.handle(VoiceCommand(intent: .none), waiting: [], now: t0) == .say("Sorry, I didn't catch that."))
        #expect(c.handle(VoiceCommand(intent: .name, target: "a1"), waiting: [], now: t0) == .say("Sorry, I didn't catch that."))
    }

    @Test func targetNoLongerWaiting() {
        var c = VoiceConversation()
        _ = c.handle(VoiceCommand(intent: .deny), waiting: [perm, perm2], now: t0)
        #expect(c.handle(VoiceCommand(intent: .name, target: "b2"), waiting: [perm], now: t0) == .say("That one isn't waiting anymore."))
        #expect(c.handle(VoiceCommand(intent: .deny, target: "b2"), waiting: [perm], now: t0) == .say("That one isn't waiting anymore."))
        #expect(c.handle(VoiceCommand(intent: .allow, target: "b2"), waiting: [perm], now: t0) == .say("That one isn't waiting anymore."))
    }

    @Test func noButtonsAmongSeveral() {
        var c = VoiceConversation()
        func two(_ id: String) -> VoiceWaiting {
            VoiceWaiting(id: id, name: id, prompt: .question([
                .init(question: "A?", header: "A", multiSelect: false, options: []),
                .init(question: "B?", header: "B", multiSelect: false, options: []),
            ]))
        }
        #expect(c.handle(VoiceCommand(intent: .allow), waiting: [two("x"), two("y")], now: t0) == .say("Answer that one in Cat Office."))
        #expect(c.handle(VoiceCommand(intent: .allow), waiting: [two("x"), plan], now: t0)
            == .say("turborepo-lab is asking you to approve a plan, not permission."))
    }
    @Test func onlyATerminalSessionWaiting() {
        var c = VoiceConversation()
        let term = VoiceWaiting(id: "t1", name: "lab", prompt: perm.prompt, answerable: false)
        #expect(c.handle(VoiceCommand(intent: .allow), waiting: [term], now: t0) == .say("Answer that one in its terminal."))
        #expect(c.handle(VoiceCommand(intent: .deny, target: "t1"), waiting: [term], now: t0) == .say("Answer that one in its terminal."))
    }

    @Test func terminalSessionIsNeverTargeted() {
        var c = VoiceConversation()
        let term = VoiceWaiting(id: "t1", name: "lab", prompt: perm.prompt, answerable: false)
        #expect(c.handle(VoiceCommand(intent: .allow), waiting: [plan, term], now: t0) == .say("Answer that one in its terminal."))
        #expect(c.handle(VoiceCommand(intent: .allow), waiting: [plan, term, perm], now: t0) == .say("Allow npm run build for claude-bar? Say yes."))
        #expect(c.handle(VoiceCommand(intent: .approve), waiting: [plan, term], now: t0) == .say("Approve turborepo-lab's plan? Say yes."))
    }
}

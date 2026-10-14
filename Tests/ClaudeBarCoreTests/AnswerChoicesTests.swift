import Foundation
import Testing
@testable import ClaudeBarCore

@Suite struct AnswerChoicesTests {
    func json(_ d: Data) -> String { String(decoding: d, as: UTF8.self) }

    @Test func permissionsByTool() {
        let bash = AnswerChoices.of(.permission(tool: "Bash", input: "npm run build"))
        #expect(bash.prompt == "Allow this command?" && bash.detail == "npm run build")
        #expect(bash.buttons.map(\.title) == ["Allow", "Always allow", "Deny"])
        // `expect`: the prompt the button was built from; Cat Office refuses (409) if the session now waits on another.
        let expect = #""expect":{"input":"npm run build","tool":"Bash"}"#
        #expect(bash.buttons.map { json($0.request) } == [
            #"{"choice":"yes","#+expect+#","kind":"permission"}"#, #"{"choice":"yes-always","#+expect+#","kind":"permission"}"#,
            #"{"choice":"no","#+expect+#","kind":"permission"}"#])
        #expect(json(AnswerChoices.of(.permission(tool: "Read", input: "/tmp/a b")).buttons[0].request)
            == #"{"choice":"yes","expect":{"input":"/tmp/a b","tool":"Read"},"kind":"permission"}"#, "slashes as they are")
        #expect(AnswerChoices.of(.permission(tool: "Edit", input: "a.swift")).prompt == "Allow this edit?")
        #expect(AnswerChoices.of(.permission(tool: "WebFetch", input: "x")).prompt == "Allow WebFetch?")
    }

    @Test func oneSingleQuestionGetsItsOptions() {
        let q = PendingPrompt.Question(question: "Which auth?", header: "Auth", multiSelect: false,
                                       options: [.init(label: "OAuth", description: "Sign in"), .init(label: "Token", description: "Paste")])
        let c = AnswerChoices.of(.question([q]))
        #expect(c.prompt == "Which auth?" && c.buttons.map(\.title) == ["OAuth", "Token"])
        #expect(c.buttons[1].help == "Paste")
        #expect(json(c.buttons[1].request) == #"{"answers":[{"optionIndexes":[1]}],"expect":"Which auth?","kind":"question"}"#)
        var multi = q
        multi.multiSelect = true
        #expect(AnswerChoices.of(.question([multi])).buttons.isEmpty, "multi-pick: answer in Cat Office")
        #expect(AnswerChoices.of(.question([q, q])).buttons.isEmpty, "several questions: answer in Cat Office")
    }

    @Test func plans() {
        let c = AnswerChoices.of(.plan("# Add login\n\nSteps…"))
        #expect(c.prompt == "Claude proposes a plan" && c.detail == "Add login")
        #expect(c.buttons.map(\.title) == ["Approve", "Reject"])
        #expect(json(c.buttons[0].request) == ##"{"choice":"approve","expect":"# Add login\n\nSteps…","kind":"plan"}"##)
        #expect(json(c.buttons[1].request) == ##"{"choice":"reject","expect":"# Add login\n\nSteps…","kind":"plan"}"##)
    }

    /// Cat Office's 409 texts (server/agent-bridge/answer.ts, index.ts, and the patch's `expect` check) in plain words.
    @Test func eachConflictReadsPlainly() {
        let changed = "That question closed or changed before your answer got there"
        let terminal = "Cat Office can't answer this session: answer it in its terminal"
        let screen = "The question isn't on screen in its terminal"
        func r(_ e: String?) -> String { AnswerChoices.refusal(status: 409, error: e) }
        #expect(r("nothing to answer: the session is not waiting on a question, permission or plan") == changed)
        #expect(r("the open dialog is a question, not permission") == changed)
        #expect(r("the question changed") == changed)
        #expect(r("the session has ended") == changed)
        #expect(r("the question dialog is not on screen") == screen)
        #expect(r("the permission prompt is not on screen") == screen)
        #expect(r("the plan approval is not on screen") == screen)
        #expect(r(#"this prompt has no "yes-always" option"#) == "This prompt has no Always allow")
        #expect(r(#"this prompt has no "no" option"#) == "This prompt has no such choice: answer it in its terminal")
        #expect(r(#"this plan prompt has no "Yes" option"#) == "This prompt has no such choice: answer it in its terminal")
        #expect(r("this session is not in an Orca terminal") == terminal)
        #expect(r("office workers have no dialogs to answer") == terminal)
        #expect(r("helpers are read-only: only their parent session talks to them") == terminal)
        #expect(r("something new") == terminal, "unknown 409")
        #expect(r(nil) == terminal)
    }

    @Test func refusalsReadPlainly() {
        #expect(AnswerChoices.refusal(status: 409, error: "no terminal") == "Cat Office can't answer this session: answer it in its terminal")
        #expect(AnswerChoices.refusal(status: nil, error: nil) == "Couldn't reach Cat Office")
        #expect(AnswerChoices.refusal(status: 400, error: "answers don't fit") == "answers don't fit")
        #expect(AnswerChoices.refusal(status: 500, error: nil) == "Cat Office couldn't send it (error 500)")
    }

    /// A button is sent only while its agent still waits on the prompt it was built from.
    @Test func aButtonGoesOnlyToThePromptItWasBuiltFor() {
        let asked = PendingPrompt.permission(tool: "Bash", input: "npm run build")
        func agent(_ status: AgentStatus, _ p: PendingPrompt?) -> OfficeAgent {
            var a = OfficeAgent(id: "a", name: "a", status: status, cwd: "/tmp")
            a.pendingPrompt = p
            return a
        }
        let changed = "That question changed: check it again"
        #expect(AnswerChoices.changed(asked, agentId: "a", in: [agent(.waiting, asked)]) == nil)
        #expect(AnswerChoices.changed(asked, agentId: "a", in: [agent(.waiting, .permission(tool: "Bash", input: "rm -rf build"))]) == changed)
        #expect(AnswerChoices.changed(asked, agentId: "a", in: [agent(.working, nil)]) == changed)
        #expect(AnswerChoices.changed(asked, agentId: "a", in: [agent(.working, asked)]) == changed, "no longer waiting")
        #expect(AnswerChoices.changed(asked, agentId: "a", in: []) == changed, "gone")
    }
}

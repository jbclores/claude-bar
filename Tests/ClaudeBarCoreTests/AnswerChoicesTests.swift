import Foundation
import Testing
@testable import ClaudeBarCore

@Suite struct AnswerChoicesTests {
    func json(_ d: Data) -> String { String(decoding: d, as: UTF8.self) }

    @Test func permissionsByTool() {
        let bash = AnswerChoices.of(.permission(tool: "Bash", input: "npm run build"))
        #expect(bash.prompt == "Allow this command?" && bash.detail == "npm run build")
        #expect(bash.buttons.map(\.title) == ["Allow", "Always allow", "Deny"])
        #expect(bash.buttons.map { json($0.request) } == [
            #"{"choice":"yes","kind":"permission"}"#, #"{"choice":"yes-always","kind":"permission"}"#, #"{"choice":"no","kind":"permission"}"#])
        #expect(AnswerChoices.of(.permission(tool: "Edit", input: "a.swift")).prompt == "Allow this edit?")
        #expect(AnswerChoices.of(.permission(tool: "WebFetch", input: "x")).prompt == "Allow WebFetch?")
    }

    @Test func oneSingleQuestionGetsItsOptions() {
        let q = PendingPrompt.Question(question: "Which auth?", header: "Auth", multiSelect: false,
                                       options: [.init(label: "OAuth", description: "Sign in"), .init(label: "Token", description: "Paste")])
        let c = AnswerChoices.of(.question([q]))
        #expect(c.prompt == "Which auth?" && c.buttons.map(\.title) == ["OAuth", "Token"])
        #expect(c.buttons[1].help == "Paste")
        #expect(json(c.buttons[1].request) == #"{"answers":[{"optionIndexes":[1]}],"kind":"question"}"#)
        var multi = q
        multi.multiSelect = true
        #expect(AnswerChoices.of(.question([multi])).buttons.isEmpty, "multi-pick: answer in Cat Office")
        #expect(AnswerChoices.of(.question([q, q])).buttons.isEmpty, "several questions: answer in Cat Office")
    }

    @Test func plans() {
        let c = AnswerChoices.of(.plan("# Add login\n\nSteps…"))
        #expect(c.prompt == "Claude proposes a plan" && c.detail == "Add login")
        #expect(c.buttons.map(\.title) == ["Approve", "Reject"])
        #expect(json(c.buttons[0].request) == #"{"choice":"approve","kind":"plan"}"#)
    }

    @Test func refusalsReadPlainly() {
        #expect(AnswerChoices.refusal(status: 409, error: "no terminal") == "Cat Office can't answer this session: answer it in its terminal")
        #expect(AnswerChoices.refusal(status: nil, error: nil) == "Couldn't reach Cat Office")
        #expect(AnswerChoices.refusal(status: 400, error: "answers don't fit") == "answers don't fit")
        #expect(AnswerChoices.refusal(status: 500, error: nil) == "Cat Office couldn't send it (error 500)")
    }
}

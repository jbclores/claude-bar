import Foundation
import Testing
@testable import ClaudeBarCore

@Suite struct PendingPromptTests {
    func agent(_ json: String) throws -> OfficeAgent { try JSONDecoder().decode(OfficeAgent.self, from: Data(json.utf8)) }

    @Test func decodesEachKind() throws {
        let p = try agent(#"{"id":"a","status":"waiting","pid":4242,"pendingPrompt":{"kind":"permission","tool":"Bash","input":"npm run build"}}"#)
        #expect(p.pendingPrompt == .permission(tool: "Bash", input: "npm run build"))
        #expect(p.pid == 4242)
        let q = try agent(#"{"id":"a","status":"waiting","pendingPrompt":{"kind":"question","questions":[{"question":"Which auth?","header":"Auth","multiSelect":false,"options":[{"label":"OAuth","description":"Sign in"},{"label":"Token","description":"Paste"}]}]}}"#)
        #expect(q.pendingPrompt == .question([.init(question: "Which auth?", header: "Auth", multiSelect: false,
                                                     options: [.init(label: "OAuth", description: "Sign in"), .init(label: "Token", description: "Paste")])]))
        let plan = try agent(##"{"id":"a","status":"waiting","pendingPrompt":{"kind":"plan","plan":"# Plan\nDo it"}}"##)
        #expect(plan.pendingPrompt == .plan("# Plan\nDo it"))
    }

    @Test func missingOrUnknownIsNil() throws {
        #expect(try agent(#"{"id":"a","status":"idle"}"#).pendingPrompt == nil)
        #expect(try agent(#"{"id":"a","status":"waiting","pendingPrompt":null}"#).pendingPrompt == nil)
        #expect(try agent(#"{"id":"a","status":"waiting","pendingPrompt":{"kind":"something-new"}}"#).pendingPrompt == nil)
        #expect(try agent(#"{"id":"a","status":"idle","pid":null}"#).pid == nil)
    }
}

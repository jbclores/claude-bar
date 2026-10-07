import Foundation
import Testing
@testable import ClaudeBarCore

@Suite struct SubagentTests {
    @Test func decodesSubagentFieldsAndLabelsByDescription() throws {
        let json = #"{"type":"snapshot","snapshot":{"agents":[{"id":"a69adf54739f5af29","name":"a69adf54739f5af29","owner":"external","status":"working","cwd":"/","kind":"subagent","parentName":"office-82eb65","agentType":"Explore","description":"Review Cat Office walking"}]}}"#
        guard case .snapshot(let snap)? = CatOfficeEvent.decode(json) else { Issue.record("no snapshot"); return }
        let a = snap.agents[0]
        #expect(a.isSubagent && a.parentName == "office-82eb65" && a.agentType == "Explore")
        #expect(a.label == "Review Cat Office walking")
    }

    @Test func officeListShowsSubagentsUnderTheirParent() {
        var helper = OfficeAgent(id: "h1", name: "h1", status: .working, cwd: "/w/app")
        helper.kind = "subagent"; helper.parentName = "office-b"; helper.agentType = "Explore"; helper.agentDescription = "Find usages"
        var orphan = OfficeAgent(id: "h2", name: "h2", status: .working, cwd: "/w")
        orphan.kind = "subagent"; orphan.parentName = "someone-else"; orphan.agentDescription = "Lost helper"
        var ended = helper; ended.status = .ended; ended.name = "h3"
        let office = OfficeSnapshot(agents: [
            OfficeAgent(id: "b", name: "office-b", owner: "office", status: .working, cwd: "/w/app"),
            OfficeAgent(id: "a", name: "office-a", owner: "office", status: .idle, cwd: "/w"),
            helper, orphan, ended,
        ])
        let rows = StatusModel.build(StatusInput(projects: [], office: office)).office ?? []
        #expect(rows.map(\.id) == ["a", "b", "h1", "h2"])
        #expect(rows[2].isSubagent && rows[2].parentName == "office-b" && rows[2].agentType == "Explore")
        #expect(rows[2].label == "Find usages")
        #expect(!rows[0].isSubagent)
    }
}

@Suite struct ProjectHelpersTests {
    @Test func projectRowsCountHelpersSeparately() {
        let app = Project(path: "/w/app", name: "app")
        var h1 = OfficeAgent(id: "h1", name: "h1", status: .working, cwd: "/w/app", sessionId: "h1")
        h1.kind = "subagent"
        var h2 = h1; h2.id = "h2"; h2.sessionId = "h2"
        var done = h1; done.id = "h3"; done.sessionId = "h3"; done.status = .ended
        let office = OfficeSnapshot(agents: [
            OfficeAgent(id: "p", name: "office-p", owner: "office", status: .idle, cwd: "/w/app", sessionId: "p"),
            h1, h2, done,
        ])
        let row = StatusModel.build(StatusInput(projects: [app], office: office, existing: ["/w/app"])).projects[0]
        #expect(row.helpers == 2)
        #expect(row.state == .live(.idle, count: 1), "helpers don't change the main status or count")
    }

    @Test func onlyHelpersStillShowTheProjectAsLive() {
        let app = Project(path: "/w/app", name: "app")
        var h = OfficeAgent(id: "h", name: "h", status: .working, cwd: "/w/app", sessionId: "h")
        h.kind = "subagent"
        let row = StatusModel.build(StatusInput(projects: [app], office: OfficeSnapshot(agents: [h]), existing: ["/w/app"])).projects[0]
        #expect(row.helpers == 1 && row.state == .live(.working, count: 1))
    }
}

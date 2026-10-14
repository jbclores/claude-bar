import Foundation
import Testing
@testable import ClaudeBarCore

@Suite struct LabelTests {
    let t = Date(timeIntervalSince1970: 1_791_266_000)

    func agent(task: String? = nil, source: String? = nil, repo: String? = nil, name: String = "office-82eb65") -> OfficeAgent {
        var a = OfficeAgent(id: "a", name: name, owner: "office", status: .working, cwd: "/", repoName: repo, task: task)
        a.titleSource = source
        return a
    }

    @Test func projectFirstThenTaskWordsThenName() {
        #expect(agent(task: "I want to create a simple app", source: "prompt", repo: "claude-bar").label == "claude-bar")
        #expect(agent(task: "Create me a status line concept but apply here", source: "prompt").label == "Create me a status line…")
        #expect(agent(task: "hi", source: "prompt").label == "hi")
        #expect(agent().label == "office-82eb65")
    }

    @Test func customOrAiTitleWins() {
        #expect(agent(task: "Dropdown tabs", source: "custom", repo: "claude-bar").label == "Dropdown tabs")
        #expect(agent(task: "Fix invite expiry", source: "ai", repo: "app").label == "Fix invite expiry")
    }

    @Test func shortTitleCutsAtWordsAndCollapsesSpace() {
        #expect(Format.shortTitle("  Can you\ncheck   what is the agents available", max: 24) == "Can you check what is…")
        #expect(Format.shortTitle("Supercalifragilisticexpialidocious-and-more", max: 12) == "Supercalifr…")
        #expect(Format.shortTitle("short", max: 24) == "short")
    }

    @Test func statusText() {
        #expect(Format.statusText(.working, needsYou: false, since: t - 190, now: t, words: .standard) == "running 3m")
        #expect(Format.statusText(.waiting, needsYou: true, since: t - 30, now: t, words: .standard) == "needs you")
        #expect(Format.statusText(.idle, needsYou: true, since: nil, now: t, words: .standard) == "needs you")
        #expect(Format.statusText(.idle, needsYou: false, since: nil, now: t, words: .standard) == "idle")
        #expect(Format.statusText(.ended, needsYou: false, since: nil, now: t, words: .standard) == "ended")
    }

    /// Cat Office's words (status.ts STATUS_LABEL), or a teammate's own: "Running" on its own, "running 3m" in a line.
    @Test func statusWordsFollowCatOffice() throws {
        #expect(StatusWords.standard.word(.working) == "Running" && StatusWords.standard.word(.waiting) == "Needs you")
        #expect(StatusWords.standard.inline(.working) == "running" && StatusWords.standard.inline(.waiting) == "needs you")
        let busy = try #require(StatusWords(["waiting": "Your turn", "working": "Busy", "idle": "Resting", "ended": "Done"]))
        #expect(Format.statusText(.working, needsYou: false, since: t - 190, now: t, words: busy) == "busy 3m")
        #expect(Format.statusText(.idle, needsYou: true, since: nil, now: t, words: busy) == "your turn")
        #expect(StatusWords(["working": "Busy"]) == nil, "all four, or none")
        #expect(StatusWords(["waiting": "", "working": "Busy", "idle": "Resting", "ended": "Done"]) == nil)
        // From Cat Office's snapshot; an older patch sends none.
        let snap = try JSONDecoder().decode(OfficeSnapshot.self, from: Data(#"{"agents":[],"statusLabels":{"waiting":"Your turn","working":"Busy","idle":"Resting","ended":"Done"}}"#.utf8))
        #expect(snap.statusWords == busy)
        #expect(try JSONDecoder().decode(OfficeSnapshot.self, from: Data(#"{"agents":[]}"#.utf8)).statusWords == nil)
        // Kept between launches as a plain dictionary.
        #expect(StatusWords(busy.dictionary) == busy)
    }

    @Test func officeRowsCarryLabelAndLastAction() {
        var a = OfficeAgent(id: "1", name: "office-1", owner: "office", status: .idle, cwd: "/w/app", repoName: "app",
                            task: "long first prompt", lastAction: "Bash: swift test")
        a.titleSource = "prompt"
        let row = StatusModel.build(StatusInput(projects: [], office: OfficeSnapshot(agents: [a]))).office?.first
        #expect(row?.label == "app")
        #expect(row?.lastAction == "Bash: swift test")
    }

    @Test func decodesTitleSource() throws {
        let json = #"{"type":"snapshot","snapshot":{"agents":[{"id":"x","status":"idle","cwd":"/","task":"T","titleSource":"ai"}]}}"#
        guard case .snapshot(let snap)? = CatOfficeEvent.decode(json) else { Issue.record("no snapshot"); return }
        #expect(snap.agents[0].titleSource == "ai")
        #expect(snap.agents[0].label == "T")
    }
}

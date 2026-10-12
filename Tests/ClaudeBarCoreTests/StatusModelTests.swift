import Foundation
import Testing
@testable import ClaudeBarCore

@Suite struct StatusModelTests {
    let t0 = Date(timeIntervalSince1970: 1_791_266_000)
    let app = Project(path: "/w/app", name: "app")
    let api = Project(path: "/w/app/api", name: "api")
    let docs = Project(path: "/w/docs", name: "docs")

    func snap(_ id: String, _ cwd: String, at offset: TimeInterval, model: String? = "Opus 5.5", ctx: Double? = 10,
              five: Double? = nil, seven: Double? = nil) -> Snapshot {
        Snapshot(sessionId: id, cwd: cwd, model: model, contextPct: ctx, fiveHourPct: five, sevenDayPct: seven,
                 updatedAt: t0.addingTimeInterval(offset))
    }

    func input(_ projects: [Project], snaps: [Snapshot] = [], live: [LiveSession] = [], office: OfficeSnapshot? = nil,
               attention: Set<String> = []) -> StatusInput {
        StatusInput(projects: projects, snapshots: snaps, fallbackSessions: live, office: office,
                    branches: Dictionary(uniqueKeysWithValues: projects.map { ($0.path, "main") }),
                    existing: Set(projects.map(\.path)), attention: attention)
    }

    @Test func nestedProjectsTakeLongestMatch() {
        let out = StatusModel.build(input([app, api], snaps: [
            snap("a", "/w/app/src", at: 0, model: "Opus 5.5"),
            snap("b", "/w/app/api/handlers", at: 0, model: "Sonnet 5.5"),
        ]))
        #expect(out.projects[0].model == "Opus 5.5")
        #expect(out.projects[1].model == "Sonnet 5.5")
    }

    @Test func prefixOfNameIsNotInside() {
        let out = StatusModel.build(input([app], snaps: [snap("a", "/w/application", at: 0)]))
        #expect(out.projects[0].state == .noSessions)
    }

    @Test func newestSnapshotSuppliesModelAndContext() {
        let out = StatusModel.build(input([app], snaps: [
            snap("old", "/w/app", at: 0, model: "Haiku", ctx: 5),
            snap("new", "/w/app", at: 60, model: "Opus 5.5", ctx: 61),
        ]))
        #expect(out.projects[0].model == "Opus 5.5")
        #expect(out.projects[0].contextPct == 61)
        #expect(out.projects[0].state == .stale(since: t0.addingTimeInterval(60)))
    }

    @Test func liveStateUsesMostUrgentStatusAndCounts() {
        let live = [
            LiveSession(key: "a", cwd: "/w/app", status: .working, name: "a"),
            LiveSession(key: "b", cwd: "/w/app/src", status: .waiting, name: "b"),
        ]
        let out = StatusModel.build(input([app], snaps: [snap("a", "/w/app", at: 0)], live: live))
        #expect(out.projects[0].state == .live(.waiting, count: 2))
    }

    @Test func sessionCountsWhereItsSnapshotIsNotWhereItStarted() {
        let live = [LiveSession(key: "a", cwd: "/w/docs", status: .working, name: "a")]
        let out = StatusModel.build(input([app, docs], snaps: [snap("a", "/w/app", at: 0)], live: live))
        #expect(out.projects[0].state == .live(.working, count: 1))
        #expect(out.projects[1].state == .noSessions)
    }

    @Test func missingFolderShowsOnlyMissing() {
        var i = input([app], snaps: [snap("a", "/w/app", at: 0)])
        i.existing = []
        let row = StatusModel.build(i).projects[0]
        #expect(row.state == .missing)
        #expect(row.branch == nil && row.model == nil && row.contextPct == nil)
    }

    @Test func officeFeedOverridesFallbackAndDropsEnded() {
        let live = [
            LiveSession(key: "s1", cwd: "/w/app", status: .idle, name: "x"),
            LiveSession(key: "s2", cwd: "/w/app", status: .working, name: "y"),
        ]
        let office = OfficeSnapshot(agents: [
            OfficeAgent(id: "s1", name: "x", status: .waiting, cwd: "/w/app", sessionId: "s1"),
            OfficeAgent(id: "s2", name: "y", status: .ended, cwd: "/w/app", sessionId: "s2"),
        ])
        let sessions = StatusModel.liveSessions(fallback: live, office: office)
        #expect(sessions.map(\.key) == ["s1"])
        #expect(sessions[0].status == .waiting)
    }

    @Test func headlessOfficeAgentWithoutSnapshotStillShowsModel() {
        let office = OfficeSnapshot(agents: [
            OfficeAgent(id: "w1", name: "office-1", owner: "office", status: .working, cwd: "/w/docs", model: "claude-opus-5-5"),
        ])
        let row = StatusModel.build(input([docs], office: office)).projects[0]
        #expect(row.state == .live(.working, count: 1))
        #expect(row.model == "Opus 5.5")
        #expect(row.contextPct == nil)
    }

    @Test func usageFromNewestSnapshotWithLimits() {
        let out = StatusModel.build(input([], snaps: [
            snap("a", "/elsewhere", at: 0, five: 30, seven: 10),
            snap("b", "/elsewhere", at: 100, five: 42, seven: 18),
            snap("c", "/elsewhere", at: 200),
        ], live: [
            LiveSession(key: "a", cwd: "/x", status: .working, name: "a"),
            LiveSession(key: "c", cwd: "/x", status: .idle, name: "c"),
        ]))
        #expect(out.usage.fiveHourPct == 42)
        #expect(out.usage.sevenDayPct == 18)
        #expect(out.usage.asOf == t0.addingTimeInterval(100))
        #expect(out.usage.workingCount == 1)
    }

    @Test func noUsageData() {
        let out = StatusModel.build(input([app]))
        #expect(out.usage.fiveHourPct == nil && out.usage.asOf == nil)
    }

    @Test func attentionMarksRows() {
        let live = [LiveSession(key: "a", cwd: "/w/app", status: .idle, name: "a")]
        let out = StatusModel.build(input([app, docs], live: live, attention: ["a"]))
        #expect(out.projects[0].needsAttention)
        #expect(!out.projects[1].needsAttention)
    }

    @Test func officeRowsOnlyOfficeOwnedNotEndedSorted() {
        let office = OfficeSnapshot(agents: [
            OfficeAgent(id: "2", name: "office-b", owner: "office", status: .working, cwd: "/w/app", repoName: "app", branch: "main", task: "fix login"),
            OfficeAgent(id: "1", name: "office-a", owner: "office", status: .waiting, cwd: "/Users/me", waitingSince: t0),
            OfficeAgent(id: "3", name: "office-c", owner: "office", status: .ended, cwd: "/w/app"),
            OfficeAgent(id: "4", name: "term", owner: "external", status: .working, cwd: "/w/app"),
        ], claudeHindered: true)
        let out = StatusModel.build(input([], office: office))
        #expect(out.office?.map(\.name) == ["office-a", "office-b"])
        #expect(out.office?[0].place == "me")
        #expect(out.office?[0].since == t0)
        #expect(out.office?[1].place == "app")
        #expect(out.office?[1].detail == "fix login")
        #expect(out.claudeHindered)
        #expect(StatusModel.build(input([])).office == nil)
    }

    /// "idle 3h" is how long Cat Office has seen nothing from the session (its updatedAt), not how long ClaudeBar has
    /// watched it: ClaudeBar's own clock restarts on every reconnect. Working keeps ClaudeBar's clock (Cat Office has
    /// none for it); waiting keeps waitingSince.
    @Test func idleTimesComeFromCatOfficesLastActivity() throws {
        let quiet = t0.addingTimeInterval(-3 * 3600), watched = t0.addingTimeInterval(-60)
        var idle = OfficeAgent(id: "1", name: "office-a", owner: "office", status: .idle, cwd: "/w/app")
        idle.updatedAt = quiet
        var working = OfficeAgent(id: "2", name: "office-b", owner: "office", status: .working, cwd: "/w/app")
        working.updatedAt = quiet
        let noTime = OfficeAgent(id: "3", name: "office-c", owner: "office", status: .idle, cwd: "/w/app")
        #expect(idle.statusSince(tracked: watched) == quiet)
        #expect(working.statusSince(tracked: watched) == watched)
        #expect(noTime.statusSince(tracked: watched) == watched, "an older Cat Office without updatedAt")
        var since = input([], office: OfficeSnapshot(agents: [idle, working]))
        since.statusSince = ["1": watched, "2": watched]
        let rows = try #require(StatusModel.build(since).office)
        #expect(rows.first { $0.name == "office-a" }?.since == quiet)
        #expect(rows.first { $0.name == "office-b" }?.since == watched)
        let decoded = try JSONDecoder().decode(OfficeAgent.self, from: Data(#"{"id":"x","status":"idle","updatedAt":1800000000000}"#.utf8))
        #expect(decoded.updatedAt == Date(timeIntervalSince1970: 1_800_000_000))
    }

    /// The office list has room for longer titles than the name tags.
    @Test func officeListShowsLongerTitles() throws {
        var a = OfficeAgent(id: "1", name: "office-a", owner: "office", status: .idle, cwd: "/w/app",
                            task: "Fix the bug in Build a cat where the preview stays blank")
        a.titleSource = "ai"
        let row = try #require(StatusModel.build(input([], office: OfficeSnapshot(agents: [a]))).office?.first)
        #expect(row.label.count > a.label.count)
        #expect(row.label.hasPrefix("Fix the bug in Build a cat where"))
    }

    @Test func trackedSessionsPreferOfficeAndKeepEnded() {
        let tracked = StatusModel.trackedSessions(
            fallback: [LiveSession(key: "s1", cwd: "/", status: .idle, name: "x"), LiveSession(key: "t", cwd: "/", status: .working, name: "t")],
            office: OfficeSnapshot(agents: [OfficeAgent(id: "s1", name: "x", owner: "office", status: .ended, cwd: "/", task: "t1", sessionId: "s1")]))
        #expect(tracked.map(\.key) == ["s1", "t"])
        #expect(tracked[0].status == .ended && tracked[0].isOffice && tracked[0].task == "t1")
    }

    @Test func officeAgentCountsUnderItsCatOfficeProject() {
        let office = OfficeSnapshot(agents: [
            OfficeAgent(id: "w1", name: "office-1", owner: "office", status: .working, cwd: "/Users/me",
                        repoName: "app", repoRoot: "/w/app", model: "claude-opus-5-5"),
            OfficeAgent(id: "w2", name: "office-2", owner: "office", status: .idle, cwd: "/w/docs"),
        ])
        let out = StatusModel.build(input([app, docs], office: office))
        #expect(out.projects[0].state == .live(.working, count: 1))
        #expect(out.projects[0].model == "Opus 5.5")
        #expect(out.projects[1].state == .live(.idle, count: 1), "no project: falls back to where it started")
    }

    @Test func snapshotFolderStillBeatsCatOfficeProject() {
        let office = OfficeSnapshot(agents: [
            OfficeAgent(id: "s1", name: "term", status: .working, cwd: "/Users/me", repoRoot: "/w/app", sessionId: "s1"),
        ])
        let out = StatusModel.build(input([app, docs], snaps: [snap("s1", "/w/docs", at: 0)], office: office))
        #expect(out.projects[1].state == .live(.working, count: 1))
        #expect(out.projects[0].state == .noSessions)
    }
}

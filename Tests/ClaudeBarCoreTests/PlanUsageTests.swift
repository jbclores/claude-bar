import Foundation
import Testing
@testable import ClaudeBarCore

@Suite struct PlanUsageTests {
    let now = Date(timeIntervalSince1970: 1_791_266_000)

    @Test func readsStatusLineAndWorkerFormats() throws {
        let file = makeTempDir().appendingPathComponent("plan-usage.json")
        write(#"{"at":1791265900000,"session_id":"s","source":"office-worker","rate_limits":{"five_hour":{"used_percentage":25,"resets_at":1791285000},"seven_day":{"used_percentage":5.5,"resets_at":"2026-10-12T00:00:00Z"}}}"#, to: file)
        let plan = try #require(PlanUsageReader(file: file).read(now: now))
        #expect(plan.fiveHourPct == 25 && plan.sevenDayPct == 5.5)
        #expect(plan.fiveHourResetsAt == Date(timeIntervalSince1970: 1_791_285_000))
        #expect(plan.sevenDayResetsAt == ISO8601DateFormatter().date(from: "2026-10-12T00:00:00Z"))
        #expect(plan.asOf == Date(timeIntervalSince1970: 1_791_265_900))
    }

    @Test func dropsWindowsThatHaveReset() throws {
        let file = makeTempDir().appendingPathComponent("plan-usage.json")
        write(#"{"at":1791200000000,"rate_limits":{"five_hour":{"used_percentage":80,"resets_at":1791210000},"seven_day":{"used_percentage":30,"resets_at":1791500000}}}"#, to: file)
        let plan = try #require(PlanUsageReader(file: file).read(now: now))
        #expect(plan.fiveHourPct == nil)
        #expect(plan.sevenDayPct == 30)
    }

    @Test func missingOrBadFile() {
        let dir = makeTempDir()
        #expect(PlanUsageReader(file: dir.appendingPathComponent("none.json")).read(now: now) == nil)
        write("nope", to: dir.appendingPathComponent("bad.json"))
        #expect(PlanUsageReader(file: dir.appendingPathComponent("bad.json")).read(now: now) == nil)
    }

    @Test func usageTakesTheNewestReading() {
        let older = Snapshot(sessionId: "a", cwd: "/x", fiveHourPct: 10, sevenDayPct: 2, updatedAt: now.addingTimeInterval(-600))
        let plan = UsageSummary(fiveHourPct: 25, sevenDayPct: 5, asOf: now.addingTimeInterval(-60), workingCount: 0)
        var input = StatusInput(projects: [], snapshots: [older])
        input.planUsage = plan
        #expect(StatusModel.build(input).usage.fiveHourPct == 25)
        let newer = Snapshot(sessionId: "b", cwd: "/x", fiveHourPct: 30, sevenDayPct: 6, updatedAt: now)
        input.snapshots.append(newer)
        let usage = StatusModel.build(input).usage
        #expect(usage.fiveHourPct == 30 && usage.asOf == now)
        input.snapshots = []
        #expect(StatusModel.build(input).usage.sevenDayPct == 5)
    }
}

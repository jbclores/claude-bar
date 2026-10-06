import Foundation
import Testing
@testable import ClaudeBarCore

@Suite struct AttentionTrackerTests {
    let t = Date(timeIntervalSince1970: 1_791_266_000)

    func s(_ key: String, _ status: AgentStatus, office: Bool = true) -> TrackedSession {
        TrackedSession(key: key, name: "cat-\(key)", status: status, isOffice: office, task: "task \(key)")
    }

    @Test func firstPollIsQuietButWaitingCounts() {
        var tracker = AttentionTracker()
        let events = tracker.update([s("a", .idle), s("b", .waiting), s("c", .working)], now: t)
        #expect(events.isEmpty)
        #expect(tracker.attention == ["b"])
        #expect(tracker.since["a"] == t)
    }

    @Test func officeFinishingNeedsAttentionAndNotifies() {
        var tracker = AttentionTracker()
        _ = tracker.update([s("a", .working), s("t", .working, office: false)], now: t)
        let events = tracker.update([s("a", .idle), s("t", .idle, office: false)], now: t + 10)
        #expect(events == [FinishedEvent(key: "a", name: "cat-a", task: "task a")])
        #expect(tracker.attention == ["a"])
        #expect(tracker.since["a"] == t + 10)
    }

    @Test func endedOfficeAgentNotifiesWithoutAttention() {
        var tracker = AttentionTracker()
        _ = tracker.update([s("a", .working)], now: t)
        let events = tracker.update([s("a", .ended)], now: t + 1)
        #expect(events.count == 1)
        #expect(tracker.attention.isEmpty)
    }

    @Test func acknowledgeClearsUntilNextChange() {
        var tracker = AttentionTracker()
        _ = tracker.update([s("a", .working), s("w", .waiting)], now: t)
        _ = tracker.update([s("a", .idle), s("w", .waiting)], now: t + 1)
        #expect(tracker.attention == ["a", "w"])
        tracker.acknowledge()
        #expect(tracker.attention.isEmpty)
        _ = tracker.update([s("a", .idle), s("w", .waiting)], now: t + 2)
        #expect(tracker.attention.isEmpty)
        _ = tracker.update([s("a", .working), s("w", .working)], now: t + 3)
        _ = tracker.update([s("a", .idle), s("w", .waiting)], now: t + 4)
        #expect(tracker.attention == ["a", "w"])
    }

    @Test func startingWorkClearsAttention() {
        var tracker = AttentionTracker()
        _ = tracker.update([s("a", .working)], now: t)
        _ = tracker.update([s("a", .idle)], now: t + 1)
        _ = tracker.update([s("a", .working)], now: t + 2)
        #expect(tracker.attention.isEmpty)
    }

    @Test func goneSessionsAreForgotten() {
        var tracker = AttentionTracker()
        _ = tracker.update([s("w", .waiting)], now: t)
        _ = tracker.update([], now: t + 1)
        #expect(tracker.attention.isEmpty && tracker.since.isEmpty)
    }
}

import Foundation
import Testing
@testable import ClaudeBarCore

@Suite struct CatSoundsTests {
    let t0 = Date(timeIntervalSince1970: 1_791_300_000)
    let all = SoundSettings(needsYou: true, finished: true, click: true, elevator: true, volume: 0.6)

    @Test func eachEventHasItsSound() {
        var g = SoundGate()
        #expect(g.sound(for: .needsYou("a"), settings: all, now: t0) == .meow)
        #expect(g.sound(for: .finished("b"), settings: all, now: t0 + 10) == .purr)
        #expect(g.sound(for: .clicked, settings: all, now: t0 + 20) == .meow)
        #expect(g.sound(for: .elevator, settings: all, now: t0 + 30) == .ding)
    }

    @Test func switchedOffSoundsStaySilent() {
        var g = SoundGate()
        let none = SoundSettings(needsYou: false, finished: false, click: false, elevator: false, volume: 0.6)
        for e in [SoundEvent.needsYou("a"), .finished("a"), .clicked, .elevator] { #expect(g.sound(for: e, settings: none, now: t0) == nil) }
    }

    @Test func atMostOneSoundEveryThreeSeconds() {
        var g = SoundGate()
        #expect(g.sound(for: .needsYou("a"), settings: all, now: t0) == .meow)
        #expect(g.sound(for: .needsYou("b"), settings: all, now: t0 + 1) == nil, "several cats at once: one sound")
        #expect(g.sound(for: .clicked, settings: all, now: t0 + 2.9) == nil)
        #expect(g.sound(for: .clicked, settings: all, now: t0 + 3) == .meow)
    }

    @Test func theSameCatDoesNotRepeatAnAlertWithinAMinute() {
        var g = SoundGate()
        #expect(g.sound(for: .needsYou("a"), settings: all, now: t0) == .meow)
        #expect(g.sound(for: .needsYou("a"), settings: all, now: t0 + 30) == nil)
        #expect(g.sound(for: .finished("a"), settings: all, now: t0 + 31) == .purr, "a different alert from the same cat")
        #expect(g.sound(for: .needsYou("a"), settings: all, now: t0 + 61) == .meow)
    }

    @Test func aSilencedEventDoesNotUseUpTheSpacing() {
        var g = SoundGate()
        var quiet = all; quiet.needsYou = false
        #expect(g.sound(for: .needsYou("a"), settings: quiet, now: t0) == nil)
        #expect(g.sound(for: .clicked, settings: all, now: t0 + 0.5) == .meow)
    }

    @Test func settingsDefaultAndParse() throws {
        #expect(SoundSettings() == SoundSettings(needsYou: true, finished: true, click: true, elevator: false, volume: 0.6))
        let c = try Config.parse(Data(#"{"projects":[],"sounds":{"elevator":true,"click":false,"volume":0.3}}"#.utf8))
        #expect(c.sounds == SoundSettings(needsYou: true, finished: true, click: false, elevator: true, volume: 0.3))
        #expect(try Config.parse(Data(#"{"projects":[]}"#.utf8)).sounds == SoundSettings())
    }

    @Test func soundSettingsAreSavedInTheConfigFile() throws {
        let file = makeTempDir().appendingPathComponent("projects.json")
        write(#"{"projects":[],"notifications":true}"#, to: file)
        let store = ConfigStore(file: file)
        store.reload()
        try store.set(0.35, at: ["sounds", "volume"])
        try store.set(true, at: ["sounds", "elevator"])
        store.reload()
        #expect(store.config.sounds.volume == 0.35 && store.config.sounds.elevator)
        #expect(store.config.notifications, "other keys kept")
    }

    @Test func trackerReportsSessionsThatJustStartedWaiting() {
        var t = AttentionTracker()
        func s(_ k: String, _ st: AgentStatus) -> TrackedSession { TrackedSession(key: k, name: k, status: st, isOffice: true) }
        _ = t.update([s("a", .waiting), s("b", .working)], now: t0)
        #expect(t.startedWaiting.isEmpty, "not on the first update (launch)")
        _ = t.update([s("a", .waiting), s("b", .waiting)], now: t0 + 5)
        #expect(t.startedWaiting == ["b"])
        _ = t.update([s("a", .waiting), s("b", .waiting)], now: t0 + 10)
        #expect(t.startedWaiting.isEmpty, "still waiting: no new start")
    }
}

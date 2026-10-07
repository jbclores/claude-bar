import Foundation
import Testing
@testable import ClaudeBarCore

@Suite struct OfficeLightingTests {
    @Test func autoFollowsTheMacOthersAreFixed() {
        #expect(OfficeLighting.auto.isNight(systemDark: true))
        #expect(!OfficeLighting.auto.isNight(systemDark: false))
        #expect(OfficeLighting.night.isNight(systemDark: false))
        #expect(!OfficeLighting.day.isNight(systemDark: true))
    }

    @Test func theQuickButtonFlipsWhatYouSee() {
        #expect(OfficeLighting.auto.toggled(systemDark: true) == .day)
        #expect(OfficeLighting.auto.toggled(systemDark: false) == .night)
        #expect(OfficeLighting.night.toggled(systemDark: true) == .day)
        #expect(OfficeLighting.day.toggled(systemDark: false) == .night)
    }

    @Test func parsesAndDefaultsToAuto() throws {
        #expect(Config.empty.officeLighting == .auto)
        #expect(try Config.parse(Data(#"{"officeLighting":"night"}"#.utf8)).officeLighting == .night)
        #expect(try Config.parse(Data(#"{"officeLighting":"disco"}"#.utf8)).officeLighting == .auto)
    }

    @Test func savesAsAStringSetting() throws {
        let file = makeTempDir().appendingPathComponent("projects.json")
        write(#"{"projects":[{"path":"/x"}]}"#, to: file)
        let store = ConfigStore(file: file)
        store.reload()
        try store.set("day", at: ["officeLighting"])
        #expect(store.config.officeLighting == .day)
        #expect(store.config.projects.count == 1)
    }
}

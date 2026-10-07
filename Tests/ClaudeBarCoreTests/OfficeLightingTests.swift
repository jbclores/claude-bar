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

    @Test func theButtonFlipsWhatYouSeeAndReturnsToFollowingTheMac() {
        // From following the Mac: the opposite, fixed.
        #expect(OfficeLighting.auto.toggled(systemDark: true) == .day)
        #expect(OfficeLighting.auto.toggled(systemDark: false) == .night)
        // Flipping back to what the Mac shows: follow the Mac again.
        #expect(OfficeLighting.day.toggled(systemDark: true) == .auto)
        #expect(OfficeLighting.night.toggled(systemDark: false) == .auto)
        // Fixed against the Mac's own theme stays fixed.
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

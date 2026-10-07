import Foundation
import Testing
@testable import ClaudeBarCore

@Suite struct OfficeMusicTests {
    let t0 = Date(timeIntervalSince1970: 1_791_300_000)

    @Test func playsWhileTheOfficeTabIsShown() {
        #expect(OfficeMusic.shouldPlay(on: true, officeTab: true, peekShownSince: nil, now: t0))
        #expect(!OfficeMusic.shouldPlay(on: true, officeTab: false, peekShownSince: nil, now: t0), "office closed, or another tab")
    }

    @Test func thePopupWaitsASecondSoPassingTheIconStaysQuiet() {
        #expect(!OfficeMusic.shouldPlay(on: true, officeTab: false, peekShownSince: t0, now: t0 + 0.5))
        #expect(OfficeMusic.shouldPlay(on: true, officeTab: false, peekShownSince: t0, now: t0 + 1.0))
    }

    @Test func theButtonTurnsItOff() {
        #expect(!OfficeMusic.shouldPlay(on: false, officeTab: true, peekShownSince: t0, now: t0 + 5))
    }

    @Test func playsAtHalfTheSoundsVolume() {
        #expect(OfficeMusic.volume(sounds: 0.6) == 0.3)
    }

    @Test func onByDefaultAndSaved() throws {
        #expect(SoundSettings().music)
        #expect(try !Config.parse(Data(#"{"projects":[],"sounds":{"music":false}}"#.utf8)).sounds.music)
    }
}

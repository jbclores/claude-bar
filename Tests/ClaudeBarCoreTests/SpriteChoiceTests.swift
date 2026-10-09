import Testing
@testable import ClaudeBarCore

/// Which picture a sprite view shows when its key changes (a cat turning): the cached picture for the new key, else
/// the one it already holds until the new one loads.
@Suite struct SpriteChoiceTests {
    @Test func aCachedPictureForTheNewKeyWinsOverTheOldOne() {
        #expect(SpriteChoice.shown(cached: "front-right", held: "front-left") == "front-right")
    }

    @Test func theHeldPictureStaysUntilTheNewOneLoads() {
        #expect(SpriteChoice.shown(cached: nil as String?, held: "front-left") == "front-left")
        #expect(SpriteChoice.shown(cached: nil as String?, held: nil as String?) == nil)
    }
}

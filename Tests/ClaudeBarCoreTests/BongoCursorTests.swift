import Testing
@testable import ClaudeBarCore

@Suite struct BongoCursorTests {
    @Test func pawsDownWhileOnlyHovering() {
        #expect(BongoCursor.frame(heldFor: nil, reduceMotion: false) == .rest)
        #expect(BongoCursor.frame(heldFor: nil, reduceMotion: true) == .rest)
    }

    @Test func slapsLeftThenRightEvery150msWhileHeld() {
        #expect(BongoCursor.frame(heldFor: 0, reduceMotion: false) == .left)
        #expect(BongoCursor.frame(heldFor: 0.149, reduceMotion: false) == .left)
        #expect(BongoCursor.frame(heldFor: 0.15, reduceMotion: false) == .right)
        #expect(BongoCursor.frame(heldFor: 0.31, reduceMotion: false) == .left)
        #expect(BongoCursor.frame(heldFor: 0.46, reduceMotion: false) == .right)
    }

    @Test func reduceMotionSlapsOnceWithoutLooping() {
        for t in [0, 0.15, 0.3, 2.0] { #expect(BongoCursor.frame(heldFor: t, reduceMotion: true) == .left) }
    }

    @Test func artComesFromCatOfficesOwnFolder() {
        #expect(BongoCursor.path(.rest) == "assets/cursors/bongo-cat/rest.png")
        #expect(BongoCursor.path(.left) == "assets/cursors/bongo-cat/slap-left.png")
        #expect(BongoCursor.path(.right) == "assets/cursors/bongo-cat/slap-right.png")
    }
}

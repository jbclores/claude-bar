import CoreGraphics
import Testing
@testable import ClaudeBarCore

@Suite struct NameTagsTests {
    let room = CGRect(x: 0, y: 0, width: 400, height: 200)
    func tag(_ x: CGFloat, _ y: CGFloat, w: CGFloat = 60) -> CGRect { CGRect(x: x, y: y, width: w, height: 14) }

    @Test func everyTagIsPlacedAndNoneOverlap() {
        // Five cats bunched together, as at a busy desk.
        let wanted = ["a": tag(100, 100), "b": tag(110, 102), "c": tag(105, 98), "d": tag(120, 100), "e": tag(100, 104)]
        let placed = NameTags.layout(wanted, avoid: [], priority: [], in: room)
        #expect(Set(placed.keys) == Set(wanted.keys), "every cat keeps a tag")
        let rects = Array(placed.values)
        for i in rects.indices { for j in rects.indices where i < j { #expect(!rects[i].intersects(rects[j])) } }
        for r in rects { #expect(room.contains(r)) }
        // Each stays close to its cat: within 3 tag heights down/up and about one tag width sideways.
        for (k, r) in placed {
            let w = wanted[k]!
            #expect(abs(r.minY - w.minY) <= 3 * (w.height + 1) + 0.01 && abs(r.minX - w.minX) <= 1.1 * w.width + 0.01)
        }
    }

    @Test func aCatThatNeedsYouKeepsItsSpot() {
        let wanted = ["a": tag(100, 100), "z": tag(100, 100)]
        let placed = NameTags.layout(wanted, avoid: [], priority: ["z"], in: room)
        #expect(placed["z"] == wanted["z"])
        #expect(placed["a"] != wanted["a"])
    }

    @Test func tagsStepAroundNotesAndStayInTheRoom() {
        let note = tag(100, 186, w: 40)
        let placed = NameTags.layout(["a": tag(100, 186)], avoid: [note], in: room)
        let r = placed["a"]!
        #expect(!r.intersects(note) && room.contains(r))
    }

    @Test func nowhereFreeKeepsThePreferredSpot() {
        // A room only as tall as one tag, already taken: the tag still shows, where it wanted to be.
        let tiny = CGRect(x: 0, y: 0, width: 100, height: 14)
        let placed = NameTags.layout(["a": tag(0, 0), "b": tag(0, 0)], avoid: [], priority: ["a"], in: tiny)
        #expect(placed["a"] == tag(0, 0) && placed["b"] == tag(0, 0))
    }

    @Test func longNamesAreCutWithAnEllipsis() {
        #expect(NameTags.text("claude-bar") == "claude-bar")
        #expect(NameTags.text("pnp-ufdms-base-admin") == "pnp-ufdms-bas…")
        #expect(NameTags.text("Create me a status line") == "Create me a s…")
        #expect(NameTags.text("pnp-ufdms-base-admin").count == 14)
    }

    @Test func aTagPartlyOutsideTheViewMovesIn() {
        let placed = NameTags.layout(["a": tag(380, 100)], avoid: [], in: room)   // 60 wide at x 380: sticks out
        #expect(room.contains(placed["a"]!))
    }

    @Test func theNearestFreeSpotWins() {
        // One tag in the way: the next tag moves one step, not further.
        let placed = NameTags.layout(["b": tag(100, 100)], avoid: [tag(100, 100)], in: room)
        let r = placed["b"]!
        #expect(abs(r.minY - 100) + abs(r.minX - 100) <= 15.01)
    }

    @Test func aCrowdAtTheEdgeStillGetsApart() {
        // Six cats piled at the bottom-left corner of the room (a full sofa): nobody overlaps.
        let wanted = Dictionary(uniqueKeysWithValues: (0..<6).map { ("c\($0)", tag(CGFloat(4 + 6 * $0), 180)) })
        let placed = NameTags.layout(wanted, avoid: [], in: room)
        let rects = Array(placed.values)
        for i in rects.indices { for j in rects.indices where i < j { #expect(!rects[i].intersects(rects[j])) } }
        for r in rects { #expect(room.contains(r)) }
    }
}

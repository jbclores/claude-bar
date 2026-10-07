import Foundation

/// Cat Office's room cursor (canvas-zoom.css): Bongo Cat with both paws down over the room; while the mouse button
/// is held the cat slaps, left and right every 150 ms (one slap, no loop, with Reduce Motion). The art is read from
/// each Cat Office's own assets (personal-use art: see its assets/cursors/bongo-cat/README.md), never bundled.
public enum BongoCursor {
    public enum Frame: Sendable, CaseIterable { case rest, left, right }

    public static let slap: TimeInterval = 0.15

    public static func frame(heldFor: TimeInterval?, reduceMotion: Bool) -> Frame {
        guard let held = heldFor else { return .rest }
        if reduceMotion { return .left }
        return Int((held / slap).rounded(.down)) % 2 == 0 ? .left : .right
    }

    public static func path(_ frame: Frame) -> String {
        switch frame {
        case .rest: "assets/cursors/bongo-cat/rest.png"
        case .left: "assets/cursors/bongo-cat/slap-left.png"
        case .right: "assets/cursors/bongo-cat/slap-right.png"
        }
    }
}

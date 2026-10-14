import CoreGraphics
import Foundation

/// Every cat's name tag, placed so none overlap: each tag takes the nearest free spot to the one under its cat (up to 3
/// tag heights up or down and about a tag's width sideways; in a crowd, twice that), clear of the tags already placed and of `avoid` (the "+N"
/// notes), inside the visible room. Cats that need you are placed first, so they keep their spot. Rects are in view points after zoom.
public enum NameTags {
    /// The longest tag text, in characters, "…" included.
    public static let maxLength = 14
    /// How far a tag may move: up to 3 tag heights up or down, and up to about one tag width sideways.
    static let maxSteps = 3

    /// Spots around `home`, nearest first: a step down or up costs less than a slide sideways (a tag reads best right
    /// under its cat).
    static func candidates(around home: CGRect, steps: Int, widths: [CGFloat], step: CGFloat) -> [CGRect] {
        func cost(_ r: CGRect) -> CGFloat { hypot(r.minX - home.minX, (r.minY - home.minY) * 1.5) }
        let dys = (-steps...steps).map { CGFloat($0) * step }
        let spots: [CGRect] = dys.flatMap { dy -> [CGRect] in widths.map { home.offsetBy(dx: $0 * home.width, dy: dy) } }
        return spots.sorted { cost($0) < cost($1) }
    }

    /// A name cut to `maxLength` with "…".
    public static func text(_ name: String) -> String {
        name.count <= maxLength ? name : String(name.prefix(maxLength - 1)) + "…"
    }

    /// The cat is mostly out of view (less than half of it inside `visible`): no tag for it, so no tag hangs where no
    /// cat shows (a cat at the back wall of a deep floor, cut off at the top).
    public static func isMostlyHidden(figure: CGRect, visible: CGRect) -> Bool {
        guard figure.width > 0, figure.height > 0 else { return true }
        let shown = figure.intersection(visible)
        guard !shown.isNull else { return true }
        return shown.width * shown.height < figure.width * figure.height / 2
    }

    public static func layout(_ wanted: [String: CGRect], avoid: [CGRect], priority: Set<String> = [], in room: CGRect) -> [String: CGRect] {
        let order = wanted.keys.sorted { a, b in
            let pa = priority.contains(a), pb = priority.contains(b)
            return pa != pb ? pa : a < b
        }
        var taken = avoid
        var out: [String: CGRect] = [:]
        for key in order {
            guard let want = wanted[key] else { continue }
            let step = want.height + 1
            // Inside the view first: a tag under a cat at the edge slides in.
            let home = want.offsetBy(dx: min(max(0, room.minX - want.minX), room.maxX - want.maxX),
                                     dy: min(max(0, room.minY - want.minY), room.maxY - want.maxY))
            // The nearest free spot: straight down or up first, then a little to the side; in a crowd (a sofa full of
            // cats), a wider ring before giving up.
            let near = candidates(around: home, steps: maxSteps, widths: [0, -0.6, 0.6, -1.1, 1.1], step: step)
            let wide = candidates(around: home, steps: 2 * maxSteps, widths: [0, -0.6, 0.6, -1.1, 1.1, -1.6, 1.6, -2.2, 2.2], step: step)
            let free = { (r: CGRect) in room.contains(r) && !taken.contains(where: { $0.intersects(r) }) }
            let spot = near.first(where: free) ?? wide.first(where: free)
            // Nowhere free: keep the tag where it wanted to be (inside the view) rather than lose it.
            let placed = spot ?? home
            out[key] = placed
            taken.append(placed)
        }
        return out
    }
}

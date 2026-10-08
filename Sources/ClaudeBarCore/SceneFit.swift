import CoreGraphics
import Foundation

/// World px onto a view's points: a uniform scale and an origin (view #2: the floor fills the width with a 20 world-px
/// margin each side, centred across; the room's content centred down).
public struct SceneFit: Equatable, Sendable {
    /// Points per world px.
    public let scale: CGFloat
    /// Where world (0, 0) lands, in points.
    public let origin: CGPoint

    public init(scale: CGFloat, origin: CGPoint) {
        self.scale = scale
        self.origin = origin
    }

    public func point(_ p: WorldPoint) -> CGPoint {
        CGPoint(x: origin.x + CGFloat(p.x) * scale, y: origin.y + CGFloat(p.y) * scale)
    }

    /// The world point under a view point: the inverse of `point(_:)`.
    public func world(_ p: CGPoint) -> WorldPoint {
        WorldPoint(x: Double((p.x - origin.x) / scale), y: Double((p.y - origin.y) / scale))
    }

    /// A world rect in points.
    public func rect(_ r: CGRect) -> CGRect {
        CGRect(x: origin.x + r.minX * scale, y: origin.y + r.minY * scale, width: r.width * scale, height: r.height * scale)
    }

    /// View #2: the floor fills the width (20 world px margin each side), centred across. Down, the room's content
    /// (BuiltRoom.contentBounds) is centred; content taller than the view keeps its top and loses its front, but never
    /// so far that `keep` (BuiltRoom.catBounds: where cats stand) leaves the view. A `keep` taller than the view at
    /// that scale shrinks the floor until it fits, `keep` centred down and the floor across.
    public static func fill(floor: FloorFrame, content: CGRect, keep: CGRect? = nil, into size: CGSize) -> SceneFit {
        let c = floor.corners
        let fillWidth = size.width / CGFloat(c.right.x - c.left.x + 40)
        let midX = CGFloat(c.left.x + c.right.x) / 2
        // Cats' band taller than the view at that scale: shrink until it fits, centred down (margins at the sides).
        if let keep, keep.height > 0, keep.height * fillWidth > size.height {
            let scale = min(fillWidth, size.height / keep.height)
            return SceneFit(scale: scale, origin: CGPoint(x: size.width / 2 - midX * scale, y: size.height / 2 - keep.midY * scale))
        }
        let scale = fillWidth
        var y = content.height * scale <= size.height
            ? size.height / 2 - content.midY * scale
            : -content.minY * scale
        if let keep, keep.height * scale <= size.height {
            // keep.maxY lands at or above the bottom, keep.minY at or below the top.
            y = min(y, size.height - keep.maxY * scale)
            y = max(y, -keep.minY * scale)
        }
        return SceneFit(scale: scale, origin: CGPoint(x: size.width / 2 - midX * scale, y: y))
    }
}

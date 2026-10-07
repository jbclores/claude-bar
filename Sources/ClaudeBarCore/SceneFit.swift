import CoreGraphics
import Foundation

/// World px onto a view's points: a uniform scale and an origin (view #2: the floor fills the width with a 20 world-px
/// margin each side, centred across; the floor parallelogram's middle centred down, walls and front trimmed).
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

    /// A world rect in points.
    public func rect(_ r: CGRect) -> CGRect {
        CGRect(x: origin.x + r.minX * scale, y: origin.y + r.minY * scale, width: r.width * scale, height: r.height * scale)
    }

    public static func fill(floor: FloorFrame, into size: CGSize) -> SceneFit {
        let c = floor.corners
        let scale = size.width / CGFloat(c.right.x - c.left.x + 40)
        let midX = CGFloat(c.left.x + c.right.x) / 2
        let midY = CGFloat(c.top.y + c.bottom.y) / 2
        return SceneFit(scale: scale, origin: CGPoint(x: size.width / 2 - midX * scale, y: size.height / 2 - midY * scale))
    }
}

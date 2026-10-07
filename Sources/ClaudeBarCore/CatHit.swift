import CoreGraphics
import Foundation

/// A cat as the pointer finds it: its hover frame, depth and feet (all in one view's points).
public struct CatHit: Equatable, Sendable {
    public var frame: CGRect
    /// Its drawing depth (higher is in front); 0 where a view has none.
    public var z: Int
    public var feet: CGPoint

    public init(frame: CGRect, z: Int, feet: CGPoint) {
        self.frame = frame; self.z = z; self.feet = feet
    }

    /// The cat under `point`: the frontmost (highest z), then the one whose feet are nearest the pointer, then the
    /// first id. nil when no frame holds the point.
    public static func frontmost(_ hits: [String: CatHit], at point: CGPoint) -> String? {
        func distance(_ h: CatHit) -> CGFloat { hypot(h.feet.x - point.x, h.feet.y - point.y) }
        return hits.filter { $0.value.frame.contains(point) }
            .min { a, b in
                if a.value.z != b.value.z { return a.value.z > b.value.z }
                let da = distance(a.value), db = distance(b.value)
                if da != db { return da < db }
                return a.key < b.key
            }?.key
    }
}

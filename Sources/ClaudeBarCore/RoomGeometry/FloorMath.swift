import CoreGraphics
import Foundation

/// A floor's parallelogram and its axes, ported from Cat Office's floor-math.ts, RoomShell.tsx, room.ts and occlusion.ts.
public struct FloorFrame: Equatable, Sendable {
    public let corners: FloorCorners
    /// Screen length in world px of the floor's u axis and v axis (desks.ts floorAxes).
    public let eu: Double
    public let ev: Double

    /// nil when the parallelogram's area is under 1 px².
    public init?(corners: FloorCorners) {
        let ax = corners.left.x - corners.top.x, ay = corners.left.y - corners.top.y
        let bx = corners.right.x - corners.top.x, by = corners.right.y - corners.top.y
        guard abs(ax * by - ay * bx) >= 1 else { return nil }
        self.corners = corners
        self.eu = hypot(ax, ay)
        self.ev = hypot(bx, by)
    }

    /// floor-math.ts uvToPx.
    public func px(_ p: FloorPoint) -> WorldPoint {
        let top = corners.top, left = corners.left, right = corners.right
        return WorldPoint(
            x: top.x + p.u * (left.x - top.x) + p.v * (right.x - top.x),
            y: top.y + p.u * (left.y - top.y) + p.v * (right.y - top.y))
    }

    /// floor-math.ts pxToUv.
    public func uv(_ p: WorldPoint) -> FloorPoint {
        let top = corners.top, left = corners.left, right = corners.right
        let ax = left.x - top.x, ay = left.y - top.y
        let bx = right.x - top.x, by = right.y - top.y
        let det = ax * by - ay * bx
        let dx = p.x - top.x, dy = p.y - top.y
        return FloorPoint(u: (dx * by - dy * bx) / det, v: (ax * dy - ay * dx) / det)
    }

    /// RoomShell.tsx floorPlane: local px (x along v, y along u) onto the floor parallelogram.
    public var plane: (size: Double, transform: CGAffineTransform) {
        let top = corners.top, left = corners.left, right = corners.right
        let size = (eu + ev) / 2
        return (size, CGAffineTransform(
            a: (right.x - top.x) / size, b: (right.y - top.y) / size,
            c: (left.x - top.x) / size, d: (left.y - top.y) / size,
            tx: top.x, ty: top.y))
    }

    /// A wall's base line from its back corner to its front end (room.ts wallBase).
    private func base(_ side: WallSide) -> (from: WorldPoint, to: WorldPoint) {
        (corners.top, side == .left ? corners.left : corners.right)
    }

    /// RoomShell.tsx wallFrame, with room.ts wallLength: the transform for the length x height box.
    public func wall(_ side: WallSide, height: Double) -> (length: Double, transform: CGAffineTransform) {
        let (from, to) = base(side)
        let length = hypot(to.x - from.x, to.y - from.y)
        let start = side == .left ? to : from
        let end = side == .left ? from : to
        return (length, CGAffineTransform(
            a: (end.x - start.x) / length, b: (end.y - start.y) / length, c: 0, d: 1,
            tx: start.x, ty: start.y - height))
    }

    /// room.ts wallPoint: `at` along the wall (0 = back corner), `up` world px above the floor.
    public func wallPoint(_ side: WallSide, at: Double, up: Double) -> WorldPoint {
        let (from, to) = base(side)
        return WorldPoint(x: from.x + (to.x - from.x) * at, y: from.y + (to.y - from.y) * at - up)
    }

    /// room.ts outUnit: floor units per world px going out from a wall.
    public func outUnit(_ side: WallSide) -> Double {
        1 / (side == .left ? ev : eu)
    }

    /// occlusion.ts depthZ: `10 + Math.round(depth * 10000)`, rounding half up like JS.
    public static func depthZ(_ uv: Double) -> Int {
        10 + Int((uv * 10000 + 0.5).rounded(.down))
    }

    /// room.ts wallFloorPoint.
    public static func wallFloorPoint(_ side: WallSide, at: Double, out: Double) -> FloorPoint {
        side == .left ? FloorPoint(u: at, v: out) : FloorPoint(u: out, v: at)
    }
}

/// A footprint on the floor in floor units (desks.ts Footprint).
public struct Footprint: Equatable, Sendable {
    public var u0: Double, u1: Double, v0: Double, v1: Double
    public init(u0: Double, u1: Double, v0: Double, v1: Double) {
        self.u0 = u0; self.u1 = u1; self.v0 = v0; self.v1 = v1
    }
}

/// Something drawn in the cats' layer that covers cats behind it (occlusion.ts OccluderBox).
public struct OccluderBox: Equatable, Sendable {
    public var front: FloorPoint
    public var rect: CGRect
    public var back: Double?
    public var z: Int
    /// What the box belongs to (a wall item's or prop's placement id), for cats perching on it. Not in Cat Office's box.
    public var id: String? = nil

    /// occlusion.ts occluderBox: z from the front ground corner's depth (u + v).
    public static func make(front: FloorPoint, rect: CGRect, back: Double?, id: String? = nil) -> OccluderBox {
        OccluderBox(front: front, rect: rect, back: back, z: FloorFrame.depthZ(front.u + front.v), id: id)
    }
}

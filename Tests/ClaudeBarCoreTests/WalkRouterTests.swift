import CoreGraphics
import Testing
@testable import ClaudeBarCore

@Suite struct WalkRouterTests {
    let frame = FloorFrame(corners: FloorCorners(top: WorldPoint(x: 0, y: 0), left: WorldPoint(x: -200, y: 100),
                                                 bottom: WorldPoint(x: 0, y: 200), right: WorldPoint(x: 200, y: 100)))!
    let fit = SceneFit(scale: 0.5, origin: CGPoint(x: 120, y: 10))

    func grid(wall: Bool) -> NavGrid {
        var open = [Bool](repeating: true, count: 100)
        if wall { for u in 4...5 { for v in 2...7 { open[u * 10 + v] = false } } }
        return NavGrid(size: 10, open: open, frame: frame)
    }
    func view(_ u: Double, _ v: Double) -> CGPoint { fit.point(frame.px(FloorPoint(u: u, v: v))) }

    @Test func fitRoundTrips() {
        let p = CGPoint(x: 77.3, y: 41.9)
        let back = fit.point(fit.world(p))
        #expect(abs(back.x - p.x) < 1e-9 && abs(back.y - p.y) < 1e-9)
    }

    @Test func routesAroundAWallAndEndsExactlyAtTheTarget() {
        let from = view(0.15, 0.45), to = view(0.85, 0.45)
        let w = WalkRouter.path(from: from, to: to, grid: grid(wall: true), frame: frame, fit: fit)
        #expect(w.points.first == from && w.points.last == to)
        #expect(w.points.count > 3, "goes round, not straight through")
    }

    @Test func noGridOrNoRouteFallsBackToTheL() {
        let from = view(0.15, 0.45), to = view(0.85, 0.45)
        #expect(WalkRouter.path(from: from, to: to, grid: nil, frame: frame, fit: fit) == WalkPath(from: from, to: to))
        var open = [Bool](repeating: true, count: 100)
        for v in 0..<10 { open[50 + v] = false }   // a full wall across u = 5: the far side is unreachable
        let cut = NavGrid(size: 10, open: open, frame: frame)
        #expect(WalkRouter.path(from: from, to: to, grid: cut, frame: frame, fit: fit) == WalkPath(from: from, to: to))
    }

    @Test func nonFiniteInputsFallBackToTheL() {
        let from = view(0.15, 0.45), to = view(0.85, 0.45)
        let g = grid(wall: false)
        // A scale of 0 makes fit.world non-finite.
        let flat = SceneFit(scale: 0, origin: fit.origin)
        #expect(WalkRouter.path(from: from, to: to, grid: g, frame: frame, fit: flat) == WalkPath(from: from, to: to))
        // A NaN start.
        let nan = CGPoint(x: CGFloat.nan, y: 5)
        let w = WalkRouter.path(from: nan, to: to, grid: g, frame: frame, fit: fit)
        #expect(w.points.last == to, "the L, not a route")
    }

    @Test func aBlockedTargetKeepsTheHopFromTheOpenFloorInFront() {
        let g = grid(wall: true)
        let from = view(0.15, 0.45), to = view(0.45, 0.25)   // a seat inside the wall
        let w = WalkRouter.path(from: from, to: to, grid: g, frame: frame, fit: fit)
        #expect(w.points.first == from && w.points.last == to)
        let before = w.points[w.points.count - 2]
        #expect(g.isOpenAt(frame.uv(fit.world(before))), "the hop starts on open floor")
        let hop = CGPoint(x: to.x - before.x, y: to.y - before.y)
        let o = frame.px(FloorPoint(u: 0, v: 0))
        let uAxis = frame.px(FloorPoint(u: 1, v: 0)), vAxis = frame.px(FloorPoint(u: 0, v: 1))
        func cross(_ a: CGPoint, _ b: CGPoint) -> CGFloat { a.x * b.y - a.y * b.x }
        let u = CGPoint(x: uAxis.x - o.x, y: uAxis.y - o.y), v = CGPoint(x: vAxis.x - o.x, y: vAxis.y - o.y)
        #expect(abs(cross(hop, u)) < 1e-6 || abs(cross(hop, v)) < 1e-6, "the last leg runs along u or v")
    }
    /// A seat in cell (4,4) with its four axis neighbours blocked and its diagonals open: NavGrid's approach falls back
    /// to the nearest open cell's centre, off both axes of the seat, so the last hop needs an L, not a diagonal.
    @Test func aFallbackApproachEndsWithAnLNotADiagonal() {
        var open = [Bool](repeating: true, count: 100)
        for (u, v) in [(4, 4), (3, 4), (5, 4), (4, 3), (4, 5)] { open[u * 10 + v] = false }
        let g = NavGrid(size: 10, open: open, frame: frame)
        let from = view(0.15, 0.15), to = view(0.45, 0.45)
        let w = WalkRouter.path(from: from, to: to, grid: g, frame: frame, fit: fit)
        #expect(w.points.first == from && w.points.last == to)
        #expect(w.points.count > 2, "a route, not the L fallback")
        let uv = w.points.map { frame.uv(fit.world($0)) }
        for (a, b) in zip(uv, uv.dropFirst()) {
            #expect(abs(b.u - a.u) < 1e-6 || abs(b.v - a.v) < 1e-6, "leg \(a) -> \(b) runs along u or v")
        }
    }
}

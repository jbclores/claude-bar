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
}

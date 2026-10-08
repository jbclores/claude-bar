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

    /// A raised seat: floor point F on a blocked cell (4,4), drawn lifted by `lift` world px (SceneCats' feet).
    func raisedSeat() -> (grid: NavGrid, floor: FloorPoint, ground: CGPoint, lifted: CGPoint) {
        var open = [Bool](repeating: true, count: 100)
        open[4 * 10 + 4] = false
        let g = NavGrid(size: 10, open: open, frame: frame)
        let f = FloorPoint(u: 0.45, v: 0.45), lift: CGFloat = 30
        let ground = view(f.u, f.v)
        return (g, f, ground, CGPoint(x: ground.x, y: ground.y - lift * fit.scale))
    }

    /// Samples of the leg a → b (view points) that fall on blocked cells.
    func blockedSamples(_ g: NavGrid, _ a: CGPoint, _ b: CGPoint) -> Int {
        let ua = frame.uv(fit.world(a)), ub = frame.uv(fit.world(b))
        return (1..<20).filter { t in
            let f = Double(t) / 20
            return !g.isOpenAt(FloorPoint(u: ua.u + (ub.u - ua.u) * f, v: ua.v + (ub.v - ua.v) * f))
        }.count
    }

    func alongAnAxis(_ a: CGPoint, _ b: CGPoint) -> Bool {
        let ua = frame.uv(fit.world(a)), ub = frame.uv(fit.world(b))
        return abs(ub.u - ua.u) < 1e-6 || abs(ub.v - ua.v) < 1e-6
    }

    /// A walk to a raised seat routes to the seat's floor point (not to the lifted feet taken as floor), steps under
    /// it from the open floor in front, and hops straight up onto the lifted feet.
    @Test func aRaisedTargetRoutesToItsFloorPointThenHopsStraightUp() {
        let (g, f, ground, lifted) = raisedSeat()
        let from = view(0.15, 0.15)
        let w = WalkRouter.path(from: from, to: lifted, toFloor: f, grid: g, frame: frame, fit: fit)
        let p = w.points
        #expect(p.count >= 4, "a route, not the L")
        #expect(p.first == from && p.last == lifted)
        let under = p[p.count - 2]
        #expect(abs(under.x - ground.x) < 1e-6 && abs(under.y - ground.y) < 1e-6, "the hop up starts under the seat")
        #expect(abs(lifted.x - under.x) < 1e-6, "the hop up is vertical on screen")
        let front = p[p.count - 3]
        #expect(g.isOpenAt(frame.uv(fit.world(front))), "it steps under the seat from open floor")
        #expect(alongAnAxis(front, under), "the step under the seat runs along u or v")
        for (a, b) in zip(p.dropLast(2), p.dropLast(2).dropFirst()) {
            #expect(blockedSamples(g, a, b) == 0, "leg \(a) -> \(b) stays on open floor")
        }
    }

    /// The same from a raised seat: straight down onto its floor point, out onto the open floor in front, then round.
    @Test func aRaisedStartHopsStraightDownThenRoutes() {
        let (g, f, ground, lifted) = raisedSeat()
        let to = view(0.85, 0.85)
        let w = WalkRouter.path(from: lifted, fromFloor: f, to: to, grid: g, frame: frame, fit: fit)
        let p = w.points
        #expect(p.count >= 4, "a route, not the L")
        #expect(p.first == lifted && p.last == to)
        #expect(abs(p[1].x - ground.x) < 1e-6 && abs(p[1].y - ground.y) < 1e-6, "the hop down lands under the seat")
        #expect(abs(p[1].x - lifted.x) < 1e-6, "the hop down is vertical on screen")
        #expect(g.isOpenAt(frame.uv(fit.world(p[2]))), "it steps out onto open floor")
        #expect(alongAnAxis(p[1], p[2]), "the step out runs along u or v")
        for (a, b) in zip(p.dropFirst(2), p.dropFirst(3)) {
            #expect(blockedSamples(g, a, b) == 0, "leg \(a) -> \(b) stays on open floor")
        }
    }

    @Test func anInterruptedWalkRestartsFromTheFloorNotTheLiftedSeat() {
        let (g, f, ground, lifted) = raisedSeat()
        let from = view(0.15, 0.15)
        let up = WalkRouter.path(from: from, to: lifted, toFloor: f, grid: g, frame: frame, fit: fit)
        // During the hop up, at its end, and past it (the 0.18 s landing window), the cat counts as under the seat.
        for d in [up.length - 0.5, up.length, up.length + 5] {
            let q = up.floorPosition(atDistance: d)
            #expect(abs(q.x - ground.x) < 1e-6 && abs(q.y - ground.y) < 1e-6, "at \(d)")
        }
        // Mid-route on the floor it is where it is drawn.
        #expect(up.floorPosition(atDistance: up.length / 2) == up.position(atDistance: up.length / 2))
        // Off a raised seat: during the hop down it counts as on the floor under the seat.
        let down = WalkRouter.path(from: lifted, fromFloor: f, to: from, grid: g, frame: frame, fit: fit)
        for d in [CGFloat(0), 0.5] {
            let q = down.floorPosition(atDistance: d)
            #expect(abs(q.x - ground.x) < 1e-6 && abs(q.y - ground.y) < 1e-6, "at \(d)")
        }
        // A walk without raised ends is drawn where it is.
        let flat = WalkRouter.path(from: from, to: view(0.85, 0.85), grid: g, frame: frame, fit: fit)
        #expect(flat.floorPosition(atDistance: flat.length) == flat.position(atDistance: flat.length))
    }

    @Test func aTinyStepUnderTheSeatKeepsTheHopVertical() {
        // Under the seat, then up: a 1 pt step before it would be merged into the hop, tilting it. It is dropped instead.
        let pts = [CGPoint(x: 0, y: 0), CGPoint(x: 40, y: 20), CGPoint(x: 41, y: 20.5), CGPoint(x: 41, y: 10)]
        let kept = WalkRouter.keepHopsExact(pts, liftedStart: false, liftedEnd: true)
        #expect(kept == [CGPoint(x: 0, y: 0), CGPoint(x: 41, y: 20.5), CGPoint(x: 41, y: 10)])
        let w = WalkPath(points: kept)
        #expect(abs(w.points[w.points.count - 1].x - w.points[w.points.count - 2].x) < 1e-9, "the hop up is vertical")
        // Same at the start: down off the seat, then a 1 pt step.
        let start = [CGPoint(x: 41, y: 10), CGPoint(x: 41, y: 20.5), CGPoint(x: 42, y: 21), CGPoint(x: 80, y: 40)]
        #expect(WalkRouter.keepHopsExact(start, liftedStart: true, liftedEnd: false)
                == [CGPoint(x: 41, y: 10), CGPoint(x: 41, y: 20.5), CGPoint(x: 80, y: 40)])
        // Long steps stay.
        let long = [CGPoint(x: 0, y: 0), CGPoint(x: 40, y: 20), CGPoint(x: 60, y: 30), CGPoint(x: 60, y: 10)]
        #expect(WalkRouter.keepHopsExact(long, liftedStart: false, liftedEnd: true) == long)
    }
}

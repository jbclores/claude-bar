import CoreGraphics

/// Turns a walk's two view points into a route around furniture on the nav grid, or today's L when there is no grid
/// or no route (or the numbers aren't finite).
///
/// Routes run between floor points. A cat on a raised seat (a sofa, a bed) is drawn with its feet lifted, so a walk
/// end that is a seat or spot passes its own floor point (`fromFloor` / `toFloor`) along with its drawn feet: the route
/// goes from the drawn start straight down onto its floor point, round the furniture, to the end's floor point, and
/// straight up onto the drawn end (the lift is straight up on screen). With no floor point (a cat stopped mid-walk on
/// open floor), the view point is taken as on the floor.
public enum WalkRouter {
    public static func path(from: CGPoint, fromFloor: FloorPoint? = nil, to: CGPoint, toFloor: FloorPoint? = nil,
                            grid: NavGrid?, frame: FloorFrame?, fit: SceneFit?) -> WalkPath {
        let fallback = WalkPath(from: from, to: to)
        guard let grid, let frame, let fit, isFinite(from), isFinite(to) else { return fallback }
        let start = fromFloor ?? frame.uv(fit.world(from)), goal = toFloor ?? frame.uv(fit.world(to))
        guard start.u.isFinite, start.v.isFinite, goal.u.isFinite, goal.v.isFinite,
              let route = grid.findPath(from: start, to: goal), !route.isEmpty else { return fallback }
        var points = [from]
        // Off a raised seat: straight down onto its floor point first (WalkPath drops it when there is no lift).
        if fromFloor != nil {
            let q = fit.point(frame.px(start))
            guard isFinite(q) else { return fallback }
            points.append(q)
        }
        for p in route {
            let q = fit.point(frame.px(p))
            guard isFinite(q) else { return fallback }
            points.append(q)
        }
        // The route ends on the goal when it is open floor; when it is blocked (a seat, a bed) it ends on the open floor
        // in front of it, and the last hop onto the goal is kept (it runs along an axis). When NavGrid's approach fell back to
        // the nearest cell's centre, off both of the goal's axes, that hop becomes an L (nav-grid.ts axisLegs: the open
        // elbow, else the longer leg on screen first) instead of a diagonal.
        guard let end = route.last else { return fallback }
        let du = abs(end.u - goal.u), dv = abs(end.v - goal.v)
        if du < 1e-9, dv < 1e-9 {
            // On a raised end the route's last point is its floor point: the hop up onto `to` follows.
            if toFloor == nil { points[points.count - 1] = to } else { points.append(to) }
        } else {
            if du >= 1e-9, dv >= 1e-9 {
                let uFirst = FloorPoint(u: goal.u, v: end.v), vFirst = FloorPoint(u: end.u, v: goal.v)
                let order = du * frame.eu >= dv * frame.ev ? [uFirst, vFirst] : [vFirst, uFirst]
                let elbow = order.first(where: grid.isOpenAt) ?? order[0]
                let q = fit.point(frame.px(elbow))
                guard isFinite(q) else { return fallback }
                points.append(q)
            }
            // A raised end: onto its floor point under the seat, then straight up.
            if toFloor != nil {
                let q = fit.point(frame.px(goal))
                guard isFinite(q) else { return fallback }
                points.append(q)
            }
            points.append(to)
        }
        let below = fromFloor.map { fit.point(frame.px($0)) }, under = toFloor.map { fit.point(frame.px($0)) }
        var walk = WalkPath(points: keepHopsExact(points, liftedStart: below != nil, liftedEnd: under != nil))
        // A hop that survived as its own leg (a seat with no lift has none): the walk knows the cat is off the floor there.
        let w = walk.points
        if let below, w.count >= 2, hypot(w[1].x - below.x, w[1].y - below.y) < 1e-6 { walk.liftedStart = true }
        if let under, w.count >= 2, hypot(w[w.count - 2].x - under.x, w[w.count - 2].y - under.y) < 1e-6 { walk.liftedEnd = true }
        return walk
    }

    /// A step under 2 pt (WalkPath.minLeg) next to a hop off or onto a raised seat would merge into the hop and tilt it:
    /// drop the step's far end instead, so the hop stays vertical (the leg before it is off its axis by under 2 pt).
    static func keepHopsExact(_ points: [CGPoint], liftedStart: Bool, liftedEnd: Bool) -> [CGPoint] {
        var p = points
        func tiny(_ a: CGPoint, _ b: CGPoint) -> Bool { hypot(b.x - a.x, b.y - a.y) < WalkPath.minLeg }
        if liftedEnd, p.count >= 4, tiny(p[p.count - 3], p[p.count - 2]) { p.remove(at: p.count - 3) }
        if liftedStart, p.count >= 4, tiny(p[1], p[2]) { p.remove(at: 2) }
        return p
    }

    private static func isFinite(_ p: CGPoint) -> Bool { p.x.isFinite && p.y.isFinite }
}

import CoreGraphics

/// Turns a walk's two view points into a route around furniture on the nav grid, or today's L when there is no grid
/// or no route (or the numbers aren't finite).
public enum WalkRouter {
    public static func path(from: CGPoint, to: CGPoint, grid: NavGrid?, frame: FloorFrame?, fit: SceneFit?) -> WalkPath {
        let fallback = WalkPath(from: from, to: to)
        guard let grid, let frame, let fit, isFinite(from), isFinite(to) else { return fallback }
        let start = frame.uv(fit.world(from)), goal = frame.uv(fit.world(to))
        guard start.u.isFinite, start.v.isFinite, goal.u.isFinite, goal.v.isFinite,
              let route = grid.findPath(from: start, to: goal), !route.isEmpty else { return fallback }
        var points = [from]
        for p in route {
            let q = fit.point(frame.px(p))
            guard isFinite(q) else { return fallback }
            points.append(q)
        }
        // The route ends on `to` when it is open floor; when it is blocked (a seat, a bed) it ends on the open floor in
        // front of it, and the last hop onto `to` is kept (it runs along an axis).
        if let end = route.last, abs(end.u - goal.u) < 1e-9, abs(end.v - goal.v) < 1e-9 {
            points[points.count - 1] = to
        } else {
            points.append(to)
        }
        return WalkPath(points: points)
    }

    private static func isFinite(_ p: CGPoint) -> Bool { p.x.isFinite && p.y.isFinite }
}

import CoreGraphics

/// A cat's walk between two spots, the way Cat Office walks (simulation-engine.ts walk(), nav-grid.ts): an L along the
/// floor's two diagonals (no diagonal sliding), constant speed, facing each leg's direction; leg frames by distance.
/// Points are on screen (y down); the floor's +u runs down-left and +v down-right.
public struct WalkPath: Equatable, Sendable {
    /// Legs shorter than this are dropped (Cat Office's MIN_LEG_PX).
    static let minLeg: CGFloat = 2

    public private(set) var points: [CGPoint]
    public private(set) var length: CGFloat
    private var directions: [String]

    /// The L: along the floor's two diagonals, the longer leg first.
    public init(from start: CGPoint, to end: CGPoint) {
        let dx = end.x - start.x, dy = end.y - start.y
        // dx = 2(b − a), dy = a + b, for a steps along +u = (−2, 1) and b along +v = (2, 1).
        let a = (2 * dy - dx) / 4, b = (2 * dy + dx) / 4
        let uLeg = CGVector(dx: -2 * a, dy: a), vLeg = CGVector(dx: 2 * b, dy: b)
        // The longer leg first: one turn, like an A* route that prefers few turns.
        let firstLeg = hypot(uLeg.dx, uLeg.dy) >= hypot(vLeg.dx, vLeg.dy) ? uLeg : vLeg
        self.init(points: [start, CGPoint(x: start.x + firstLeg.dx, y: start.y + firstLeg.dy), end])
    }

    /// A walk through `points` in order (first = start), facing each leg's direction. Legs shorter than `minLeg` merge
    /// into their neighbour; fewer than two distinct points make a zero-length walk at the point.
    public init(points route: [CGPoint]) {
        guard let start = route.first else { self.init(still: .zero); return }
        var points = [start]
        for (i, q) in route.enumerated().dropFirst() {
            let last = points[points.count - 1]
            let tiny = hypot(q.x - last.x, q.y - last.y) < Self.minLeg
            if i < route.count - 1 {
                if !tiny { points.append(q) }
            } else if !tiny || points.count > 1 {
                // The route ends exactly at its last point: a tiny final leg folds into the one before it.
                if tiny { points[points.count - 1] = q } else { points.append(q) }
            } else if q != start {
                points.append(q)
            }
        }
        if points.count == 1 { self.init(still: start); return }
        self.init(legs: points)
    }

    private init(still p: CGPoint) {
        self.init(points: [p], directions: ["front-left"], length: 0)
    }

    private init(legs points: [CGPoint]) {
        self.init(points: points, directions: zip(points, points.dropFirst()).map(Self.direction),
                  length: zip(points, points.dropFirst()).reduce(0) { $0 + hypot($1.1.x - $1.0.x, $1.1.y - $1.0.y) })
    }

    private init(points: [CGPoint], directions: [String], length: CGFloat) {
        self.points = points
        self.directions = directions
        self.length = length
    }

    /// A leg's facing from its screen vector: +u is down-left, +v down-right.
    private static func direction(_ p: CGPoint, _ q: CGPoint) -> String {
        let dx = q.x - p.x, dy = q.y - p.y
        if hypot(dx, dy) < minLeg { return "front-left" }
        let a = (2 * dy - dx) / 4, b = (2 * dy + dx) / 4
        if abs(a) >= abs(b) { return a > 0 ? "front-left" : "back-right" }
        return b > 0 ? "front-right" : "back-left"
    }

    /// Where the cat is after walking `distance` (at the end once past it).
    public func position(atDistance distance: CGFloat) -> CGPoint {
        var left = max(0, distance)
        for (p, q) in zip(points, points.dropFirst()) {
            let leg = hypot(q.x - p.x, q.y - p.y)
            if left <= leg, leg > 0 { return CGPoint(x: p.x + (q.x - p.x) * left / leg, y: p.y + (q.y - p.y) * left / leg) }
            left -= leg
        }
        return points[points.count - 1]
    }

    /// The way the cat faces after walking `distance`: its current leg's direction.
    public func direction(atDistance distance: CGFloat) -> String {
        var left = max(0, distance)
        for (i, (p, q)) in zip(points, points.dropFirst()).enumerated() {
            let leg = hypot(q.x - p.x, q.y - p.y)
            if left < leg { return directions[i] }
            left -= leg
        }
        return directions[directions.count - 1]
    }

    /// The walk frame (1–4) after `distance`: the next one every `stride`, starting from the cat's own `phase`.
    public static func frame(distance: CGFloat, stride: CGFloat, phase: Int) -> Int {
        (Int((max(0, distance) / stride).rounded(.down)) + phase) % 4 + 1
    }

    /// Each cat starts its stride somewhere else, so cats don't march in step (Cat Office's stridePhase).
    public static func phase(for id: String) -> Int { Int(CatPicker.fnv1a(id) % 4) }

    /// A cat's speed: `base` varied by up to ±15%, the same each time (Cat Office: 0.85–1.15 per cat).
    public static func speed(for id: String, base: CGFloat) -> CGFloat {
        base * (0.85 + 0.3 * CGFloat(CatPicker.fnv1a("walk:" + id) % 1000) / 999)
    }
}

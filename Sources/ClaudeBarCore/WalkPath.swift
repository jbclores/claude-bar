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

    public init(from start: CGPoint, to end: CGPoint) {
        let dx = end.x - start.x, dy = end.y - start.y
        // dx = 2(b − a), dy = a + b, for a steps along +u = (−2, 1) and b along +v = (2, 1).
        let a = (2 * dy - dx) / 4, b = (2 * dy + dx) / 4
        let uLeg = CGVector(dx: -2 * a, dy: a), vLeg = CGVector(dx: 2 * b, dy: b)
        // The longer leg first: one turn, like an A* route that prefers few turns.
        let first = hypot(uLeg.dx, uLeg.dy) >= hypot(vLeg.dx, vLeg.dy) ? (uLeg, a, true) : (vLeg, b, false)
        let second = first.2 ? (vLeg, b, false) : (uLeg, a, true)
        var points = [start], directions: [String] = []
        for (leg, amount, isU) in [first, second] where hypot(leg.dx, leg.dy) >= Self.minLeg {
            let last = points[points.count - 1]
            points.append(CGPoint(x: last.x + leg.dx, y: last.y + leg.dy))
            directions.append(isU ? (amount > 0 ? "front-left" : "back-right") : (amount > 0 ? "front-right" : "back-left"))
        }
        if points.count == 1 { points.append(end) ; directions.append("front-left") }
        points[points.count - 1] = end
        self.points = points
        self.directions = directions
        length = zip(points, points.dropFirst()).reduce(0) { $0 + hypot($1.1.x - $1.0.x, $1.1.y - $1.0.y) }
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

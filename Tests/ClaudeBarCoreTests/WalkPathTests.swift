import CoreGraphics
import Testing
@testable import ClaudeBarCore

@Suite struct WalkPathTests {
    func near(_ a: CGPoint, _ b: CGPoint) -> Bool { abs(a.x - b.x) < 0.01 && abs(a.y - b.y) < 0.01 }

    @Test func walksAnLAlongTheFloorDiagonals() {
        // Down-right then down-left legs: Δ = (0, 40) is 20 along +u (down-left) and 20 along +v (down-right).
        let path = WalkPath(from: .zero, to: CGPoint(x: 0, y: 40))
        #expect(path.points.count == 3)
        #expect(near(path.points[2], CGPoint(x: 0, y: 40)))
        let elbow = path.points[1]
        #expect(near(elbow, CGPoint(x: -40, y: 20)) || near(elbow, CGPoint(x: 40, y: 20)))
    }

    @Test func facesEachLegLikeCatOffice() {
        // Up-right only: −u in Cat Office terms → back-right.
        let up = WalkPath(from: .zero, to: CGPoint(x: 40, y: -20))
        #expect(up.points.count == 2 && up.direction(atDistance: 1) == "back-right")
        #expect(WalkPath(from: .zero, to: CGPoint(x: -40, y: 20)).direction(atDistance: 1) == "front-left")
        #expect(WalkPath(from: .zero, to: CGPoint(x: 40, y: 20)).direction(atDistance: 1) == "front-right")
        #expect(WalkPath(from: .zero, to: CGPoint(x: -40, y: -20)).direction(atDistance: 1) == "back-left")
    }

    @Test func positionMovesAtConstantSpeedAndStopsAtTheEnd() {
        let path = WalkPath(from: .zero, to: CGPoint(x: 40, y: -20))
        #expect(near(path.position(atDistance: 0), .zero))
        #expect(near(path.position(atDistance: path.length / 2), CGPoint(x: 20, y: -10)))
        #expect(near(path.position(atDistance: path.length + 50), CGPoint(x: 40, y: -20)))
    }

    @Test func legsShorterThanTwoPointsAreSkipped() {
        let path = WalkPath(from: .zero, to: CGPoint(x: 40.5, y: -19.5))
        #expect(path.points.count == 2)
    }

    @Test func legFramesGoByDistanceFromEachCatsPhase() {
        #expect(WalkPath.frame(distance: 0, stride: 5, phase: 0) == 1)
        #expect(WalkPath.frame(distance: 5, stride: 5, phase: 0) == 2)
        #expect(WalkPath.frame(distance: 19.9, stride: 5, phase: 0) == 4)
        #expect(WalkPath.frame(distance: 20, stride: 5, phase: 0) == 1)
        #expect(WalkPath.frame(distance: 0, stride: 5, phase: 2) == 3)
        #expect(WalkPath.phase(for: "office-82eb65") == WalkPath.phase(for: "office-82eb65"))
        #expect((0..<4).contains(WalkPath.phase(for: "x")))
    }

    @Test func speedVariesUpTo15PercentPerCat() {
        let speeds = ["a", "b", "c", "office-82eb65", "office-9fc8a4"].map { WalkPath.speed(for: $0, base: 100) }
        #expect(speeds.allSatisfy { $0 >= 85 && $0 <= 115 })
        #expect(WalkPath.speed(for: "a", base: 100) == WalkPath.speed(for: "a", base: 100))
    }
}

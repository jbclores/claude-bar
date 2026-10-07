import CoreGraphics
import Testing
@testable import ClaudeBarCore

@Suite struct SceneFitTests {
    @Test func fillsTheWidthAndCentresTheFloor() throws {
        let f = try #require(FloorFrame(corners: try expected("user").floors[1].corners))
        let fit = SceneFit.fill(floor: f, into: CGSize(width: 472, height: 180))
        let left = fit.point(f.corners.left), right = fit.point(f.corners.right)
        #expect(abs(left.x - 20 * fit.scale) < 0.5, "a 20 world-px margin each side")
        #expect(abs((left.x + right.x) / 2 - 236) < 0.5, "centred across")
        let mid = fit.point(WorldPoint(x: f.corners.top.x, y: (f.corners.top.y + f.corners.bottom.y) / 2))
        #expect(abs(mid.y - 90) < 0.5, "floor centred down")
        #expect(abs(right.x - left.x - (472 - 40 * fit.scale)) < 0.5, "fills the width")
    }
}

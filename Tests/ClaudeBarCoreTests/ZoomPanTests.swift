import CoreGraphics
import Testing
@testable import ClaudeBarCore

@Suite struct ZoomPanTests {
    let room = CGSize(width: 400, height: 200)

    @Test func startsAtTheWholeRoom() {
        let z = ZoomPan()
        #expect(z.scale == 1 && z.offset == .zero && !z.isZoomed)
    }

    @Test func zoomKeepsThePinchPointStill() {
        var z = ZoomPan()
        let q = CGPoint(x: 100, y: 50)
        z.zoom(by: 2, at: q, in: room)
        #expect(z.scale == 2)
        // The content point under the pinch stays under it.
        let content = z.unzoom(q)
        #expect(abs(content.x - 100) < 0.001 && abs(content.y - 50) < 0.001)
    }

    @Test func zoomIsLimitedTo1And3() {
        var z = ZoomPan()
        z.zoom(by: 10, at: .zero, in: room)
        #expect(z.scale == 3)
        z.zoom(by: 0.01, at: .zero, in: room)
        #expect(z.scale == 1 && z.offset == .zero)
    }

    @Test func panStopsAtTheRoomEdges() {
        var z = ZoomPan()
        z.zoom(by: 2, at: CGPoint(x: 200, y: 100), in: room)
        z.pan(by: CGSize(width: 10_000, height: 10_000), in: room)
        #expect(z.offset == .zero, "top-left corner")
        z.pan(by: CGSize(width: -10_000, height: -10_000), in: room)
        #expect(z.offset == CGPoint(x: -400, y: -200), "bottom-right corner")
        var whole = ZoomPan()
        whole.pan(by: CGSize(width: 50, height: 50), in: room)
        #expect(whole.offset == .zero, "no panning at 1×")
    }

    @Test func doubleClickTogglesBetween2xAndTheWholeRoom() {
        var z = ZoomPan()
        z.toggle(at: CGPoint(x: 300, y: 150), in: room)
        #expect(z.scale == 2 && z.isZoomed)
        z.toggle(at: CGPoint(x: 10, y: 10), in: room)
        #expect(z.scale == 1 && z.offset == .zero)
    }

    @Test func unzoomMapsShownPointsBackToTheRoom() {
        var z = ZoomPan()
        z.zoom(by: 2, at: .zero, in: room)
        #expect(z.unzoom(CGPoint(x: 100, y: 60)) == CGPoint(x: 50, y: 30))
    }
}

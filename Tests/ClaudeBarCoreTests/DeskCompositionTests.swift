import CoreGraphics
import Foundation
import Testing
@testable import ClaudeBarCore

@Suite struct DeskCompositionTests {
    // Real numbers from Cat Office's desks.json.
    let walnut = DeskGeometry(width: 276, height: 242, anchor: CGPoint(x: 186.5, y: 239.2), stand: CGVector(dx: -110, dy: -20),
                              rear: DeskGeometry.Sprite(width: 282, height: 228, anchor: CGPoint(x: 189.5, y: 223.7)))

    func near(_ a: CGFloat, _ b: CGFloat) -> Bool { abs(a - b) < 0.01 }

    @Test func parsesGeometryFromDesksJSON() {
        let json = #"{"desks":[{"id":"s1-walnut","image":"a.png","width":276,"height":242,"anchor":{"x":186.5,"y":239.2},"stand":{"dx":-110.0,"dy":-20.0},"rear":{"image":"r.png","width":282,"height":228,"anchor":{"x":189.5,"y":223.7}}}]}"#
        #expect(DeskCatalog.parse(Data(json.utf8)).geometry(for: "s1-walnut") == walnut)
        #expect(DeskCatalog.parse(Data(json.utf8)).geometry(for: nil) == walnut, "default: the first desk")
    }

    @Test func catStandsAtTheDesksStandPointWithFeetThere() {
        let c = DeskComposition(walnut, flip: false, rear: false)
        // Desk drawn with its anchor at the origin.
        #expect(near(c.desk.minX, -186.5) && near(c.desk.minY, -239.2) && near(c.desk.width, 276))
        // The cat's feet (canvas 180,300 at 160/210 scale) on the stand point (-110, -20).
        let s = CGFloat(160) / 210
        #expect(near(c.cat.minX + 180 * s, -110) && near(c.cat.minY + 300 * s, -20))
        #expect(near(c.cat.width, 360 * s) && near(c.cat.height, 380 * s))
        #expect(c.catInFront && c.facing == "back-right")
    }

    @Test func aTeammatesOwnCatCanvasKeepsItsFeetOnTheStandPoint() {
        let frame = CatFrame(canvas: CGSize(width: 200, height: 250), feet: CGPoint(x: 100, y: 220), bodyHeight: 160)
        let c = DeskComposition(walnut, flip: false, rear: false, cat: frame)
        // catHeight 160 over bodyHeight 160: drawn at full size.
        #expect(near(c.cat.minX + 100, -110) && near(c.cat.minY + 220, -20))
        #expect(near(c.cat.width, 200) && near(c.cat.height, 250))
        #expect(near(c.feet.x, -110) && near(c.feet.y, -20))
        #expect(near(DeskComposition.catScale(frame), 1))
        #expect(near(DeskComposition.catScale(.standard), DeskComposition.catScale))
    }

    @Test func mirroredDeskMirrorsTheStandPointAndFacing() {
        let c = DeskComposition(walnut, flip: true, rear: false)
        #expect(near(c.desk.minX, -(276 - 186.5)))
        let s = CGFloat(160) / 210
        #expect(near(c.cat.minX + 180 * s, 110) && c.facing == "back-left")
    }

    @Test func turnedDeskPutsTheCatBehindFacingUs() {
        let c = DeskComposition(walnut, flip: false, rear: true)
        #expect(!c.catInFront && c.facing == "front-left")
        #expect(near(c.desk.width, 282) && near(c.desk.minY, -223.7), "the rear sprite")
        let feetY = c.cat.minY + 300 * CGFloat(160) / 210
        #expect(feetY < -20, "on the far side: further back than the front stand point")
        #expect(DeskComposition(walnut, flip: true, rear: true).facing == "front-right")
    }

    @Test func boundsHoldDeskAndCat() {
        let c = DeskComposition(walnut, flip: false, rear: false)
        for r in [c.desk, c.cat] {
            #expect(c.bounds.minX <= r.minX + 0.01 && c.bounds.maxX >= r.maxX - 0.01)
            #expect(c.bounds.minY <= r.minY + 0.01 && c.bounds.maxY >= r.maxY - 0.01)
        }
    }
}

import CoreGraphics
import Testing
@testable import ClaudeBarCore

@Suite struct SceneFitTests {
    static let size = CGSize(width: 472, height: 180)

    @Test func fillsTheWidthAndCentresAcross() throws {
        let room = try BuiltRoomTests().built(2)
        let f = room.frame
        let fit = SceneFit.fill(floor: f, content: room.contentBounds(catHeight: 160), into: Self.size)
        let left = fit.point(f.corners.left), right = fit.point(f.corners.right)
        #expect(abs(left.x - 20 * fit.scale) < 0.5, "a 20 world-px margin each side")
        #expect(abs((left.x + right.x) / 2 - 236) < 0.5, "centred across")
        #expect(abs(right.x - left.x - (472 - 40 * fit.scale)) < 0.5, "fills the width")
    }

    @Test(arguments: [1, 2, 12]) func everySeatAndDeskCatIsInView(id: Int) throws {
        let room = try BuiltRoomTests().built(id)
        let content = room.contentBounds(catHeight: 160)
        let fit = SceneFit.fill(floor: room.frame, content: content, keep: room.catBounds(catHeight: 160), into: Self.size)
        let spots = room.seats.map(\.standAt) + room.desks.map(\.standAt) + (room.elevator.map { [$0.standAt] } ?? [])
        #expect(!spots.isEmpty)
        for s in spots {
            let feet = room.frame.px(s)
            let y = fit.point(feet).y, top = fit.point(WorldPoint(x: feet.x, y: feet.y - 1.1 * 160)).y
            #expect(y >= 0 && y <= 180, "floor \(id): feet at \(y)")
            #expect(top >= 0 && top <= 180, "floor \(id): cat top at \(top)")
        }
        let shown = fit.rect(content)
        if shown.height <= 180 {
            #expect(abs(shown.midY - 90) < 0.5, "floor \(id): content centred down")
        } else {
            // Too tall: the top kept, unless that would put a cat's spot below the view.
            let cats = fit.rect(try #require(room.catBounds(catHeight: 160)))
            #expect(abs(shown.minY) < 0.5 || abs(cats.maxY - 180) < 0.5, "floor \(id): top kept or cats kept")
        }
    }

    @Test func tallContentKeepsItsTopUnlessCatsWouldLeave() throws {
        let f = try #require(FloorFrame(corners: try expected("user").floors[1].corners))
        let content = CGRect(x: 0, y: 100, width: 10, height: 5000)
        let fit = SceneFit.fill(floor: f, content: content, into: Self.size)
        #expect(abs(fit.rect(content).minY) < 0.5)
        let keep = CGRect(x: 0, y: 2000, width: 10, height: 100)
        let kept = SceneFit.fill(floor: f, content: content, keep: keep, into: Self.size)
        #expect(abs(kept.rect(keep).maxY - 180) < 0.5, "the cats' band pulled up into view")
    }
}

@Suite struct ContentBoundsTests {
    @Test func floorTwoHoldsEveryDeskAndItsCat() throws {
        let room = try BuiltRoomTests().built(2)
        let b = room.contentBounds(catHeight: 160)
        #expect(!room.desks.isEmpty)
        for d in room.desks {
            #expect(b.contains(d.rect), "\(d.id)")
            let feet = room.frame.px(d.standAt)
            #expect(b.contains(CGPoint(x: feet.x, y: feet.y - 1.1 * 160)), "\(d.id) cat top")
        }
        for p in room.props { #expect(b.contains(p.rect), "\(p.id)") }
    }
}


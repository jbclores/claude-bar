import CoreGraphics
import Foundation
import Testing
@testable import ClaudeBarCore

@Suite struct RoomCoverTests {
    /// A cat on `spot` as SceneCats draws it: its figure and depth.
    func cat(_ r: BuiltRoom, _ s: RoomSpot, perch: String?) -> (z: Int, figure: CGRect) {
        let px = r.frame.px(s.standAt)
        let figure = RoomGeometry.figure(feet: px, catHeight: 160, lift: s.lift)
        return (RoomGeometry.catZ(feet: s.standAt, figure: figure, boxes: r.boxes, perch: perch), figure)
    }

    @Test func standingIsInDrawingOrder() throws {
        let r = try BuiltRoomTests().built(2)
        let s = r.standing
        #expect(s.count == r.desks.count + r.props.count + r.fixtures.count)
        #expect(zip(s, s.dropFirst()).allSatisfy { ($0.box.z, $0.kind.rawValue, $0.index) < ($1.box.z, $1.kind.rawValue, $1.index) })
    }

    @Test func windowSeatCatLiftsTheCushionsInFrontOfIt() throws {
        let r = try BuiltRoomTests().built(1)
        let seat = try #require(r.seats.first { $0.owner == "window-seat" })
        let c = cat(r, seat, perch: seat.lift > 0 ? seat.owner : nil)
        let ids = RoomGeometry.overCats([c], standing: r.standing).map(\.id)
        #expect(ids.contains("prop:cushion-3"))
        // cushion-2 is nearer and overlaps cushion-3: it must be drawn again too, after it.
        let i3 = try #require(ids.firstIndex(of: "prop:cushion-3")), i2 = try #require(ids.firstIndex(of: "prop:cushion-2"))
        #expect(i3 < i2)
    }

    @Test func deskCatLiftsTheNearerDesksOverItsNeighbour() throws {
        let r = try BuiltRoomTests().built(2)
        let desk = try #require(r.desks.first { $0.id == "f2-desk-2" })
        let spot = RoomSpot(id: "w", kind: "desk", pose: nil, standAt: desk.standAt, facing: desk.facing, lift: 0, owner: desk.id)
        let ids = RoomGeometry.overCats([cat(r, spot, perch: nil)], standing: r.standing).map(\.id)
        #expect(ids.contains("desk:f2-desk-4") && ids.contains("desk:f2-desk-6"))
        #expect(ids.firstIndex(of: "desk:f2-desk-4")! < ids.firstIndex(of: "desk:f2-desk-6")!)
    }

    @Test func closureAddsOnlyNearerOverlappingPieces() {
        func piece(_ id: String, _ z: Int, _ x: Double) -> StandingPiece {
            StandingPiece(kind: .prop, index: z, id: id,
                          box: OccluderBox(front: FloorPoint(u: 0, v: 0), rect: CGRect(x: x, y: 0, width: 10, height: 10), back: nil, z: z))
        }
        // a (behind the cat), b (over the cat), c (nearer, overlaps b), d (nearer, overlaps c only), e (far off).
        let standing = [piece("a", 1, 0), piece("b", 5, 0), piece("c", 6, 8), piece("d", 7, 16), piece("e", 8, 100)]
        let out = RoomGeometry.overCats([(z: 3, figure: CGRect(x: 0, y: 0, width: 5, height: 5))], standing: standing)
        #expect(out.map(\.id) == ["b", "c", "d"])
        #expect(RoomGeometry.overCats([], standing: standing).isEmpty)
    }
}

@Suite struct CatHitTests {
    @Test func frontmostCatWinsWhereFramesOverlap() {
        let hits = [
            "back": CatHit(frame: CGRect(x: 0, y: 0, width: 20, height: 20), z: 100, feet: CGPoint(x: 10, y: 20)),
            "front": CatHit(frame: CGRect(x: 5, y: 5, width: 20, height: 20), z: 200, feet: CGPoint(x: 15, y: 25)),
            "far": CatHit(frame: CGRect(x: 50, y: 50, width: 20, height: 20), z: 999, feet: CGPoint(x: 60, y: 70)),
        ]
        #expect(CatHit.frontmost(hits, at: CGPoint(x: 10, y: 10)) == "front")
        #expect(CatHit.frontmost(hits, at: CGPoint(x: 2, y: 2)) == "back")
        #expect(CatHit.frontmost(hits, at: CGPoint(x: 40, y: 40)) == nil)
    }

    @Test func sameDepthPicksTheFeetNearestThePointer() {
        let hits = [
            "a": CatHit(frame: CGRect(x: 0, y: 0, width: 40, height: 40), z: 0, feet: CGPoint(x: 20, y: 40)),
            "b": CatHit(frame: CGRect(x: 10, y: 0, width: 40, height: 40), z: 0, feet: CGPoint(x: 30, y: 40)),
        ]
        #expect(CatHit.frontmost(hits, at: CGPoint(x: 16, y: 30)) == "a")
        #expect(CatHit.frontmost(hits, at: CGPoint(x: 34, y: 30)) == "b")
        // Every time the same answer (not the Dictionary's order).
        for _ in 0..<20 { #expect(CatHit.frontmost(hits, at: CGPoint(x: 25, y: 39)) == "a") }
    }
}

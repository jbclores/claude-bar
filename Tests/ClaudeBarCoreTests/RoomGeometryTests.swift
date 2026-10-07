// Tests/ClaudeBarCoreTests/RoomGeometryTests.swift
import CoreGraphics
import Foundation
import Testing
@testable import ClaudeBarCore

struct Expected: Decodable {
    struct Floor: Decodable {
        struct Plane: Decodable { let size, a, b, c, d, e, f: Double }
        struct Wall: Decodable { let length, a, b, e, f: Double }
        struct UV: Decodable { let u, v: Double }
        struct Rug: Decodable { let id, rug: String; let image: String?; let left, top, width, height: Double; let turned: Bool }
        struct Plate: Decodable { let left, top, width, height: Double }
        struct WallItem: Decodable { let id, item, wall: String; let image: String?; let mirrored: Bool; let left, top, width, height: Double; let plate: Plate? }
        struct Elevator: Decodable { let id: String; let standAt: UV; let facing: String }
        struct Fixture: Decodable { let id: String; let image: String?; let mirrored: Bool; let left, top, width, height: Double; let z: Int }
        struct Desk: Decodable { let id, desk, image: String; let flip, rear: Bool; let left, top, width, height: Double; let z: Int; let standAt: UV; let facing: String }
        struct Spot: Decodable { let id, kind: String; let pose: String?; let u, v: Double; let facing: String; let lift: Double }
        struct Prop: Decodable { let id, prop: String; let image: String?; let mirrored: Bool; let left, top, width, height: Double; let z: Int; let companionOf: String?; let spots: [Spot] }
        let id: Int; let corners: FloorCorners; let wallHeight, eu, ev: Double
        let floorPlane: Plane; let walls: [String: Wall]
        let rugs: [Rug]; let wallItems: [WallItem]; let elevators: [Elevator]; let fixtures: [Fixture]; let desks: [Desk]; let props: [Prop]
    }
    let floors: [Floor]
}

func expected(_ b: String) throws -> Expected { try JSONDecoder().decode(Expected.self, from: fixture("rooms/\(b)/expected.json")) }
func near(_ a: Double, _ b: Double, _ tol: Double = 0.5) -> Bool { abs(a - b) <= tol }

@Suite struct FloorMathTests {
    @Test(arguments: ["user", "edge"]) func planeAndWallsMatchCatOffice(_ b: String) throws {
        for e in try expected(b).floors {
            let f = try #require(FloorFrame(corners: e.corners))
            #expect(near(f.eu, e.eu) && near(f.ev, e.ev))
            let p = f.plane
            #expect(near(p.size, e.floorPlane.size))
            #expect(near(p.transform.a, e.floorPlane.a, 1e-3) && near(p.transform.b, e.floorPlane.b, 1e-3))
            #expect(near(p.transform.c, e.floorPlane.c, 1e-3) && near(p.transform.d, e.floorPlane.d, 1e-3))
            #expect(near(p.transform.tx, e.floorPlane.e) && near(p.transform.ty, e.floorPlane.f))
            for side in [WallSide.left, .right] {
                let w = f.wall(side, height: e.wallHeight), x = try #require(e.walls[side.rawValue])
                #expect(near(w.length, x.length) && near(w.transform.a, x.a, 1e-3) && near(w.transform.b, x.b, 1e-3))
                #expect(near(w.transform.tx, x.e) && near(w.transform.ty, x.f))
            }
        }
    }

    @Test func uvRoundTrips() throws {
        let f = try #require(FloorFrame(corners: try expected("user").floors[1].corners))
        let p = FloorPoint(u: 0.3, v: 0.7)
        let back = f.uv(f.px(p))
        #expect(near(back.u, 0.3, 1e-9) && near(back.v, 0.7, 1e-9))
    }

    @Test func degenerateCornersGiveNoFrame() {
        let z = WorldPoint(x: 5, y: 5)
        #expect(FloorFrame(corners: FloorCorners(top: z, left: z, bottom: z, right: z)) == nil)
    }

    @Test func depthRoundsLikeJavaScript() {
        #expect(FloorFrame.depthZ(0.00005) == 11)
        #expect(FloorFrame.depthZ(1.2345) == 12355)
    }
}

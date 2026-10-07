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

@Suite struct WallItemTests {
    @Test(arguments: ["user", "edge"]) func wallItemsMatchCatOffice(_ b: String) throws {
        let c = try RoomCatalogueTests().catalogue(b)
        let building = try #require(Building.parse(building: fixture("rooms/\(b)/building.json"), parts: fixture("rooms/\(b)/room-parts.json")))
        for e in try expected(b).floors {
            let floor = try #require(building.floor(id: e.id)), room = try #require(floor.room)
            let frame = try #require(FloorFrame(corners: e.corners))
            let placed = room.wallItems.compactMap { WallItems.place($0, frame: frame, catalogue: c, wallHeight: e.wallHeight) }
            #expect(placed.map(\.id) == e.wallItems.map(\.id))
            for (p, x) in zip(placed, e.wallItems) {
                #expect(p.image == x.image && p.mirrored == x.mirrored, "\(x.id)")
                #expect(near(p.box.minX, x.left) && near(p.box.minY, x.top) && near(p.box.width, x.width) && near(p.box.height, x.height), "\(x.id)")
                #expect((p.plate == nil) == (x.plate == nil))
                if let pp = p.plate, let xp = x.plate { #expect(near(pp.minX, xp.left) && near(pp.minY, xp.top)) }
            }
            let spots = room.wallItems.compactMap { WallItems.elevatorSpot($0, frame: frame, catalogue: c) }
            #expect(spots.map(\.id) == e.elevators.map(\.id))
            for (s, x) in zip(spots, e.elevators) {
                #expect(near(s.standAt.u, x.standAt.u, 1e-3) && near(s.standAt.v, x.standAt.v, 1e-3) && s.facing == x.facing)
            }
            let fixtures = room.wallItems.compactMap { WallItems.fixture($0, frame: frame, catalogue: c, wallHeight: e.wallHeight) }
            #expect(fixtures.count == e.fixtures.count)
            for (f, x) in zip(fixtures, e.fixtures) { #expect(near(f.rect.minX, x.left) && near(f.rect.minY, x.top) && f.box.z == x.z) }
        }
    }

    @Test func fullWindowHasSkyMullionsTransomAndFrame() throws {
        let c = try RoomCatalogueTests().catalogue()
        let frame = try #require(FloorFrame(corners: try expected("user").floors[1].corners))
        let w = WallItemPlacement(id: "w", item: "window-lounge-full", wall: .right, at: 0.21, width: 560, height: 127, bottom: 189, up: nil, transom: nil)
        let p = try #require(WallItems.place(w, frame: frame, catalogue: c, wallHeight: 399))
        guard case .stretch = p.pieces.first, case .nineSlice = p.pieces.last else { Issue.record("sky first, frame last: \(p.pieces)"); return }
        #expect(p.pieces.count >= 4)
    }

    @Test func windowDecorIsDrawnLikeCatOffice() throws {
        let c = try RoomCatalogueTests().catalogue()
        let frame = try #require(FloorFrame(corners: try expected("user").floors[1].corners))
        func decor(_ item: String) throws -> [CGRect] {
            let w = WallItemPlacement(id: "w", item: item, wall: .left, at: 0.5, width: nil, height: nil, bottom: nil, up: nil, transom: nil)
            let p = try #require(WallItems.place(w, frame: frame, catalogue: c, wallHeight: 399))
            #expect({ if case .nineSlice = p.pieces.first { return true } else { return false } }())
            return p.pieces.compactMap { if case .decor(_, let r) = $0 { return r } else { return nil } }
        }
        // 163x127 window, glass x 20...129, y 17...102: one 75px strip repeat, stretched over the 109px glass, 1px under its top.
        #expect(try decor("window-string-lights") == [CGRect(x: 20, y: 18, width: 109, height: 30)])
        // A hung lantern 53x61, centred on the glass, at its top.
        #expect(try decor("window-star-lantern") == [CGRect(x: 48, y: 17, width: 53, height: 61)])
    }

    @Test func unknownWallItemIsSkipped() throws {
        let c = try RoomCatalogueTests().catalogue()
        let frame = try #require(FloorFrame(corners: try expected("user").floors[1].corners))
        let w = WallItemPlacement(id: "x", item: "portal", wall: .left, at: 0.5, width: nil, height: nil, bottom: nil, up: nil, transom: nil)
        #expect(WallItems.place(w, frame: frame, catalogue: c, wallHeight: 399) == nil)
    }
}

@Suite struct DeskPlacementTests {
    @Test(arguments: ["user", "edge"]) func desksMatchCatOffice(_ b: String) throws {
        let c = try RoomCatalogueTests().catalogue(b)
        let building = try #require(Building.parse(building: fixture("rooms/\(b)/building.json"), parts: fixture("rooms/\(b)/room-parts.json")))
        for e in try expected(b).floors {
            let room = try #require(building.floor(id: e.id)?.room), frame = try #require(FloorFrame(corners: e.corners))
            let desks = room.desks.compactMap { DeskPlacer.place($0, frame: frame, catalogue: c) }
            #expect(desks.map(\.id) == e.desks.map(\.id))
            for (d, x) in zip(desks, e.desks) {
                #expect(d.image == x.image && d.flip == x.flip && d.rear == x.rear && d.facing == x.facing, "\(x.id)")
                #expect(near(d.rect.minX, x.left) && near(d.rect.minY, x.top) && near(d.rect.width, x.width) && d.box.z == x.z, "\(x.id)")
                #expect(near(d.standAt.u, x.standAt.u, 1e-3) && near(d.standAt.v, x.standAt.v, 1e-3), "\(x.id)")
            }
        }
    }
}

@Suite struct PropPlacementTests {
    @Test(arguments: ["user", "edge"]) func propsMatchCatOffice(_ b: String) throws {
        let c = try RoomCatalogueTests().catalogue(b)
        let building = try #require(Building.parse(building: fixture("rooms/\(b)/building.json"), parts: fixture("rooms/\(b)/room-parts.json")))
        for e in try expected(b).floors {
            let floor = try #require(building.floor(id: e.id))
            let room = try #require(floor.room), frame = try #require(FloorFrame(corners: e.corners))
            let grid = try #require(floor.gridSize)
            #expect(grid == 48, "floor \(e.id) grid")
            let desks = room.desks.compactMap { DeskPlacer.place($0, frame: frame, catalogue: c) }
            let props = PropPlacer.place(room: room, frame: frame, catalogue: c, desks: desks, gridSize: grid)
            #expect(props.map(\.id) == e.props.map(\.id), "floor \(e.id)")
            for (p, x) in zip(props, e.props) {
                #expect(p.image == x.image && p.mirrored == x.mirrored && p.companionOf == x.companionOf, "\(x.id)")
                #expect(near(p.rect.minX, x.left) && near(p.rect.minY, x.top) && near(p.rect.width, x.width) && near(p.rect.height, x.height), "\(x.id)")
                #expect(p.box.z == x.z, "\(x.id) z")
                #expect(p.spots.map(\.id) == x.spots.map(\.id), "\(x.id) spots")
                for (s, xs) in zip(p.spots, x.spots) {
                    #expect(near(s.standAt.u, xs.u, 1e-3) && near(s.standAt.v, xs.v, 1e-3) && s.facing == xs.facing && near(s.lift, xs.lift), "\(xs.id)")
                }
            }
            let rugs = PropPlacer.rugs(room: room, frame: frame, catalogue: c, gridSize: grid)
            #expect(rugs.map(\.id) == e.rugs.map(\.id))
            for (r, x) in zip(rugs, e.rugs) { #expect(near(r.rect.minX, x.left) && near(r.rect.minY, x.top) && r.turned == x.turned) }
        }
    }

    @Test func unknownPropSkipped() throws {
        let c = try RoomCatalogueTests().catalogue()
        let building = try #require(Building.parse(building: fixture("rooms/user/building.json"), parts: fixture("rooms/user/room-parts.json")))
        var room = try #require(building.floor(id: 2)?.room)
        room.props.append(PropPlacement(id: "ufo", prop: "ufo", u: 0.5, v: 0.5, facing: 0, decor: nil, panels: nil, companionsOff: nil))
        let corners = try #require(building.floor(id: 2)?.corners)
        let frame = try #require(FloorFrame(corners: corners))
        let grid = try #require(building.floor(id: 2)?.gridSize)
        let props = PropPlacer.place(room: room, frame: frame, catalogue: c, desks: [], gridSize: grid)
        #expect(!props.contains { $0.id == "ufo" } && props.contains { $0.prop == "printer" })
    }

    /// room.ts placeProp with a table: a table bit is drawn `top.height` px up and over its table, its z set by how
    /// deep it stands across the table (none of the fixtures has one). Off any table it stays on the floor.
    @Test func tableBitRidesItsTable() throws {
        let c = try RoomCatalogueTests().catalogue()
        let building = try #require(Building.parse(building: fixture("rooms/user/building.json"), parts: fixture("rooms/user/room-parts.json")))
        let corners = try #require(building.floor(id: 2)?.corners)
        let frame = try #require(FloorFrame(corners: corners))
        let grid = try #require(building.floor(id: 2)?.gridSize)
        func placement(_ id: String, _ prop: String, _ u: Double, _ v: Double) -> PropPlacement {
            PropPlacement(id: id, prop: prop, u: u, v: v, facing: 0, decor: nil, panels: nil, companionsOff: nil)
        }
        let room = FloorRoom(floor: "f", wall: "w", props: [
            placement("table", "conference-table-square", 0.5, 0.5),
            placement("phone", "table-speakerphone", 0.45, 0.46),
            placement("stray", "table-speakerphone", 0.9, 0.9),
        ])
        let props = PropPlacer.place(room: room, frame: frame, catalogue: c, desks: [], gridSize: grid)
        #expect(props.map(\.id) == ["table", "phone", "stray"])
        // The table's footprint: depth 126.3 along u, length 126 along v.
        let t = (u0: 0.5 - 126.3 / frame.eu, v0: 0.5 - 126.0 / frame.ev, u1: 0.5, v1: 0.5)
        let share = min(1, max(0, (0.45 + 0.46 - (t.u0 + t.v0)) / (t.u1 + t.v1 - (t.u0 + t.v0))))
        #expect(props[1].box.z == FloorFrame.depthZ(t.u1 + t.v1) + 1 + Int((share * 8 + 0.5).rounded(.down)))
        // Drawn at its anchor (centred in its one cell), lifted by the table's 55.6 px top.
        let cell = 1.0 / grid
        let a = frame.px(FloorPoint(u: 0.45 - (cell - 25 / frame.eu) / 2, v: 0.46 - (cell - 25 / frame.ev) / 2))
        #expect(near(props[1].rect.minX, a.x - 29.3, 1e-6) && near(props[1].rect.minY, a.y - 32.2 - 55.6, 1e-6))
        // Off any table: on the floor, by its own front corner.
        #expect(props[2].box.z == FloorFrame.depthZ(1.8))
        #expect(props.allSatisfy { $0.companionOf == nil })
    }

    /// room.ts rugSpots: each spot at its share of the rug's depth (u) and width (v) from its centre; a turned
    /// rug's art runs a quarter round (u += at.v * d, v -= at.u * w). Ids: the rug's, then `<id>:<spot id>`.
    @Test func rugSpotsFollowCatOffice() throws {
        let c = try RoomCatalogueTests().catalogue()
        let building = try #require(Building.parse(building: fixture("rooms/user/building.json"), parts: fixture("rooms/user/room-parts.json")))
        var room = try #require(building.floor(id: 1)?.room)
        let corners = try #require(building.floor(id: 1)?.corners)
        let frame = try #require(FloorFrame(corners: corners))
        let grid = try #require(building.floor(id: 1)?.gridSize)
        let rug = RugPlacement(id: "r", rug: "round-cream-painted", u: 0.5, v: 0.4, w: 0.3, d: 0.2, turned: nil)
        room.rugs = [rug]
        let flat = PropPlacer.rugSpots(room: room, frame: frame, catalogue: c, gridSize: grid)
        #expect(flat.map(\.id) == ["r", "r:rug-left", "r:rug-right"])
        #expect(flat.allSatisfy { $0.owner == "r" && $0.kind == "rug" && $0.lift == 0 })
        // rug-back: at (-0.1676, -0.1664), sleep, front-left.
        #expect(near(flat[0].standAt.u, 0.5 - 0.1676 * 0.2, 1e-9) && near(flat[0].standAt.v, 0.4 - 0.1664 * 0.3, 1e-9))
        #expect(flat[0].pose == "sleep" && flat[0].facing == "front-left")
        // rug-left: at (0.2045, -0.1043), sit, front-right.
        #expect(near(flat[1].standAt.u, 0.5 + 0.2045 * 0.2, 1e-9) && near(flat[1].standAt.v, 0.4 - 0.1043 * 0.3, 1e-9))
        #expect(flat[1].pose == "sit" && flat[1].facing == "front-right")

        room.rugs = [RugPlacement(id: "r", rug: "round-cream-painted", u: 0.5, v: 0.4, w: 0.3, d: 0.2, turned: true)]
        let turned = PropPlacer.rugSpots(room: room, frame: frame, catalogue: c, gridSize: grid)
        #expect(near(turned[1].standAt.u, 0.5 + -0.1043 * 0.2, 1e-9) && near(turned[1].standAt.v, 0.4 - 0.2045 * 0.3, 1e-9))
        #expect(turned[1].facing == "front-right")

        room.rugs = [RugPlacement(id: "plain", rug: "no-such-rug", u: 0.5, v: 0.4, w: 0.3, d: 0.2, turned: nil)]
        #expect(PropPlacer.rugSpots(room: room, frame: frame, catalogue: c, gridSize: grid).isEmpty)
    }
}

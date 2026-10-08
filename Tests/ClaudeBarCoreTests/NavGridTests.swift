import Foundation
import Testing
@testable import ClaudeBarCore

struct NavFixture: Decodable {
    struct P: Decodable { var u: Double; var v: Double }
    struct Route: Decodable { var from: P; var to: P; var path: [P]? }
    struct Nav: Decodable { var size: Int; var walkable: [String]; var routes: [Route] }
    struct FloorOut: Decodable { var id: Int; var nav: Nav? }
    var floors: [FloorOut]
}

@Suite struct NavGridTests {
    func load(_ b: String) throws -> (Building, RoomCatalogue, NavFixture) {
        let building = try #require(Building.parse(building: fixture("rooms/\(b)/building.json"), parts: fixture("rooms/\(b)/room-parts.json")))
        let catalogue = try RoomCatalogueTests().catalogue(b)
        let expected = try JSONDecoder().decode(NavFixture.self, from: fixture("rooms/\(b)/expected.json"))
        return (building, catalogue, expected)
    }

    @Test(arguments: ["user", "edge"]) func carvedGridMatchesCatOffice(_ b: String) throws {
        let (building, catalogue, expected) = try load(b)
        var checked = 0
        for f in expected.floors {
            guard let nav = f.nav else { continue }
            let floor = try #require(building.floors.first { $0.id == f.id })
            let room = try #require(RoomGeometry.build(floor: floor, catalogue: catalogue))
            let grid = try #require(NavGrid(floor: floor, room: room))
            #expect(grid.size == nav.size)
            #expect(grid.walkableRows == nav.walkable, "floor \(f.id)")
            checked += 1
        }
        #expect(checked > 0)
    }

    @Test func noGridNoNavGrid() throws {
        let (building, catalogue, _) = try load("user")
        var floor = try #require(building.floors.first)
        let room = try #require(RoomGeometry.build(floor: floor, catalogue: catalogue))
        floor.walkable = nil
        #expect(NavGrid(floor: floor, room: room) == nil)
    }

    @Test func footprintCellsPortsDesksTs() {
        // Size 10, margin half a cell: u 0.19…0.31 grows to 0.14…0.36, so cell centres 1.5…3.5 → cells 1…3; v likewise → 2…4.
        let cells = NavGrid.footprintCells(Footprint(u0: 0.19, u1: 0.31, v0: 0.29, v1: 0.41), size: 10)
        #expect(Set(cells) == Set([1, 2, 3].flatMap { u in [2, 3, 4].map { v in u * 10 + v } }))
        #expect(NavGrid.cellIndex(FloorPoint(u: 0.999, v: 0), size: 10) == 90)
        #expect(NavGrid.cellIndex(FloorPoint(u: 1.5, v: -1), size: 10) == 90)
    }

    @Test func hugeAndNaNCoordinatesDoNotTrap() {
        let all = NavGrid.footprintCells(Footprint(u0: -1e30, u1: 1e30, v0: -1e30, v1: 1e30), size: 10)
        #expect(Set(all) == Set(0..<100))
        #expect(NavGrid.cellIndex(FloorPoint(u: 1e300, v: -1e300), size: 10) == 90)
        #expect(NavGrid.cellIndex(FloorPoint(u: .nan, v: .nan), size: 10) == 0)
        #expect(NavGrid.footprintCells(Footprint(u0: .nan, u1: 0.5, v0: 0, v1: 1), size: 10).isEmpty)
    }

    /// Building.parse's grid gate: walkable is kept only for an integer size >= 1 with exactly that many full rows.
    @Test func gridGate() throws {
        let (building, catalogue, _) = try load("user")
        func floor(grid: Any?) throws -> Floor {
            var root = try #require(JSONSerialization.jsonObject(with: fixture("rooms/user/building.json")) as? [String: Any])
            var floors = try #require(root["floors"] as? [[String: Any]])
            if let grid { floors[0]["grid"] = grid } else { floors[0].removeValue(forKey: "grid") }
            root["floors"] = floors
            let data = try JSONSerialization.data(withJSONObject: root)
            let b = try #require(Building.parse(building: data, parts: fixture("rooms/user/room-parts.json")))
            return try #require(b.floors.first { $0.id == building.floors[0].id })
        }
        let row = String(repeating: "1", count: 4)
        let cases: [(String, Any?)] = [
            ("valid", ["size": 4, "walkable": [String](repeating: row, count: 4)]),
            ("short row", ["size": 4, "walkable": [row, row, "111", row]]),
            ("wrong row count", ["size": 4, "walkable": [row, row, row]]),
            ("fractional size", ["size": 4.5, "walkable": [String](repeating: row, count: 4)]),
            ("zero size", ["size": 0, "walkable": [String]()]),
            ("no walkable", ["size": 4]),
            ("no grid", nil),
            ("valid at the 512 cap", ["size": 512, "walkable": [String](repeating: String(repeating: "1", count: 512), count: 512)]),
            ("size over the 512 cap", ["size": 513, "walkable": [String](repeating: String(repeating: "1", count: 513), count: 513)]),
        ]
        let template = try #require(building.floors.first)
        let room = try #require(RoomGeometry.build(floor: template, catalogue: catalogue))
        for (name, grid) in cases {
            let f = try floor(grid: grid)
            let kept = f.walkable != nil   // a Bool, so a failure doesn't print 512 rows
            if name.hasPrefix("valid") { #expect(kept, "\(name)"); continue }
            #expect(!kept, "\(name)")
            // The room is built from the unmodified floor; the gate only reads the parsed floor's walkable.
            let built = NavGrid(floor: f, room: room) != nil
            #expect(!built, "\(name)")
        }
    }

    @Test(arguments: ["user", "edge"]) func routesMatchCatOffice(_ b: String) throws {
        let (building, catalogue, expected) = try load(b)
        var checked = 0
        for f in expected.floors {
            guard let nav = f.nav else { continue }
            let floor = try #require(building.floors.first { $0.id == f.id })
            let room = try #require(RoomGeometry.build(floor: floor, catalogue: catalogue))
            let grid = try #require(NavGrid(floor: floor, room: room))
            for r in nav.routes {
                let got = grid.findPath(from: FloorPoint(u: r.from.u, v: r.from.v), to: FloorPoint(u: r.to.u, v: r.to.v))
                guard let want = r.path else { #expect(got == nil, "floor \(f.id) \(r.from)→\(r.to) should be unreachable"); continue }
                let path = try #require(got, "floor \(f.id) \(r.from)→\(r.to) should be reachable")
                #expect(path.count == want.count, "floor \(f.id) \(r.from)→\(r.to): \(path.count) points, want \(want.count)")
                for (p, w) in zip(path, want) {
                    let a = room.frame.px(p), e = room.frame.px(FloorPoint(u: w.u, v: w.v))
                    #expect(hypot(a.x - e.x, a.y - e.y) <= 0.5, "floor \(f.id) \(r.from)→\(r.to)")
                }
                checked += 1
            }
        }
        #expect(checked > 20)
    }

    /// A 10×10 open floor with one blocked 2×6 wall in the middle (cells u 4…5, v 2…7).
    func walled() throws -> NavGrid {
        var open = [Bool](repeating: true, count: 100)
        for u in 4...5 { for v in 2...7 { open[u * 10 + v] = false } }
        let frame = try #require(FloorFrame(corners: FloorCorners(top: WorldPoint(x: 0, y: 0), left: WorldPoint(x: -200, y: 100),
                                                                bottom: WorldPoint(x: 0, y: 200), right: WorldPoint(x: 200, y: 100))))
        return NavGrid(size: 10, open: open, frame: frame)
    }

    @Test func routeGoesRoundAWallAlongTheAxes() throws {
        let g = try walled()
        let from = FloorPoint(u: 0.15, v: 0.45), to = FloorPoint(u: 0.85, v: 0.45)
        let path = try #require(g.findPath(from: from, to: to))
        #expect(path.last == to)
        var prev = from
        for p in path {
            // Every leg runs along u or along v.
            #expect(abs(p.u - prev.u) < 1e-9 || abs(p.v - prev.v) < 1e-9)
            // No point of any leg is in a blocked cell (sampled every 1/100).
            for i in 0...100 {
                let t = Double(i) / 100
                #expect(g.isOpenAt(FloorPoint(u: prev.u + (p.u - prev.u) * t, v: prev.v + (p.v - prev.v) * t)))
            }
            prev = p
        }
    }

    @Test func boxedInSpotIsUnreachable() throws {
        var open = [Bool](repeating: true, count: 100)
        for u in 3...5 { for v in 3...5 where !(u == 4 && v == 4) { open[u * 10 + v] = false } }   // a ring round (4,4)
        let frame = try #require(FloorFrame(corners: FloorCorners(top: WorldPoint(x: 0, y: 0), left: WorldPoint(x: -200, y: 100),
                                                                bottom: WorldPoint(x: 0, y: 200), right: WorldPoint(x: 200, y: 100))))
        let g = NavGrid(size: 10, open: open, frame: frame)
        #expect(g.findPath(from: FloorPoint(u: 0.05, v: 0.05), to: FloorPoint(u: 0.45, v: 0.45)) == nil)
    }

    @Test func aSeatOnFurnitureStepsOffAlongAnAxis() throws {
        let g = try walled()
        let seat = FloorPoint(u: 0.45, v: 0.25)          // inside the wall (blocked)
        let path = try #require(g.findPath(from: seat, to: FloorPoint(u: 0.15, v: 0.85)))
        let first = path[0]
        #expect(abs(first.u - seat.u) < 1e-9 || abs(first.v - seat.v) < 1e-9, "the hop off runs along an axis")
        #expect(g.isOpenAt(first))
    }
}

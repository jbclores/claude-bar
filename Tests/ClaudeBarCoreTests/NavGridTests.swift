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
}

import Foundation
import Testing
@testable import ClaudeBarCore

/// sim-expected.json `spots` / `spotCases`: every floor's spots as the browser walks them (buildRoomOffice), in order.
struct SpotsFixture: Decodable {
    struct P: Decodable { var u: Double; var v: Double }
    struct S: Decodable { var id: String; var kind: String; var pose: String?; var u: Double; var v: Double; var slots: [P] }
    struct FloorSpots: Decodable { var floor: Int; var spots: [S] }
    struct Case: Decodable {
        struct Add: Decodable { var floor: Int; var props: [PropPlacement]; var desks: [DeskPlacement] }
        var name: String
        var add: Add
        var spots: [S]
    }
    var spots: [FloorSpots]
    var spotCases: [Case]
}

@Suite struct WalkSpotsTests {
    let expected: SpotsFixture

    init() throws {
        expected = try JSONDecoder().decode(SpotsFixture.self, from: fixture("rooms/user/sim-expected.json"))
    }

    func building(adding add: SpotsFixture.Case.Add? = nil) throws -> Building {
        var data = try fixture("rooms/user/building.json")
        if let add {
            var root = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
            var floors = try #require(root["floors"] as? [[String: Any]])
            let i = try #require(floors.firstIndex { ($0["id"] as? NSNumber)?.intValue == add.floor })
            var room = try #require(floors[i]["room"] as? [String: Any])
            func json<T: Encodable>(_ x: [T]) throws -> [Any] { try x.map { try JSONSerialization.jsonObject(with: JSONEncoder().encode($0)) } }
            room["props"] = (room["props"] as? [Any] ?? []) + (try json(add.props))
            room["desks"] = (room["desks"] as? [Any] ?? []) + (try json(add.desks))
            floors[i]["room"] = room
            root["floors"] = floors
            data = try JSONSerialization.data(withJSONObject: root)
        }
        return try #require(Building.parse(building: data, parts: fixture("rooms/user/room-parts.json")))
    }

    func check(_ got: [RoomSpot], _ want: [SpotsFixture.S], _ label: String) {
        #expect(got.map(\.id) == want.map(\.id), "\(label): ids")
        for (g, w) in zip(got, want) where g.id == w.id {
            #expect(g.kind == w.kind && g.pose == w.pose, "\(label) \(w.id): kind/pose")
            #expect(abs(g.standAt.u - w.u) < 1e-9 && abs(g.standAt.v - w.v) < 1e-9, "\(label) \(w.id): standAt \(g.standAt) vs \(w.u),\(w.v)")
            #expect(g.slots.count == w.slots.count, "\(label) \(w.id): slots")
            for (a, b) in zip(g.slots, w.slots) {
                #expect(abs(a.u - b.u) < 1e-9 && abs(a.v - b.v) < 1e-9, "\(label) \(w.id): slot")
            }
        }
    }

    @Test func everyFloorKeepsTheBrowsersSpotsInOrder() throws {
        let b = try building()
        let catalogue = try RoomCatalogueTests().catalogue("user")
        #expect(expected.spots.count == b.floors.count)
        for f in expected.spots {
            let floor = try #require(b.floor(id: f.floor))
            let room = try #require(RoomGeometry.build(floor: floor, catalogue: catalogue))
            check(room.spots, f.spots, "floor \(f.floor)")
        }
    }

    /// closeSpots moves a spot off a trash bin and closes an optional spot a desk covers.
    @Test func closeSpotsCases() throws {
        let catalogue = try RoomCatalogueTests().catalogue("user")
        #expect(expected.spotCases.count == 2)
        for c in expected.spotCases {
            let floor = try #require(building(adding: c.add).floor(id: c.add.floor))
            let room = try #require(RoomGeometry.build(floor: floor, catalogue: catalogue))
            check(room.spots, c.spots, c.name)
        }
    }

    /// Seats are the lounge seats among the walked spots (a dropped spot is no seat), at their walked positions.
    @Test func seatsAreWalkedSpots() throws {
        let b = try building()
        let catalogue = try RoomCatalogueTests().catalogue("user")
        for floor in b.floors {
            guard let room = RoomGeometry.build(floor: floor, catalogue: catalogue) else { continue }
            for s in room.seats { #expect(room.spots.contains(s), "floor \(floor.id) seat \(s.id)") }
        }
    }
}

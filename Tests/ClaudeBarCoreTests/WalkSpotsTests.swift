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

    /// Seats are the lounge seats among the walked spots (a dropped spot is no seat), at their walked positions. Also
    /// on Lounge floors where closeSpots drops a seat (a trash bin or a desk over an optional one); a seat it moves
    /// would be seated where it is walked.
    @Test func seatsAreWalkedSpots() throws {
        let b = try building()
        let catalogue = try RoomCatalogueTests().catalogue("user")
        for floor in b.floors {
            guard let room = RoomGeometry.build(floor: floor, catalogue: catalogue) else { continue }
            for s in room.seats { #expect(room.spots.contains(s), "floor \(floor.id) seat \(s.id)") }
        }
        let loungeFloor = try #require(b.floor(id: 1))
        let lounge = try #require(RoomGeometry.build(floor: loungeFloor, catalogue: catalogue))
        var moved = 0, dropped = 0
        for seat in lounge.seats where seat.lift == 0 {
            // A placement's u, v is its footprint's far corner: these put the bin's and the desk's footprint over the seat.
            let at = seat.standAt
            let adds = [
                SpotsFixture.Case.Add(floor: 1, props: [try JSONDecoder().decode(PropPlacement.self, from: Data(#"{"id":"test-bin","prop":"trash-bin-pedal","u":\#(at.u + 0.01),"v":\#(at.v + 0.01),"facing":0}"#.utf8))], desks: []),
                SpotsFixture.Case.Add(floor: 1, props: [], desks: [try JSONDecoder().decode(DeskPlacement.self, from: Data(#"{"id":"test-desk","desk":"s1-walnut","u":\#(at.u + 0.04),"v":\#(at.v + 0.08),"flip":false}"#.utf8))]),
            ]
            for add in adds {
                let floor = try #require(building(adding: add).floor(id: 1))
                guard let room = RoomGeometry.build(floor: floor, catalogue: catalogue) else { continue }
                let walked = room.spots.first { $0.id == seat.id }
                if walked == nil { dropped += 1 } else if walked?.standAt != seat.standAt { moved += 1 }
                for s in room.seats { #expect(room.spots.contains(s), "\(add.props.isEmpty ? "desk" : "bin") on \(seat.id): seat \(s.id)") }
                if let walked, room.seats.contains(where: { $0.id == seat.id }) {
                    #expect(room.seats.first { $0.id == seat.id } == walked, "\(seat.id) seated where it is walked")
                } else if walked == nil {
                    #expect(!room.seats.contains { $0.id == seat.id }, "\(seat.id) dropped but still a seat")
                }
            }
        }
        // The cases above really dropped seats (every seat on the floor off furniture is an optional rug spot, which a
        // bin or desk over it closes; closeSpots moves only spots it doesn't close, so none moves here).
        #expect(dropped >= 6, "moved \(moved), dropped \(dropped)")
    }
}

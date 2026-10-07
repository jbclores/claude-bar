import Foundation
import Testing
@testable import ClaudeBarCore

@Suite struct RoomCatalogueTests {
    func catalogue(_ b: String = "user") throws -> RoomCatalogue {
        try #require(RoomCatalogue.parse(roomParts: fixture("rooms/\(b)/room-parts.json"), props: fixture("rooms/\(b)/props.json"),
                                         desks: fixture("rooms/\(b)/desks.json"), wallItemArt: fixture("rooms/\(b)/wall-item-art.json")))
    }

    @Test func parsesTheUsersCatalogues() throws {
        let c = try catalogue()
        #expect(c.desks["s1-walnut"]?.stand == SpotOffset(dx: -110, dy: -20))
        #expect(c.props["sofa"]?.spots?.filter { $0.pose == "sit" }.count == 3)
        #expect(c.wallItems["elevator"]?.plate != nil)
        #expect(c.wallItems["wall-tv"]?.art != nil, "art bounds merged from wall-item-art.json")
        #expect(c.floors["oak"]?.image == "assets/room/floors/oak.png")
    }

    @Test func wallHeightPerFloor() throws {
        let c = try catalogue()
        let b = try #require(Building.parse(building: fixture("rooms/user/building.json"), parts: fixture("rooms/user/room-parts.json")))
        #expect(c.wallHeight(floorId: 1, room: try #require(b.floor(id: 1)?.room)) == 432)
        #expect(c.wallHeight(floorId: 2, room: try #require(b.floor(id: 2)?.room)) == 399)
    }

    @Test func unknownIdsAreSkipped() throws {
        var props = try JSONSerialization.jsonObject(with: fixture("rooms/user/props.json")) as! [String: Any]
        var list = props["props"] as! [[String: Any]]
        list.append(["id": "hovercraft", "width": "not a number"])
        props["props"] = list
        let c = try #require(RoomCatalogue.parse(roomParts: fixture("rooms/user/room-parts.json"),
                                                 props: JSONSerialization.data(withJSONObject: props),
                                                 desks: fixture("rooms/user/desks.json"), wallItemArt: nil))
        #expect(c.props["hovercraft"] == nil && c.props["sofa"] != nil)
    }

    @Test func brokenRequiredFileGivesNil() throws {
        #expect(RoomCatalogue.parse(roomParts: Data("<html>".utf8), props: try fixture("rooms/user/props.json"),
                                    desks: try fixture("rooms/user/desks.json"), wallItemArt: nil) == nil)
    }

    @Test func floorsKeepCornersRoomAndDeskPositions() throws {
        let b = try #require(Building.parse(building: fixture("rooms/user/building.json"), parts: fixture("rooms/user/room-parts.json")))
        let f2 = try #require(b.floor(id: 2))
        #expect(f2.corners?.top == WorldPoint(x: 1375, y: 271))
        #expect(f2.room?.desks.count == 11 && f2.room?.wallItems.first?.wall == .left)
        #expect(f2.desks.first.map { ($0.u, $0.v) } ?? (0, 0) == (0.1178, 0.4328))
    }

    @Test func parsesTheEdgeCatalogues() throws {
        let c = try catalogue("edge")
        #expect(!c.props.isEmpty && !c.desks.isEmpty && !c.wallItems.isEmpty)
        let b = try #require(Building.parse(building: fixture("rooms/edge/building.json"), parts: fixture("rooms/edge/room-parts.json")))
        #expect(b.floors.contains { $0.room != nil })
    }
}

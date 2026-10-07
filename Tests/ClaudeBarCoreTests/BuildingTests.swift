// Tests/ClaudeBarCoreTests/BuildingTests.swift
import CoreGraphics
import Foundation
import Testing
@testable import ClaudeBarCore

@Suite struct BuildingTests {
    let buildingJSON = #"""
    {"floors":[
      {"id":1,"name":"Lounge","room":{"floor":"oak","wall":"plaster-lounge","desks":[],
        "wallItems":[{"id":"sign-lounge-1","item":"sign-lounge","wall":"right","at":0.25},{"id":"elevator-lounge-1","item":"elevator-lounge","wall":"left","at":0.5}]}},
      {"id":6,"name":"Desk pool","room":{"floor":"oak","wall":"plaster","desks":[{"id":"d1","desk":"s1-oak","u":0.1,"v":0.2,"flip":false}],
        "wallItems":[{"id":"e6","item":"elevator","wall":"left","at":0.5}]}},
      {"id":12,"name":"claude-bar","repo":{"root":"~/Documents/projects/claude-bar"},
        "room":{"floor":"slate","wall":"plaster","desks":[{"id":"f12-desk-1","desk":"s1-walnut","u":0.9,"v":0.1,"flip":true},{"id":"f12-desk-2","desk":"s3-mint","u":0.1,"v":0.3,"flip":false,"rear":true}],
        "wallItems":[{"id":"elevator-12","item":"elevator","wall":"left","at":0.5}]}}
    ]}
    """#
    let partsJSON = #"""
    {"floors":[{"id":"oak","image":"assets/room/floors/oak.png","tile":[1024,528],"color":"#e3a56c"},
               {"id":"slate","image":"assets/room/floors/slate.png","tile":[1024,528],"color":"#6b7280"}],
     "walls":[{"id":"plaster","image":"assets/room/walls/plaster.png","tile":[200,267],"color":"#fdeee0"},
              {"id":"plaster-lounge","image":"assets/room/walls/plaster-lounge.png","tile":[200,432],"color":"#fbe8dc"}],
     "wallItems":[{"id":"elevator","image":"assets/room/wall-items/elevator.png","width":262,"height":231,"plate":{"x":80,"y":10,"width":68,"height":21,"color":"#f4ece6"}},
                  {"id":"elevator-lounge","image":"assets/room/wall-items/elevator-lounge.png","width":256,"height":360,"plate":{"x":77,"y":19,"width":58,"height":23,"color":"#f4ece6"}},
                  {"id":"sign-lounge","image":"assets/room/wall-items/sign-lounge.png","width":195,"height":91}]}
    """#

    func building() throws -> Building {
        try #require(Building.parse(building: Data(buildingJSON.utf8), parts: Data(partsJSON.utf8)))
    }

    @Test func parsesFloorsInIdOrder() throws {
        let b = try building()
        #expect(b.floors.map(\.id) == [1, 6, 12])
        #expect(b.floors.map(\.name) == ["Lounge", "Desk pool", "claude-bar"])
    }

    @Test func projectFloorsCarryANormalizedRepoRoot() throws {
        let b = try building()
        #expect(b.floor(id: 12)?.repoRoot == Paths.normalize("~/Documents/projects/claude-bar"))
        #expect(b.floor(id: 1)?.repoRoot == nil)
    }

    @Test func texturesAndElevatorComeFromRoomParts() throws {
        let f = try #require(try building().floor(id: 12))
        #expect(f.floorTexture == RoomTexture(id: "slate", image: "assets/room/floors/slate.png", tile: CGSize(width: 1024, height: 528), color: "#6b7280"))
        #expect(f.wallTexture?.id == "plaster")
        #expect(f.elevator?.image == "assets/room/wall-items/elevator.png")
        #expect(f.elevator?.plate == CGRect(x: 80, y: 10, width: 68, height: 21))
        #expect(f.elevator?.plateColor == "#f4ece6")
    }

    @Test func desksKeepStoredOrderAndOrientation() throws {
        let f = try #require(try building().floor(id: 12))
        #expect(f.desks == [FloorDesk(id: "f12-desk-1", design: "s1-walnut", flip: true, rear: false),
                            FloorDesk(id: "f12-desk-2", design: "s3-mint", flip: false, rear: true)])
    }

    @Test func loungeAndDeskPoolAreFound() throws {
        let b = try building()
        #expect(b.lounge?.id == 1 && b.lounge?.isLounge == true && b.lounge?.hasLoungeSign == true)
        #expect(b.deskPool?.id == 6)
    }

    @Test func deskPoolFallsBackToTheFirstSharedFloorAfterTheLounge() throws {
        let json = #"{"floors":[{"id":1,"name":"Lounge","room":{}},{"id":2,"name":"Office","room":{}},{"id":4,"name":"x","repo":{"root":"/r"},"room":{}}]}"#
        let b = try #require(Building.parse(building: Data(json.utf8), parts: Data("{}".utf8)))
        #expect(b.deskPool?.id == 2)
    }

    @Test func brokenDataGivesNilAndTheFallbackIsOneLounge() {
        #expect(Building.parse(building: Data("nope".utf8), parts: Data("{}".utf8)) == nil)
        #expect(Building.fallback.floors.count == 1 && Building.fallback.floors[0].isLounge)
    }
}

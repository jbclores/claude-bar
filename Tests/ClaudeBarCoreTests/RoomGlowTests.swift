import CoreGraphics
import Foundation
import Testing
@testable import ClaudeBarCore

/// The lit copies Cat Office draws at night (RoomProps.tsx glow, RoomShell.tsx wall glow and DecorArt lit).
@Suite struct RoomGlowTests {
    @Test func catalogueKeepsTheLitArtAndMasks() throws {
        let c = try RoomCatalogueTests().catalogue()
        let lamp = try #require(c.props["arc-floor-lamp"])
        #expect(lamp.emissive == "assets/emissive/arc-floor-lamp.png")
        #expect(lamp.emissiveImage == "assets/room/light-props/arc-floor-lamp-on.png")
        #expect(c.props["fish-tank"]?.glowModes == ["night", "off", "ambient", "party"])
        let meow = try #require(c.wallItems["neon-meow"])
        #expect(meow.emissiveRight == "assets/emissive/neon-meow-right.png")
        #expect(meow.emissiveImageRight == "assets/room/light-props/neon-meow-right-on.png")
        #expect(c.wallItems["window-string-lights-colour"]?.decor?.glowModes == ["night", "off", "ambient", "party"])
    }

    @Test func aLampGlowsAtNightOnly() throws {
        let r = try BuiltRoomTests().built(1)
        let lamp = try #require(r.props.first { $0.id == "paper-lantern-lamp-1-1" })
        #expect(lamp.glow == RoomGlow(image: "assets/room/light-props/paper-lantern-lamp-on.png",
                                      mask: "assets/emissive/paper-lantern-lamp.png", modes: nil))
        #expect(lamp.glow?.lit(night: true) == true && lamp.glow?.lit(night: false) == false)
        // Unlit furniture has none.
        #expect(r.props.first { $0.id == "sofa" }?.glow == nil)
    }

    @Test func glowModesDecideTheNight() {
        #expect(RoomGlow(image: "a", mask: "m", modes: ["night", "party"]).lit(night: true))
        #expect(!RoomGlow(image: "a", mask: "m", modes: ["panic"]).lit(night: true))
        #expect(!RoomGlow(image: "a", mask: "m", modes: ["party"]).lit(night: true))
    }

    @Test func mirroredAquariumGlowsInItsModes() throws {
        let r = try BuiltRoomTests().built(2)
        let tank = try #require(r.props.first { $0.id == "aquarium-long-2-1" })
        #expect(tank.mirrored)
        #expect(tank.glow?.image == "assets/room/light-props/aquarium-long-on.png")
        #expect(tank.glow?.lit(night: true) == true)
    }

    @Test func wallTvFixtureGlows() throws {
        let r = try BuiltRoomTests().built(7)
        let tv = try #require(r.fixtures.first { $0.id == "wall-tv-7-1" })
        #expect(tv.glow == RoomGlow(image: "assets/room/conference/wall-tv-on.png", mask: "assets/room/conference/wall-tv-mask.png", modes: nil))
    }

    @Test func wallLightAndWindowDecorGlowOverTheirArt() throws {
        let c = try RoomCatalogueTests().catalogue()
        let frame = try #require(FloorFrame(corners: try expected("user").floors[1].corners))
        func place(_ item: String, _ wall: WallSide) throws -> PlacedWallItem {
            let w = WallItemPlacement(id: "w", item: item, wall: wall, at: 0.5, width: nil, height: nil, bottom: nil, up: nil, transom: nil)
            return try #require(WallItems.place(w, frame: frame, catalogue: c, wallHeight: 399))
        }
        // A neon sign on the wall: lit over its whole box; the right wall's own art there.
        let neon = try place("neon-meow", .right)
        #expect(neon.glows == [GlowPiece(glow: RoomGlow(image: "assets/room/light-props/neon-meow-right-on.png",
                                                         mask: "assets/emissive/neon-meow-right.png",
                                                         modes: ["night", "off", "ambient", "party"]),
                                         rect: CGRect(x: 0, y: 0, width: neon.box.width, height: neon.box.height))])
        // A window's lantern: lit where its unlit art hangs.
        let lantern = try place("window-star-lantern", .left)
        #expect(lantern.glows == [GlowPiece(glow: RoomGlow(image: "assets/room/light-props/star-lantern-on.png",
                                                            mask: "assets/emissive/star-lantern.png", modes: nil),
                                            rect: CGRect(x: 48, y: 17, width: 53, height: 61))])
        // A plain window has none.
        #expect(try place("window-lounge-full", .left).glows.isEmpty)
    }
}

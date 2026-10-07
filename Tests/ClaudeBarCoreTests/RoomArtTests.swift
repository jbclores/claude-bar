import CoreGraphics
import Foundation
import Testing
@testable import ClaudeBarCore

/// What a room's picture needs loaded, and when the picture can be kept.
@Suite struct RoomArtTests {
    @Test func everyPictureTheRoomDraws() throws {
        let r = try BuiltRoomTests().built(1)
        let day = RoomArt.paths(r, night: false)
        let paths = Set(day.map(\.path))
        for d in r.desks { #expect(paths.contains(d.image)) }
        for p in r.props { if let i = p.image { #expect(paths.contains(i)) } }
        for f in r.fixtures { if let i = f.image { #expect(paths.contains(i)) } }
        if let t = r.floorTexture { #expect(paths.contains(t.image)) }
        // The plaster is sliced: loaded at its own size.
        if let w = r.wallTexture { #expect(day.first { $0.path == w.image }?.natural == true) }
        // Each path once.
        #expect(paths.count == day.count)
        // Lit art only at night.
        #expect(!paths.contains("assets/room/light-props/paper-lantern-lamp-on.png"))
        let night = Set(RoomArt.paths(r, night: true).map(\.path))
        #expect(night.contains("assets/room/light-props/paper-lantern-lamp-on.png") && night.contains("assets/emissive/paper-lantern-lamp.png"))
        #expect(night.isSuperset(of: paths))
    }

    @Test func aPictureIsKeptOnlyWithEveryPictureLoaded() {
        let needed = ["desk.png", "sofa.png", "floor.png"]
        #expect(RoomArt.missing(needed, loaded: ["desk.png", "floor.png"]) == ["sofa.png"])
        #expect(!RoomArt.complete(needed, loaded: ["desk.png", "floor.png"]))
        #expect(RoomArt.complete(needed, loaded: ["desk.png", "sofa.png", "floor.png", "extra.png"]))
        #expect(RoomArt.complete([], loaded: []))
    }
}

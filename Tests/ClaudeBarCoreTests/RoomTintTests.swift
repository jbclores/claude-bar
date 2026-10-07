import CoreGraphics
import Foundation
import Testing
@testable import ClaudeBarCore

/// room-tint.ts: a room's wall and floor paint.
@Suite struct RoomTintTests {
    func close(_ a: [Double], _ b: [Double], _ tol: Double = 6e-5) -> Bool {
        a.count == b.count && zip(a, b).allSatisfy { abs($0 - $1) <= tol }
    }

    @Test func normalTintAcceptsOnlyHexColours() {
        #expect(RoomTint.normal("#CFE0EC") == "#cfe0ec")
        #expect(RoomTint.normal("#cfe0e") == nil)
        #expect(RoomTint.normal("cfe0ec") == nil)
        #expect(RoomTint.normal(nil) == nil)
    }

    @Test func lumaAndRgb() {
        let c = RoomTint.rgb("#cfe0ec")
        #expect(close([c.0, c.1, c.2], [207.0 / 255, 224.0 / 255, 236.0 / 255], 1e-12))
        #expect(abs(RoomTint.luma("#ffffff") - 1) < 1e-12)
        #expect(abs(RoomTint.luma("#cfe0ec") - (0.2126 * 207 + 0.7152 * 224 + 0.0722 * 236) / 255) < 1e-12)
    }

    @Test func tintMatrixMatchesCatOffice() {
        // tintMatrix('#cfe0ec', 0.8) in Cat Office: "0.2157 0.7257 0.0733 0 0  0.2334 0.7853 0.0793 0 0  0.2459 0.8274 0.0835 0 0  0 0 0 1 0"
        #expect(close(RoomTint.tintMatrix("#cfe0ec", base: 0.8),
                      [0.2157, 0.7257, 0.0733, 0, 0, 0.2334, 0.7853, 0.0793, 0, 0, 0.2459, 0.8274, 0.0835, 0, 0, 0, 0, 0, 1, 0]))
        // A base under 0.05 counts as 0.05.
        #expect(close(RoomTint.tintMatrix("#cfe0ec", base: 0.01),
                      [3.4516, 11.6115, 1.1722, 0, 0, 3.7351, 12.5651, 1.2685, 0, 0, 3.9352, 13.2382, 1.3364, 0, 0, 0, 0, 0, 1, 0]))
    }

    @Test func inkMatrixMatchesCatOffice() {
        // "1 0 0 0 0  0 1 0 0 0  0 0 1 0 0  -1.6354 -5.5015 -0.5554 0 2.5385"
        #expect(close(RoomTint.inkMatrix(), [1, 0, 0, 0, 0, 0, 1, 0, 0, 0, 0, 0, 1, 0, 0, -1.6354, -5.5015, -0.5554, 0, 2.5385]))
    }

    @Test func textureLumaSkipsInkAndClearPixels() {
        // white, mid grey, ink (black), a clear pixel.
        let bytes: [UInt8] = [255, 255, 255, 255, 128, 128, 128, 255, 0, 0, 0, 255, 255, 255, 255, 0]
        let l = try! #require(RoomTint.textureLuma(bytes))
        #expect(abs(l - (1 + 128.0 / 255) / 2) < 1e-9)
        #expect(RoomTint.textureLuma([0, 0, 0, 255]) == nil)
    }

    @Test func paintTurnsTheBodyIntoTheTintAndKeepsInk() {
        let base = 0.8
        let m = RoomTint.tintMatrix("#cfe0ec", base: base)
        // A pixel as light as the texture's body comes out as the paint.
        let grey = base
        let body = RoomTint.paint((grey, grey, grey, 1), matrix: m)
        #expect(close([body.0, body.1, body.2, body.3], [207.0 / 255, 224.0 / 255, 236.0 / 255, 1], 1e-3))
        // Ink keeps its own colour.
        let ink = RoomTint.paint((0.05, 0.02, 0.01, 1), matrix: m)
        #expect(close([ink.0, ink.1, ink.2, ink.3], [0.05, 0.02, 0.01, 1], 1e-9))
        // Lighter grain stays lighter (clamped to 1).
        let light = RoomTint.paint((1, 1, 1, 1), matrix: m)
        #expect(light.0 > body.0 && light.2 <= 1)
        // Clear stays clear.
        #expect(RoomTint.paint((1, 1, 1, 0), matrix: m).3 == 0)
    }

    @Test func roomCarriesItsPaint() throws {
        let b = try #require(Building.parse(building: fixture("rooms/user/building.json"), parts: fixture("rooms/user/room-parts.json")))
        #expect(b.floor(id: 7)?.room?.wallTint == "#cfe0ec")
        #expect(b.floor(id: 7)?.room?.floorTint == nil)
        let seven = try BuiltRoomTests().built(7)
        #expect(seven.wallTint == "#cfe0ec" && seven.floorTint == nil)
        #expect(try BuiltRoomTests().built(1).wallTint == nil)
    }
}

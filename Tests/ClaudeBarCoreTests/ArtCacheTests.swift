import CoreGraphics
import Foundation
import ImageIO
import Testing
@testable import ClaudeBarCore

@Suite struct ArtCacheTests {
    // Expected values computed with Cat Office's own portraitCat (src/agents/live/cat-assignment.ts) in node.
    @Test func fnvMatchesCatOffice() {
        #expect(CatPicker.fnv1a("") == 2_166_136_261)
        #expect(CatPicker.fnv1a("a08f04cc-0480-45f8-bae0-71a2aa333a5a") == 2_017_415_928)
        #expect(CatPicker.fnv1a("office-82eb65") == 4_008_419_252)
        #expect(CatPicker.fnv1a("café😺") == 1_986_295_627)
    }

    @Test func picksAssignedCatElseHash() {
        let ids = (0..<18).map { "cat\($0)" }
        #expect(CatPicker.portraitCat("office-82eb65", catIds: ids) == "cat8")
        let agent = OfficeAgent(id: "office-82eb65", name: "x", status: .idle, cwd: "/")
        #expect(CatPicker.cat(for: agent, catIds: ids) == "cat8")
        var assigned = agent
        assigned.cat = "tuxedo"
        #expect(CatPicker.cat(for: assigned, catIds: ids) == "tuxedo")
        #expect(CatPicker.portraitCat("x", catIds: []) == "")
    }

    @Test func catalogPathsPerPose() throws {
        let json = """
        {"path":"assets/cats/{cat}/{direction}/{gesture}.png","sleepPath":"assets/cats/{cat}/sleep.png",
         "typePath":"assets/cats/{cat}/{direction}/type.png","cats":[{"id":"orange"},{"id":"gray"}]}
        """
        let c = try #require(CatCatalog.parse(Data(json.utf8)))
        #expect(c.catIds == ["orange", "gray"])
        #expect(c.path(cat: "gray", pose: .typing) == "assets/cats/gray/back-left/type.png")
        #expect(c.path(cat: "gray", pose: .waving) == "assets/cats/gray/front-left/right-up.png")
        #expect(c.path(cat: "gray", pose: .sleeping) == "assets/cats/gray/sleep.png")
        #expect(CatPose(status: .working) == .typing)
        #expect(CatPose(status: .waiting) == .waving)
        #expect(CatPose(status: .idle) == .sleeping)
    }

    @Test func shrinksImages() throws {
        let png = try #require(Self.png(width: 360, height: 380))
        let small = try #require(ArtCache.shrink(png, maxPixelSize: 128))
        let source = try #require(CGImageSourceCreateWithData(small as CFData, nil))
        let image = try #require(CGImageSourceCreateImageAtIndex(source, 0, nil))
        #expect(max(image.width, image.height) == 128)
    }

    @Test func servesFromDiskCacheWithoutNetwork() async {
        let dir = makeTempDir()
        write("cached-bytes", to: dir.appendingPathComponent("assets_cats_orange_sleep.png"))
        let cache = ArtCache(dir: dir, baseURL: { URL(string: "http://localhost:1")! })
        let data = await cache.image(path: "assets/cats/orange/sleep.png")
        #expect(data == Data("cached-bytes".utf8))
        #expect(await cache.image(path: "assets/missing.png") == nil)
    }

    static func png(width: Int, height: Int) -> Data? {
        guard let ctx = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue),
              let image = ctx.makeImage() else { return nil }
        let out = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(out, "public.png" as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(dest, image, nil)
        return CGImageDestinationFinalize(dest) ? out as Data : nil
    }
}

@Suite struct PeekLayoutTests {
    func a(_ name: String, _ status: AgentStatus) -> OfficeAgent {
        OfficeAgent(id: name, name: name, status: status, cwd: "/")
    }

    @Test func desksForBusyLoungeForIdleSorted() {
        let layout = PeekLayout.make([a("b", .working), a("a", .waiting), a("z", .idle), a("e", .ended), a("c", .idle)])
        #expect(layout.desks.map(\.name) == ["a", "b"])
        #expect(layout.lounge.map(\.name) == ["c", "z"])
        #expect(layout.deskOverflow == 0 && layout.loungeOverflow == 0)
    }

    @Test func overflow() {
        let busy = (1...8).map { a("w\($0)", .working) }
        let idle = (1...5).map { a("i\($0)", .idle) }
        let layout = PeekLayout.make(busy + idle)
        #expect(layout.desks.count == 6 && layout.deskOverflow == 2)
        #expect(layout.lounge.count == 3 && layout.loungeOverflow == 2)
    }

    @Test func motion() {
        #expect(CatMotion.at(status: .waiting, time: 1.23) == CatMotion(offsetY: 0, scale: 1))
        let typing = CatMotion.at(status: .working, time: 0.35 / 4)
        #expect(abs(typing.offsetY - (-1.5)) < 0.01)
        #expect(CatMotion.at(status: .idle, time: 4.8 / 4).scale > 1.02)
    }
}

@Suite struct ArtCacheLiveTests {
    @Test(.enabled(if: ProcessInfo.processInfo.environment["CLAUDEBAR_LIVE"] == "1"))
    func loadsRealSpritesFromCatOffice() async throws {
        let dir = makeTempDir()
        let cache = ArtCache(dir: dir, baseURL: { CatOfficeSettings.defaultURL })
        let catalog = try #require(await cache.catalog())
        #expect(catalog.catIds.count >= 18)
        for pose in [CatPose.typing, .waving, .sleeping] {
            let data = try #require(await cache.catImage(cat: catalog.catIds[0], pose: pose))
            #expect(data.count > 500)
        }
        #expect(await cache.deskImage() != nil)
        print("cached:", (try? FileManager.default.contentsOfDirectory(atPath: dir.path).sorted()) ?? [])
    }
}

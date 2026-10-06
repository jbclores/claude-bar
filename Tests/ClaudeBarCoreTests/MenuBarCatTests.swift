import CoreGraphics
import Foundation
import ImageIO
import Testing
@testable import ClaudeBarCore

@Suite struct MenuBarCatTests {
    let t = Date(timeIntervalSince1970: 1_791_266_000)
    let ids = ["orange", "gray", "tuxedo"]

    func a(_ id: String, _ status: AgentStatus, cat: String? = nil, waitingSince: Date? = nil) -> OfficeAgent {
        OfficeAgent(id: id, name: id, status: status, cwd: "/", waitingSince: waitingSince, cat: cat)
    }

    @Test func needsYouBeatsWorkingBeatsIdle() {
        let agents = [a("idle1", .idle, cat: "orange"), a("work1", .working, cat: "gray"), a("wait1", .waiting, cat: "tuxedo")]
        #expect(MenuBarCat.pick(agents: agents, attention: [], catIds: ids)
                == MenuBarCat(agentId: "wait1", cat: "tuxedo", pose: .waving))
        #expect(MenuBarCat.pick(agents: Array(agents.prefix(2)), attention: [], catIds: ids)
                == MenuBarCat(agentId: "work1", cat: "gray", pose: .typing))
        #expect(MenuBarCat.pick(agents: [agents[0]], attention: [], catIds: ids)
                == MenuBarCat(agentId: "idle1", cat: "orange", pose: .sleeping))
    }

    @Test func finishedIdleAgentWithAttentionWaves() {
        let agents = [a("done", .idle, cat: "orange"), a("work", .working, cat: "gray")]
        #expect(MenuBarCat.pick(agents: agents, attention: ["done"], catIds: ids)?.agentId == "done")
        #expect(MenuBarCat.pick(agents: agents, attention: ["done"], catIds: ids)?.pose == .waving)
    }

    @Test func endedAgentsAndNoAgentsGiveNothing() {
        #expect(MenuBarCat.pick(agents: [a("x", .ended)], attention: [], catIds: ids) == nil)
        #expect(MenuBarCat.pick(agents: [], attention: [], catIds: ids) == nil)
    }

    @Test func keepsTheCurrentCatWhileItStillQualifies() {
        let agents = [a("w1", .working, cat: "orange"), a("w2", .working, cat: "gray")]
        let since = ["w1": t, "w2": t + 60]
        #expect(MenuBarCat.pick(agents: agents, attention: [], catIds: ids, since: since)?.agentId == "w2", "newest change first")
        #expect(MenuBarCat.pick(agents: agents, attention: [], catIds: ids, since: since, current: "w1")?.agentId == "w1", "no jumping")
        let waiting = agents + [a("w3", .waiting, cat: "tuxedo")]
        #expect(MenuBarCat.pick(agents: waiting, attention: [], catIds: ids, since: since, current: "w1")?.agentId == "w3", "more urgent wins")
    }

    @Test func waitingTiesUseWaitingSinceThenName() {
        let agents = [a("b", .waiting, waitingSince: t), a("a", .waiting, waitingSince: t + 5), a("c", .waiting, waitingSince: t + 5)]
        #expect(MenuBarCat.pick(agents: agents, attention: [], catIds: ids)?.agentId == "a")
    }

    @Test func fallsBackToCatOfficesFaceWithoutAnAssignedCat() {
        let pick = MenuBarCat.pick(agents: [a("office-82eb65", .working)], attention: [], catIds: ids)
        #expect(pick?.cat == CatPicker.portraitCat("office-82eb65", catIds: ids))
    }

    @Test func trimsTransparentEdges() throws {
        let ctx = try #require(CGContext(data: nil, width: 100, height: 80, bitsPerComponent: 8, bytesPerRow: 0,
                                         space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        ctx.setFillColor(CGColor(red: 1, green: 0, blue: 0, alpha: 1))
        ctx.fill(CGRect(x: 20, y: 10, width: 30, height: 40))
        let out = NSMutableData()
        let dest = try #require(CGImageDestinationCreateWithData(out, "public.png" as CFString, 1, nil))
        let drawn = try #require(ctx.makeImage())
        CGImageDestinationAddImage(dest, drawn, nil)
        #expect(CGImageDestinationFinalize(dest))
        let trimmed = try #require(ArtCache.trimmed(out as Data))
        let source = try #require(CGImageSourceCreateWithData(trimmed as CFData, nil))
        let image = try #require(CGImageSourceCreateImageAtIndex(source, 0, nil))
        #expect(image.width == 30 && image.height == 40)
        #expect(ArtCache.trimmed(Data("not an image".utf8)) == nil)
    }
}

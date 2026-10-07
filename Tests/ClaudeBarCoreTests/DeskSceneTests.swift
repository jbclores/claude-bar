import Foundation
import Testing
@testable import ClaudeBarCore

@Suite struct DeskSceneTests {
    func agent(_ status: AgentStatus, desk: AgentDesk?) -> OfficeAgent {
        var a = OfficeAgent(id: "a", name: "a", status: status, cwd: "/")
        a.desk = desk
        return a
    }

    @Test func decodesTheReportedDesk() throws {
        let json = #"{"type":"snapshot","snapshot":{"agents":[{"id":"x","status":"working","cwd":"/","desk":{"id":"s2-pink","flip":true,"rear":false}}]}}"#
        guard case .snapshot(let snap)? = CatOfficeEvent.decode(json) else { Issue.record("no snapshot"); return }
        #expect(snap.agents[0].desk == AgentDesk(id: "s2-pink", flip: true, rear: false))
    }

    @Test func catFacesItsDeskLikeCatOffice() {
        // Front-view desk: back to us, facing back-right (back-left when mirrored).
        #expect(DeskScene(agent(.working, desk: AgentDesk(id: "s1-oak", flip: false, rear: false)))
                == DeskScene(deskId: "s1-oak", mirrored: false, rear: false, pose: .typing, direction: "back-right"))
        #expect(DeskScene(agent(.working, desk: AgentDesk(id: "s1-oak", flip: true, rear: false))).direction == "back-left")
        // Turned desk: the cat works on the far side, facing us (front-right when mirrored), standing.
        let rear = DeskScene(agent(.working, desk: AgentDesk(id: "s3-gamer", flip: true, rear: true)))
        #expect(rear.pose == .standing && rear.direction == "front-right" && rear.rear && rear.mirrored)
        // Waiting: turned to us with a paw up.
        let waiting = DeskScene(agent(.waiting, desk: AgentDesk(id: "s1-oak", flip: false, rear: false)))
        #expect(waiting.pose == .waving && waiting.direction == "front-left")
    }

    @Test func withoutAReportedDeskKeepsTheDefault() {
        let scene = DeskScene(agent(.working, desk: nil))
        #expect(scene.deskId == nil && !scene.mirrored && !scene.rear)
        #expect(scene.pose == .typing && scene.direction == "back-right", "the default desk, unmirrored")
    }

    @Test func catalogPathsForDirectionsAndDesks() throws {
        let cats = try #require(CatCatalog.parse(Data(#"{"path":"assets/cats/{cat}/{direction}/{gesture}.png","typePath":"assets/cats/{cat}/{direction}/type.png","sleepPath":"assets/cats/{cat}/sleep.png","cats":[{"id":"gray"}]}"#.utf8)))
        #expect(cats.path(cat: "gray", pose: .typing, direction: "back-right") == "assets/cats/gray/back-right/type.png")
        #expect(cats.path(cat: "gray", pose: .standing, direction: "front-right") == "assets/cats/gray/front-right/both-down.png")
        #expect(cats.path(cat: "gray", pose: .typing) == "assets/cats/gray/back-left/type.png")
        let desks = DeskCatalog.parse(Data(#"{"desks":[{"id":"s1-walnut","image":"assets/desk-sprites/s1-walnut.png","rear":{"image":"assets/desk-sprites/s1-walnut-rear.png"}},{"id":"s2-pink","image":"assets/desk-sprites/s2-pink.png"}]}"#.utf8))
        #expect(desks.image(for: "s1-walnut", rear: true) == "assets/desk-sprites/s1-walnut-rear.png")
        #expect(desks.image(for: "s2-pink", rear: true) == "assets/desk-sprites/s2-pink.png", "no rear view: the front one")
        #expect(desks.image(for: nil, rear: false) == "assets/desk-sprites/s1-walnut.png", "default: the first desk")
        #expect(desks.image(for: "unknown", rear: false) == "assets/desk-sprites/s1-walnut.png")
    }
}

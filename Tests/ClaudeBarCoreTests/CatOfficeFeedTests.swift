import Foundation
import Testing
@testable import ClaudeBarCore

@Suite struct CatOfficeFeedTests {
    func feed(_ text: String) -> [String] {
        var parser = SSEParser()
        return Array(text.utf8).compactMap { parser.feed($0) }
    }

    @Test func parsesEventsAcrossChunksAndMultipleDataLines() {
        #expect(feed("data: {\"a\":1}\n\ndata: one\ndata: two\n\n") == ["{\"a\":1}", "one\ntwo"])
    }

    @Test func handlesCRLFCommentsAndBlankEvents() {
        #expect(feed(": hello\r\n\r\n\r\ndata:x\r\n\r\nevent: ping\n\n") == ["x"])
    }

    @Test func incompleteEventWaits() {
        #expect(feed("data: partial\n").isEmpty)
    }

    @Test func decodesSnapshotEvent() throws {
        let json = """
        {"type":"snapshot","snapshot":{"at":1,"repos":[],"claude":{"hindered":true,"reason":"x"},"agents":[
          {"id":"a1","name":"office-82eb65","pid":1,"owner":"office","status":"waiting","waitReason":"input needed",
           "cwd":"/Users/me","repo":{"root":"/w/app","name":"app"},"branch":"main","task":"design spec",
           "lastAction":{"at":5,"label":"Edit a.ts"},"model":"claude-opus-5-5","sessionId":"s1",
           "waitingSince":1791266000000,"log":[],"tokens":{},"chat":null,"cat":"tuxedo"},
          {"id":"a2","status":"something-new","cwd":"/w"}]}}
        """
        guard case .snapshot(let snap)? = CatOfficeEvent.decode(json) else { Issue.record("no snapshot"); return }
        #expect(snap.claudeHindered)
        let a = snap.agents[0]
        #expect(a.name == "office-82eb65" && a.isOffice && a.status == .waiting)
        #expect(a.waitReason == "input needed" && a.repoName == "app" && a.branch == "main")
        #expect(a.repoRoot == Paths.normalize("/w/app"))
        #expect(a.lastAction == "Edit a.ts" && a.model == "claude-opus-5-5" && a.key == "s1" && a.cat == "tuxedo")
        #expect(a.waitingSince == Date(timeIntervalSince1970: 1_791_266_000))
        #expect(snap.agents[1].status == .idle && snap.agents[1].name == "a2" && snap.agents[1].key == "a2")
    }

    @Test func otherEventsAndGarbage() {
        #expect(CatOfficeEvent.decode(#"{"type":"ping","at":1}"#) == .other)
        #expect(CatOfficeEvent.decode("nope") == nil)
    }

    @Test func tokenFromPage() {
        let html = #"<head><script>window.__CAT_OFFICE_TOKEN__ = "f9a0a4beef";</script></head>"#
        #expect(CatOfficeDiscovery.token(inPage: html) == "f9a0a4beef")
        #expect(CatOfficeDiscovery.token(inPage: "<html></html>") == nil)
    }

    @Test func bridgeFileNeedsLiveProcess() {
        let file = makeTempDir().appendingPathComponent(".cat-office/bridge.json")
        write(#"{"url":"http://localhost:5174","token":"tok","dir":"/w/cat-office","pid":42}"#, to: file)
        #expect(CatOfficeDiscovery.bridgeInfo(file: file, isAlive: { $0 == 42 })
                == BridgeInfo(url: URL(string: "http://localhost:5174")!, token: "tok", dir: "/w/cat-office"))
        #expect(CatOfficeDiscovery.bridgeInfo(file: file, isAlive: { _ in false }) == nil)
        #expect(CatOfficeDiscovery.bridgeInfo(file: file.deletingLastPathComponent().appendingPathComponent("none.json"), isAlive: { _ in true }) == nil)
    }

    @Test func folderToStartPrefersConfigThenRemembered() {
        let configured = makeTempDir().path
        let remembered = makeTempDir().path
        #expect(CatOfficeDiscovery.folderToStart(configured: configured, remembered: remembered) == configured)
        #expect(CatOfficeDiscovery.folderToStart(configured: "/gone-\(UUID())", remembered: remembered) == remembered)
        #expect(CatOfficeDiscovery.folderToStart(configured: nil, remembered: remembered) == remembered)
        #expect(CatOfficeDiscovery.folderToStart(configured: nil, remembered: "/gone-\(UUID())") == nil)
    }
}

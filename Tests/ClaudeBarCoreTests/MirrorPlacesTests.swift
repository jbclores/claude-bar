import Foundation
import Testing
@testable import ClaudeBarCore

@Suite struct MirrorPlacesTests {
    func placeJSON(state: String = "working", gesture: String = "none", asleep: Bool = false, kind: String? = "desk",
                   u: String = "3.5", v: String = "4.25", extra: String = "") -> String {
        let activity = kind.map { #"{"kind":"\#($0)","label":"Working"}"# } ?? "null"
        return """
        {"floor":1,"u":\(u),"v":\(v),"direction":"down-right","state":"\(state)","gesture":"\(gesture)","expression":"happy",
         "asleep":\(asleep),"activity":\(activity),"spotId":"desk-3","minutesLeft":7.5,"phase":"using","ridingTo":null,
         "catId":"tuxedo","at":1791266000000\(extra)}
        """
    }

    func decode(_ json: String) throws -> MirrorPlace {
        try JSONDecoder().decode(MirrorPlace.self, from: Data(json.utf8))
    }

    func snapshot(_ extra: String) throws -> OfficeSnapshot {
        let json = """
        {"agents":[{"id":"a1","name":"office-1","status":"working","cwd":"/w","cat":"tuxedo"\(extra)}]}
        """
        return try JSONDecoder().decode(OfficeSnapshot.self, from: Data(json.utf8))
    }

    @Test func decodesAPlace() throws {
        let p = try decode(placeJSON(extra: #","name":"Mochi","key":"spare:x""#))
        #expect(p.floor == 1 && p.u == 3.5 && p.v == 4.25 && p.direction == "down-right")
        #expect(p.state == "working" && p.expression == "happy" && !p.asleep)
        #expect(p.activity == MirrorPlace.Activity(kind: "desk", label: "Working"))
        #expect(p.spotId == "desk-3" && p.minutesLeft == 7.5 && p.phase == "using" && p.ridingTo == nil)
        #expect(p.catId == "tuxedo" && p.at == 1_791_266_000_000 && p.name == "Mochi" && p.key == "spare:x")
    }

    @Test func nullActivityAndMissingOptionals() throws {
        let p = try decode(placeJSON(kind: nil))
        #expect(p.activity == nil && p.name == nil && p.key == nil)
    }

    @Test func oldPatchSnapshotHasNoPlaces() throws {
        let s = try snapshot("")
        #expect(s.spares.isEmpty && s.placesAt == nil && s.agents[0].place == nil)
        #expect(s.agents[0].name == "office-1" && s.agents[0].cat == "tuxedo")
    }

    @Test func emptyPlacesSnapshotIsNotLive() throws {
        let json = #"{"agents":[{"id":"a1","status":"idle","cwd":"/w","place":null}],"spares":[],"placesAt":null}"#
        let s = try JSONDecoder().decode(OfficeSnapshot.self, from: Data(json.utf8))
        #expect(s.agents[0].place == nil && s.spares.isEmpty && s.placesAt == nil)
        #expect(!MirrorPlaces.isLive(placesAt: s.placesAt, now: Date()))
    }

    @Test func snapshotWithPlaces() throws {
        let json = """
        {"agents":[{"id":"a1","status":"working","cwd":"/w","place":\(placeJSON())}],
         "spares":[\(placeJSON(extra: #","key":"spare:s1","name":"Pip""#))],"placesAt":1791266000000}
        """
        let s = try JSONDecoder().decode(OfficeSnapshot.self, from: Data(json.utf8))
        #expect(s.agents[0].place?.u == 3.5)
        #expect(s.spares.count == 1 && s.spares[0].key == "spare:s1" && s.spares[0].name == "Pip")
        #expect(s.placesAt == 1_791_266_000_000)
    }

    @Test func badPlaceDoesNotBreakTheAgentOrSnapshot() throws {
        let json = """
        {"agents":[{"id":"a1","status":"working","cwd":"/w","place":{"floor":"x"}}],
         "spares":[{"nonsense":1},\(placeJSON(extra: #","key":"spare:ok""#))],"placesAt":"soon"}
        """
        let s = try JSONDecoder().decode(OfficeSnapshot.self, from: Data(json.utf8))
        #expect(s.agents[0].place == nil && s.agents[0].id == "a1")
        #expect(s.spares.map(\.key) == ["spare:ok"])
        #expect(s.placesAt == nil)
    }

    @Test func nonFiniteUVRejected() {
        #expect(throws: (any Error).self) { try decode(placeJSON(u: "1e999")) }
        let d = JSONDecoder()
        d.nonConformingFloatDecodingStrategy = .convertFromString(positiveInfinity: "inf", negativeInfinity: "-inf", nan: "nan")
        #expect(throws: (any Error).self) { try d.decode(MirrorPlace.self, from: Data(placeJSON(u: #""nan""#).utf8)) }
        #expect(throws: (any Error).self) { try d.decode(MirrorPlace.self, from: Data(placeJSON(v: #""inf""#).utf8)) }
    }

    // MARK: live

    let now = Date(timeIntervalSince1970: 1_791_266_100)
    func ms(_ secondsAgo: Double) -> Double { (now.timeIntervalSince1970 - secondsAgo) * 1000 }

    @Test func liveWindow() {
        #expect(MirrorPlaces.liveFor == 10)
        #expect(MirrorPlaces.isLive(placesAt: ms(9.9), now: now))
        #expect(!MirrorPlaces.isLive(placesAt: ms(10.1), now: now))
        #expect(!MirrorPlaces.isLive(placesAt: nil, now: now))
        #expect(!MirrorPlaces.isLive(placesAt: .nan, now: now))
    }

    @Test func clockSkew() {
        #expect(MirrorPlaces.isLive(placesAt: ms(-0.9), now: now))
        #expect(MirrorPlaces.isLive(placesAt: ms(-1), now: now))
        #expect(!MirrorPlaces.isLive(placesAt: ms(-1.1), now: now))
        #expect(!MirrorPlaces.isLive(placesAt: ms(-60), now: now))
    }

    // MARK: pose

    func pose(_ state: String, kind: String? = nil, gesture: String = "none", asleep: Bool = false) throws -> MirrorPose {
        try decode(placeJSON(state: state, gesture: gesture, asleep: asleep, kind: kind)).pose
    }

    @Test func poses() throws {
        #expect(try pose("working", kind: "desk") == .typing)
        #expect(try pose("working") == .typing)
        #expect(try pose("resting", kind: "sofa", asleep: true) == .asleep)
        #expect(try pose("idle", kind: "cat-bed", asleep: true) == .asleep)
        #expect(try pose("working", asleep: true) == .asleep)
        #expect(try pose("resting", kind: "window-seat") == .sitting)
        #expect(try pose("resting", kind: "rug") == .sitting)
        #expect(try pose("resting") == .sitting)
        for (s, k) in [("idle", "plant"), ("walking", nil), ("talking", "meeting"), ("blocked", nil),
                       ("celebrating", "cat-tree"), ("riding-elevator", "elevator"), ("idle", "snacks"), ("idle", "bookshelf"),
                       ("idle", "coffee"), ("working", "printer"), ("idle", "rug"), ("idle", "water"), ("mystery", nil)] as [(String, String?)] {
            #expect(try pose(s, kind: k) == .standing, "\(s)/\(k ?? "-")")
        }
    }

    @Test func sameExceptPlaces() throws {
        var a = try snapshot(#","place":\#(placeJSON())"#)
        a.spares = [sparePlace("s1", name: "Mochi")]
        a.placesAt = 1_791_266_000_000
        var moved = a
        moved.agents[0].place = try decode(placeJSON(u: "5.5"))
        moved.spares = []
        moved.placesAt = 1_791_266_002_000
        #expect(a.sameExceptPlaces(moved), "only places differ")
        #expect(a.sameExceptPlaces(a))
        #expect(a != moved)
        var busy = moved
        busy.agents[0].status = .waiting
        #expect(!a.sameExceptPlaces(busy), "a status change")
        var more = a
        more.agents.append(more.agents[0])
        more.agents[1].id = "a2"
        #expect(!a.sameExceptPlaces(more), "a new agent")
        var hindered = a
        hindered.claudeHindered = true
        #expect(!a.sameExceptPlaces(hindered))
        #expect(a.withoutPlaces.agents[0].place == nil && a.withoutPlaces.spares.isEmpty && a.withoutPlaces.placesAt == nil)
    }
}

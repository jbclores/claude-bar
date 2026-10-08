import Foundation
import Testing
@testable import ClaudeBarCore

/// A spare cat's place, as the bridge shares it (spares carry a key and a name).
func sparePlace(_ id: String, name: String, floor: Int = 4, u: Double = 0.5, v: Double = 0.5, kind: String? = nil,
                label: String = "Coffee break", minutesLeft: Double? = nil, catId: String = "calico") -> MirrorPlace {
    let activity = kind.map { #"{"kind":"\#($0)","label":"\#(label)"}"# } ?? "null"
    let json = """
    {"floor":\(floor),"u":\(u),"v":\(v),"direction":"front-left","state":"idle","gesture":"both-down","expression":"default",
     "asleep":false,"activity":\(activity),"spotId":null,"minutesLeft":\(minutesLeft.map { "\($0)" } ?? "null"),
     "phase":"using","ridingTo":null,"catId":"\(catId)","at":1791266000000,"name":"\(name)","key":"spare:\(id)"}
    """
    return try! JSONDecoder().decode(MirrorPlace.self, from: Data(json.utf8))
}

@Suite struct SpareCatsTests {
    let building = FloorAssignmentTests().building
    let now = Date(timeIntervalSince1970: 1_791_266_000)
    var nowMs: Double { now.timeIntervalSince1970 * 1000 }
    let spare = sparePlace("s1", name: "Mochi")

    func snapshot(age: Double = 2, agents: [OfficeAgent] = []) -> OfficeSnapshot {
        OfficeSnapshot(agents: agents, spares: [spare], placesAt: nowMs - age * 1000)
    }

    @Test func theSwitchDefaultsOffAndParses() throws {
        #expect(Config.empty.showSpareCats == false)
        #expect(try Config.parse(Data(#"{"office":{"spareCats":true}}"#.utf8)).showSpareCats)
        #expect(try Config.parse(Data(#"{"office":{"spareCats":"yes"}}"#.utf8)).showSpareCats == false)
        let file = makeTempDir().appendingPathComponent("projects.json")
        let store = ConfigStore(file: file)
        store.reload()
        try store.set(true, at: ["office", "spareCats"])
        #expect(store.config.showSpareCats)
    }

    @Test func sparesNeedTheSwitchAndALiveMirror() {
        #expect(OfficeMirror(snapshot(), now: now).spares.isEmpty, "switch off")
        #expect(OfficeMirror(snapshot(), now: now, showSpares: true).spares.map(\.key) == ["spare:s1"])
        #expect(OfficeMirror(snapshot(age: 10.5), now: now, showSpares: true).spares.isEmpty, "stale")
        #expect(OfficeMirror(OfficeSnapshot(agents: [], spares: [spare]), now: now, showSpares: true).spares.isEmpty, "no placesAt")
        #expect(OfficeMirror(nil, now: now, showSpares: true) == .off)
    }

    @Test func sparesAreOnTheirFloorOnly() {
        let m = OfficeMirror(snapshot(), now: now, showSpares: true)
        #expect(m.spares(on: 4, in: building).count == 1)
        #expect(m.spares(on: 1, in: building).isEmpty)
        let off = OfficeMirror(OfficeSnapshot(agents: [], spares: [sparePlace("x", name: "X", floor: 99)], placesAt: nowMs), now: now, showSpares: true)
        #expect(off.spares(on: 4, in: building).isEmpty, "unknown floor")
    }

    @Test func aSpareIsDrawnAsItsOwnCatWithItsName() {
        let a = OfficeMirror.spareAgent(sparePlace("s1", name: "Mochi", catId: "calico"))
        #expect(a.id == "spare:s1" && a.label == "Mochi" && a.cat == "calico" && a.isSpare)
        #expect(!OfficeAgent(id: "x", name: "x", status: .idle, cwd: "/w").isSpare)
    }

    // Spares never reach the Core functions behind counts, the busy strip, Follow, the menu bar cat, "N working" and sounds.
    @Test func sparesDontCount() {
        let a = FloorAssignmentTests().agent("a", .working, repoRoot: "/w/claude-bar")
        let plain = OfficeMirror(snapshot(agents: [a]), now: now)
        let with = OfficeMirror(snapshot(agents: [a]), now: now, showSpares: true)
        #expect(with.places == plain.places, "places are the sessions' only")
        for f in building.floors {
            #expect(FloorPlan.cats(on: f.id, agents: [a], in: building, mirror: with) == FloorPlan.cats(on: f.id, agents: [a], in: building, mirror: plain))
        }
        #expect(FloorPlan.activity(of: building, agents: [a], attention: [], mirror: with)
                == FloorPlan.activity(of: building, agents: [a], attention: [], mirror: plain))
        #expect(FloorPlan.activity(of: building, agents: [], attention: [], mirror: with)[4] == .empty, "a spare doesn't make a floor busy")
        #expect(FloorPlan.followTarget(building: building, agents: [], attention: [], since: [:], now: now, mirror: with)
                == building.lounge?.id)
        // The sessions the status, sounds and notifications track come from the agents only.
        let tracked = StatusModel.trackedSessions(fallback: [], office: snapshot(agents: [a]))
        #expect(tracked.map(\.key) == [a.key])
    }

    @Test func theActivityLine() {
        func line(_ kind: String?, _ label: String = "Coffee break", _ left: Double? = nil) -> String? {
            sparePlace("s", name: "M", kind: kind, label: label, minutesLeft: left).activityLine
        }
        #expect(line("coffee", "Coffee break", 3.2) == "Coffee break · 4 min left", "rounded up")
        #expect(line("coffee", "Coffee break", 4) == "Coffee break · 4 min left")
        #expect(line("coffee", "Coffee break", 0.2) == "Coffee break · 1 min left")
        #expect(line("coffee", "Coffee break", nil) == "Coffee break")
        #expect(line("coffee", "Coffee break", 0) == "Coffee break")
        #expect(line(nil) == nil)
    }
}

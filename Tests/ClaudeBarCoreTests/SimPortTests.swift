import Foundation
import Testing
@testable import ClaudeBarCore

/// sim-expected.json, written by scripts/sim-fixtures.ts with Cat Office's own simulation code.
struct SimFixture: Decodable {
    struct Arrival: Decodable { var gesture: String; var state: String; var seconds: Double }
    struct Activity: Decodable {
        var kind: String, label: String, icon: String, verb: String, state: String, gesture: String, expression: String
        var arrival: Arrival?
        var duration: [Double]
        var gains: [String: Double]
        var lounge: Bool
        var asleep: Bool
    }
    struct PoseVariant: Decodable { var kind: String; var pose: String?; var activity: Activity }
    struct RngCase: Decodable { var seed: UInt32; var values: [Double] }
    struct Decay: Decodable { var state: String; var needs0: [String: Double]; var minutes: Double; var needs: [String: Double] }
    struct P: Decodable { var u: Double; var v: Double }
    struct Pick: Decodable { var floor: Int; var spotId: String; var kind: String }
    struct Choice: Decodable {
        var seed: UInt32, floorId: Int, position: P, needs: [String: Double], minutesSinceWork: Double
        var lastSpotId: String?, ownDeskId: String?, free: String
        var choice: Pick?
    }
    struct Seed: Decodable { var id: String, name: String, role: String, catId: String, deskFloor: Int?, deskSpotId: String?, floor: Int }
    var activities: [Activity]
    var poseVariants: [PoseVariant]
    var rng: [RngCase]
    var decay: [Decay]
    var choices: [Choice]
    var roster: [Seed]
}

@Suite struct SimPortTests {
    let expected: SimFixture

    init() throws {
        expected = try JSONDecoder().decode(SimFixture.self, from: fixture("rooms/user/sim-expected.json"))
    }

    func needs(_ d: [String: Double]) -> SimNeeds {
        var n = SimNeeds(energy: 0, thirst: 0, hunger: 0, social: 0, fun: 0)
        for k in SimNeedKey.allCases { n[k] = d[k.rawValue]! }
        return n
    }

    func same(_ a: SimActivity, _ w: SimFixture.Activity, _ label: String) {
        #expect(a.kind == w.kind && a.label == w.label && a.icon == w.icon && a.verb == w.verb, "\(label)")
        #expect(a.state.rawValue == w.state && a.gesture == w.gesture && a.expression == w.expression, "\(label)")
        #expect(a.arrival?.gesture == w.arrival?.gesture && a.arrival?.state.rawValue == w.arrival?.state
                && a.arrival?.seconds == w.arrival?.seconds, "\(label) arrival")
        #expect([a.duration.min, a.duration.max] == w.duration, "\(label) duration")
        #expect(Dictionary(uniqueKeysWithValues: a.gains.map { ($0.key.rawValue, $0.value) }) == w.gains, "\(label) gains")
        #expect(a.lounge == w.lounge && a.asleep == w.asleep, "\(label)")
    }

    @Test func everyActivityMatches() {
        #expect(SimActivities.all.count == expected.activities.count)
        #expect(SimActivities.kinds == expected.activities.map(\.kind))
        for w in expected.activities {
            guard let a = SimActivities.all[w.kind] else { Issue.record("no \(w.kind)"); continue }
            same(a, w, w.kind)
        }
    }

    @Test func poseVariantsMatchActivityFor() {
        #expect(expected.poseVariants.count == 70)
        for w in expected.poseVariants {
            guard let a = SimActivities.activity(kind: w.kind, pose: w.pose) else { Issue.record("no \(w.kind)"); continue }
            same(a, w.activity, "\(w.kind)/\(w.pose ?? "nil")")
        }
    }

    @Test func rngSequencesMatch() {
        for c in expected.rng {
            var rng = SimRng(seed: c.seed)
            var got = (0..<50).map { _ in rng.next() }
            got += (0..<20).map { _ in rng.range(0, 0.15) }
            #expect(got == c.values, "seed \(c.seed)")
        }
    }

    @Test func rngHelpers() {
        var a = SimRng(seed: 7), b = SimRng(seed: 7)
        #expect(a.int(3, 9) == Int((3 + 6 * b.next()).rounded(.down)))
        #expect(a.chance(0.5) == (b.next() < 0.5))
        let items = ["a", "b", "c", "d"]
        #expect(a.pick(items) == items[b.int(0, 4)])
        var out = items
        for i in stride(from: out.count - 1, to: 0, by: -1) { out.swapAt(i, b.int(0, i + 1)) }
        #expect(a.shuffle(items) == out)
    }

    @Test func decayMatches() {
        #expect(expected.decay.count == 216)
        for c in expected.decay {
            let got = SimNeeds.decayed(needs(c.needs0), state: SimCatState(rawValue: c.state)!, minutes: c.minutes)
            for k in SimNeedKey.allCases {
                #expect(abs(got[k] - c.needs[k.rawValue]!) < 1e-9, "\(c.state) \(c.minutes) \(k)")
            }
        }
    }

    @Test func startingNeedsAndGains() {
        var a = SimRng(seed: 42), b = SimRng(seed: 42)
        let start = SimNeeds.starting(rng: &a)
        for k in SimNeedKey.allCases { #expect(start[k] == b.range(55, 95)) }
        // simulation-engine.ts 1495-1498: each step adds gain / total × dt, clamped; zero gains leave a need alone.
        let tree = SimActivities.all["cat-tree"]!
        let n = needs(["energy": 5, "thirst": 40, "hunger": 40, "social": 40, "fun": 99.9])
        let g = n.gained(tree, total: 10, dt: 1.0 / 30)
        #expect(g.fun == 100 && g.energy == 5 + (-10.0 / 10) * (1.0 / 30) && g.thirst == 40)
    }

    func floors() throws -> [SimFloor] {
        let building = try #require(Building.parse(building: fixture("rooms/user/building.json"), parts: fixture("rooms/user/room-parts.json")))
        let catalogue = try RoomCatalogueTests().catalogue("user")
        let floors = SimFloor.floors(building: building, catalogue: catalogue)
        #expect(floors.count == building.floors.count)
        return floors
    }

    @Test func everyChoiceMatches() throws {
        let floors = try floors()
        #expect(expected.choices.count == 870)
        var checked = 0
        for c in expected.choices {
            let floor = try #require(floors.first { $0.id == c.floorId })
            // The fixture rounds positions to 6 places; the script chose from the floor's first desk spot itself.
            let desk = floor.spots.first { $0.kind == "desk" }?.standAt
            var position = FloorPoint(u: c.position.u, v: c.position.v)
            if let desk, abs(desk.u - position.u) < 1e-6, abs(desk.v - position.v) < 1e-6 { position = desk }
            var rng = SimRng(seed: c.seed)
            let got = SimChoice.choose(floors: floors, floorId: c.floorId, position: position, needs: needs(c.needs),
                                       minutesSinceWork: c.minutesSinceWork, lastSpotId: c.lastSpotId, ownDeskId: c.ownDeskId,
                                       rng: &rng, isFree: { _ in c.free == "all" }, canReach: { _, _ in true })
            let label = "seed \(c.seed) floor \(c.floorId) \(c.position) \(c.needs) \(c.minutesSinceWork) \(c.lastSpotId ?? "-") \(c.ownDeskId ?? "-")"
            #expect(got?.floorId == c.choice?.floor && got?.spot.id == c.choice?.spotId && got?.activity.kind == c.choice?.kind, "\(label)")
            checked += 1
        }
        #expect(checked == 870)
    }

    @Test func rosterMatches() throws {
        let floors = try floors()
        let cats = try JSONDecoder().decode(SpareRoster.Manifest.self, from: fixture("rooms/user/cats.json"))
        let got = SpareRoster.roster(floors: floors, cats: cats.cats)
        #expect(got.count == expected.roster.count)
        for (g, w) in zip(got, expected.roster) {
            #expect(g.id == w.id && g.name == w.name && g.role == w.role && g.catId == w.catId, "\(w.id)")
            #expect(g.desk?.floor == w.deskFloor && g.desk?.spotId == w.deskSpotId && g.floor == w.floor, "\(w.id)")
        }
    }

    @Test func rosterRules() {
        // agent.registry.ts: no desks → lounge (else the first floor); a valid cats.json role wins; names after the tenth from cats.json.
        let f = { (id: Int) in SimFloor(id: id, ownOffice: false, frame: FloorFrame(corners: FloorCorners(top: WorldPoint(x: 0, y: 0), left: WorldPoint(x: -10, y: 10), bottom: WorldPoint(x: 0, y: 20), right: WorldPoint(x: 10, y: 10)))!, spots: []) }
        let cats = (0..<11).map { SpareRoster.Cat(id: "c\($0)", name: "N\($0)", role: $0 == 0 ? "qa" : $0 == 1 ? "boss" : nil) }
        let r = SpareRoster.roster(floors: [f(3), f(1)], cats: cats)
        #expect(r.map(\.floor) == Array(repeating: 1, count: 11))
        #expect(r[0].role == "qa" && r[1].role == "system-analyst" && r[10].name == "N10" && r[9].name == "Sesame")
        #expect(SpareRoster.roster(floors: [f(3), f(4)], cats: cats)[0].floor == 3)
    }
}

import Testing
@testable import ClaudeBarCore

@Suite struct StableSlotsTests {
    @Test func keepsEachCatInItsSpot() {
        #expect(StableSlots.assign(["a", "b", "c"], previous: ["c", nil, "a"], count: 3) == ["c", "b", "a"])
    }

    @Test func newcomersTakeTheFirstFreeSpots() {
        #expect(StableSlots.assign(["a", "d"], previous: ["a", "b", nil], count: 3) == ["a", "d", nil])
        #expect(StableSlots.assign(["x", "y"], previous: [], count: 3) == ["x", "y", nil])
    }

    @Test func extraCatsAreLeftOut() {
        #expect(StableSlots.assign(["a", "b", "c", "d"], previous: [nil, nil], count: 2) == ["a", "b"])
    }

    @Test func aCatThatLeftFreesItsSpot() {
        #expect(StableSlots.assign(["b"], previous: ["a", "b"], count: 2) == [nil, "b"])
    }
}

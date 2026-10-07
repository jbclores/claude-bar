import Testing
@testable import ClaudeBarCore

@Suite struct FitTextTests {
    /// One point per character, to keep the widths readable.
    let measure: (String) -> Double = { Double($0.count) }

    @Test func aNameThatFitsIsKept() {
        #expect(FitText.label(prefix: "12 ", name: "claude-bar", suffix: " · 3 cats", width: 40, measure: measure) == "12 claude-bar · 3 cats")
    }

    @Test func aLongNameGetsAnEllipsisAndKeepsNumberAndCount() {
        let label = FitText.label(prefix: "10 ", name: "pnp-ufdms-base-admin", suffix: " · 3 cats", width: 20, measure: measure)
        #expect(label == "10 pnp-ufd… · 3 cats")
        #expect(label.count <= 20)
    }

    @Test func noRoomLeavesJustTheEllipsis() {
        #expect(FitText.label(prefix: "10 ", name: "pnp", suffix: " · 3 cats", width: 5, measure: measure) == "10 … · 3 cats")
    }
}

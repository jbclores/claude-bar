// Tests/ClaudeBarCoreTests/PillLayoutTests.swift
import CoreGraphics
import Testing
@testable import ClaudeBarCore

@Suite struct PillLayoutTests {
    @Test func pillsNeverOverlap() {
        let pills = ["a": CGRect(x: 0, y: 0, width: 60, height: 20), "b": CGRect(x: 30, y: 5, width: 60, height: 20),
                     "c": CGRect(x: 100, y: 0, width: 60, height: 20)]
        let shown = PillLayout.visible(pills, priority: [])
        #expect(shown == ["a", "c"])
        for x in shown { for y in shown where x < y { #expect(!pills[x]!.intersects(pills[y]!)) } }
    }

    @Test func needsYouWinsTheSpot() {
        let pills = ["a": CGRect(x: 0, y: 0, width: 60, height: 20), "b": CGRect(x: 30, y: 5, width: 60, height: 20)]
        #expect(PillLayout.visible(pills, priority: ["b"]) == ["b"])
    }

    @Test func atTwiceTheSizeBothFit() {
        // The same cats at 2×: centres twice as far apart, pills the same size.
        let pills = ["a": CGRect(x: 0, y: 0, width: 60, height: 20), "b": CGRect(x: 70, y: 10, width: 60, height: 20)]
        #expect(PillLayout.visible(pills, priority: []) == ["a", "b"])
    }
}

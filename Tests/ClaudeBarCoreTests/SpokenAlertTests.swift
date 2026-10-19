import Foundation
import Testing
@testable import ClaudeBarCore

@Suite struct SpokenAlertTests {
    private func words(_ n: Int) -> String { (1...n).map { "w\($0)" }.joined(separator: " ") }

    @Test func short() {
        #expect(SpokenAlert.needsYou(name: "claude-bar", prompt: .permission(tool: "Bash", input: "npm test"), details: false) == "claude-bar needs you.")
        #expect(SpokenAlert.finished(name: "claude-bar", task: "Fix it", details: false) == "claude-bar finished.")
    }

    @Test func permissionBash() {
        let p = PendingPrompt.permission(tool: "Bash", input: "npm run build && npm test -- --watch=false --reporter=dot")
        #expect(SpokenAlert.needsYou(name: "claude-bar", prompt: p, details: true) == "claude-bar asks: allow npm run build && npm test?")
    }

    @Test func permissionEdit() {
        let e = PendingPrompt.permission(tool: "Edit", input: "/Users/x/app/Sources/Login.swift")
        #expect(SpokenAlert.needsYou(name: "claude-bar", prompt: e, details: true) == "claude-bar asks: allow an edit to Login.swift?")
        let w = PendingPrompt.permission(tool: "WebFetch", input: "https://x")
        #expect(SpokenAlert.needsYou(name: "claude-bar", prompt: w, details: true) == "claude-bar asks: allow WebFetch?")
    }

    @Test func permissionPhrase() {
        #expect(SpokenAlert.permissionPhrase(tool: "Bash", input: "npm run build && npm test -- --watch=false") == "allow npm run build && npm test")
        #expect(SpokenAlert.permissionPhrase(tool: "Edit", input: "/Users/x/app/Sources/Login.swift") == "allow an edit to Login.swift")
        #expect(SpokenAlert.permissionPhrase(tool: "WebFetch", input: "https://x") == "allow WebFetch")
    }

    @Test func question() {
        let q = PendingPrompt.Question(question: "Which database should I use?", header: "DB", multiSelect: false, options: [])
        #expect(SpokenAlert.needsYou(name: "claude-bar", prompt: .question([q]), details: true) == "claude-bar asks: Which database should I use?")
        let long = PendingPrompt.Question(question: words(30), header: "", multiSelect: false, options: [])
        #expect(SpokenAlert.needsYou(name: "a", prompt: .question([long]), details: true) == "a asks: \(words(20))?")
    }

    @Test func plan() {
        #expect(SpokenAlert.needsYou(name: "claude-bar", prompt: .plan("# Plan"), details: true) == "claude-bar has a plan for you.")
    }

    @Test func finishedDetails() {
        #expect(SpokenAlert.finished(name: "claude-bar", task: "Fix the login bug\nmore", details: true) == "claude-bar finished: Fix the login bug.")
        #expect(SpokenAlert.finished(name: "claude-bar", task: nil, details: true) == "claude-bar finished.")
        #expect(SpokenAlert.finished(name: "claude-bar", task: "  \n ", details: true) == "claude-bar finished.")
        #expect(SpokenAlert.finished(name: "a", task: words(20), details: true) == "a finished: \(words(12)).")
    }

    @Test func noPromptDetails() {
        #expect(SpokenAlert.needsYou(name: "a", prompt: nil, details: true) == "a needs you.")
    }

    @Test func cap() {
        let five = ["1", "2", "3", "4", "5"]
        #expect(SpokenAlert.capped(five) == ["1", "2", "3", "and 2 more."])
        #expect(SpokenAlert.capped(["1", "2", "3"]) == ["1", "2", "3"])
        #expect(SpokenAlert.capped(["x", "y", "z", "w"]).last == "and 1 more.")
    }

    @Test func repeatWindow() {
        let t = Date(timeIntervalSince1970: 1_000_000)
        let last = ["needsYou|a": t]
        #expect(SpokenAlert.shouldSpeak(key: "needsYou|a", last: last, now: t + 30) == false)
        #expect(SpokenAlert.shouldSpeak(key: "needsYou|a", last: last, now: t + 61))
        #expect(SpokenAlert.shouldSpeak(key: "needsYou|b", last: last, now: t + 1))
    }
}

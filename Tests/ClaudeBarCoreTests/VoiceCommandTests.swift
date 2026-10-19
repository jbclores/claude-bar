import Testing
@testable import ClaudeBarCore

@Suite struct VoiceCommandTests {
    private let targets = [
        VoiceTarget(id: "a1", name: "claude-bar", options: []),
        VoiceTarget(id: "b2", name: "pnp-ufdms-base-admin", options: ["PostgreSQL", "SQLite"]),
    ]
    private func parse(_ s: String) -> VoiceCommand { VoiceCommand.parse(s, targets: targets) }

    @Test func allowPhrasings() {
        for s in ["Allow", "yes allow", "allow it", "uh allow it please"] {
            #expect(parse(s) == VoiceCommand(intent: .allow, target: nil), "\(s)")
        }
    }

    @Test func alwaysAllow() {
        #expect(parse("always allow").intent == .alwaysAllow)
    }

    @Test func denyPhrasings() {
        for s in ["deny", "no", "don't allow", "Do not allow."] {
            #expect(parse(s).intent == .deny, "\(s)")
        }
    }

    @Test func planWords() {
        #expect(parse("approve the plan").intent == .approve)
        #expect(parse("reject").intent == .reject)
    }

    @Test func options() {
        #expect(parse("option two").intent == .option(1))
        #expect(parse("the first one").intent == .option(0))
        #expect(parse("number 3").intent == .option(2))
        #expect(parse("SQLite please").intent == .option(1))
        #expect(parse("two").intent == .option(1))
    }

    @Test func confirmAndCancel() {
        for s in ["yes", "yeah", "confirm"] { #expect(parse(s).intent == .yes, "\(s)") }
        for s in ["never mind", "cancel"] { #expect(parse(s).intent == .cancel, "\(s)") }
    }

    @Test func questions() {
        #expect(parse("what's running").intent == .status)
        #expect(parse("status").intent == .status)
        #expect(parse("how's my usage").intent == .usage)
        #expect(parse("what did I do today").intent == .recap)
        #expect(parse("recap").intent == .recap)
    }

    @Test func names() {
        #expect(parse("allow claude bar") == VoiceCommand(intent: .allow, target: "a1"))
        #expect(parse("pnp ufdms") == VoiceCommand(intent: .name, target: "b2"))
        #expect(parse("claude") == VoiceCommand(intent: .name, target: "a1"))
        #expect(parse("deny p") == VoiceCommand(intent: .deny, target: nil))
    }

    @Test func wholeWordsOnly() {
        #expect(parse("nothing").intent == .none)
        #expect(parse("allowance").intent == .none)
    }

    @Test func noise() {
        #expect(parse("the weather is nice") == VoiceCommand(intent: .none, target: nil))
        #expect(parse("") == VoiceCommand(intent: .none, target: nil))
    }
}

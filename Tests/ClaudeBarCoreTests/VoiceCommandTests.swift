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

    @Test func negatedAllowIsNotGuessed() {
        for s in ["don't always allow", "never allow that", "not allow"] {
            #expect(parse(s).intent == .none, "\(s)")
        }
        #expect(parse("don't allow").intent == .deny)
        #expect(parse("do not allow").intent == .deny)
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
    @Test func yesWithCancelWordsCancels() {
        for s in ["yes cancel", "yeah no", "yes never mind", "yes no wait cancel", "yes wait", "yes stop", "yeah don't"] {
            #expect(parse(s).intent == .cancel, "\(s)")
        }
        for s in ["yes", "yeah", "confirm"] { #expect(parse(s).intent == .yes, "\(s)") }
        #expect(parse("yes allow").intent == .allow)
    }

    @Test func sameNameTwiceHasNoTarget() {
        let twins = [VoiceTarget(id: "a1", name: "claude-bar", options: []), VoiceTarget(id: "a2", name: "claude-bar", options: [])]
        #expect(VoiceCommand.parse("deny claude bar", targets: twins) == VoiceCommand(intent: .deny, target: nil))
    }

    @Test func plainYesBeatsAYesOption() {
        let yesNo = [VoiceTarget(id: "q1", name: "lab", options: ["Yes", "No"])]
        for s in ["yes", "yeah please", "confirm"] {
            #expect(VoiceCommand.parse(s, targets: yesNo).intent == .yes, "\(s)")
        }
        #expect(VoiceCommand.parse("option one", targets: yesNo).intent == .option(0))
    }

    @Test func negatedDenyIsNotGuessed() {
        for s in ["don't deny", "do not deny", "never deny that"] {
            #expect(parse(s).intent == .none, "\(s)")
        }
        #expect(parse("deny").intent == .deny)
    }
}

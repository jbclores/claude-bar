import Testing
@testable import ClaudeBarCore

@Suite struct SingleInstanceTests {
    @Test func quitsWhenAnotherCopyRuns() {
        #expect(SingleInstance.shouldQuit(arguments: ["ClaudeBar"], me: 20, running: [10, 20]))
    }

    @Test func staysWhenAlone() {
        #expect(!SingleInstance.shouldQuit(arguments: ["ClaudeBar"], me: 20, running: [20]))
        #expect(!SingleInstance.shouldQuit(arguments: ["ClaudeBar"], me: 20, running: []))
    }

    @Test func rendersAndClickTestsRunBesideIt() {
        #expect(!SingleInstance.shouldQuit(arguments: ["ClaudeBar", "--render-dropdown", "/tmp/x.png"], me: 20, running: [10, 20]))
        #expect(!SingleInstance.shouldQuit(arguments: ["ClaudeBar", "--test-answer"], me: 20, running: [10, 20]))
    }
}

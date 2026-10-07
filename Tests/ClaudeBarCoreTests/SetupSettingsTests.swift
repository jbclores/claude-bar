import Foundation
import Testing
@testable import ClaudeBarCore

@Suite struct SetupSettingsTests {
    @Test func parsesAndDefaults() throws {
        #expect(try Config.parse(Data(#"{"projects":[]}"#.utf8)).setup == SetupSettings())
        let c = try Config.parse(Data(#"{"projects":[],"setup":{"seen":true,"state":"reduced"}}"#.utf8))
        #expect(c.setup == SetupSettings(seen: true, state: .reduced))
    }

    @Test func anExistingSetupIsNotAskedAgain() {
        // The user's own Mac: patched Cat Office (bridge.json names its folder) and ClaudeBar's status line.
        let s = SetupSettings.inferred(catOfficeDir: nil, bridgeDir: "/Users/x/co", statusLine: .claudeBar)
        #expect(s == SetupSettings(seen: true, state: .full))
        #expect(!SetupSettings.opensByItself(SetupSettings(), inferred: s))
    }

    @Test func aFolderWithoutTheBridgeIsReduced() {
        #expect(SetupSettings.inferred(catOfficeDir: "/Users/x/co", bridgeDir: nil, statusLine: .wrapped(original: "x"))
                == SetupSettings(seen: true, state: .reduced))
    }

    @Test func aNewMacOpensTheWindow() {
        #expect(SetupSettings.inferred(catOfficeDir: nil, bridgeDir: nil, statusLine: .none) == nil)
        #expect(SetupSettings.opensByItself(SetupSettings(), inferred: nil))
    }

    @Test func skippedStaysClosed() {
        #expect(!SetupSettings.opensByItself(SetupSettings(seen: true, state: nil), inferred: nil))
    }
}

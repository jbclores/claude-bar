import Foundation
import Testing
@testable import ClaudeBarCore

@Suite struct SetupSettingsTests {
    @Test func parsesAndDefaults() throws {
        #expect(try Config.parse(Data(#"{"projects":[]}"#.utf8)).setup == SetupSettings())
        let c = try Config.parse(Data(#"{"projects":[],"setup":{"seen":true,"state":"reduced"}}"#.utf8))
        #expect(c.setup == SetupSettings(seen: true, state: .reduced))
    }

    @Test func bridgeJsonPresentIsAlwaysFull() {
        // Running and patched: bridge.json exists (Cat Office is running and patched).
        let s = SetupSettings.inferred(catOfficeDir: nil, bridgeDir: "/Users/x/co", patched: nil, statusLine: .claudeBar)
        #expect(s == SetupSettings(seen: true, state: .full))
        #expect(!SetupSettings.opensByItself(SetupSettings(), inferred: s))
    }

    @Test func folderWithPatchedTrueIsFull() {
        // Folder exists and disk check says it's patched.
        #expect(SetupSettings.inferred(catOfficeDir: "/Users/x/co", bridgeDir: nil, patched: true, statusLine: .claudeBar)
                == SetupSettings(seen: true, state: .full))
    }

    @Test func folderWithPatchedFalseIsReduced() {
        // Folder exists but disk check says it's not patched.
        #expect(SetupSettings.inferred(catOfficeDir: "/Users/x/co", bridgeDir: nil, patched: false, statusLine: .wrapped(original: "x"))
                == SetupSettings(seen: true, state: .reduced))
    }

    @Test func folderWithPatchedNilIsUnknown() {
        // Folder exists but we don't know if it's patched (disk check unknown).
        let s = SetupSettings.inferred(catOfficeDir: "/Users/x/co", bridgeDir: nil, patched: nil, statusLine: .claudeBar)
        #expect(s == SetupSettings(seen: true, state: nil))
        #expect(!SetupSettings.opensByItself(SetupSettings(), inferred: s))
    }

    @Test func bridgeWithPatchedNilIsFull() {
        // Bridge.json present overrides patched being unknown.
        #expect(SetupSettings.inferred(catOfficeDir: "/Users/x/co", bridgeDir: "/Users/x/co", patched: nil, statusLine: .claudeBar)
                == SetupSettings(seen: true, state: .full))
    }

    @Test func catOfficeFolderWithoutStatusLineIsIncomplete() {
        // Cat Office folder exists but no status line integration: can't infer setup.
        let s = SetupSettings.inferred(catOfficeDir: "/Users/x/co", bridgeDir: nil, patched: true, statusLine: .none)
        #expect(s == nil)
        #expect(SetupSettings.opensByItself(SetupSettings(), inferred: s))
    }

    @Test func aNewMacOpensTheWindow() {
        #expect(SetupSettings.inferred(catOfficeDir: nil, bridgeDir: nil, patched: nil, statusLine: .none) == nil)
        #expect(SetupSettings.opensByItself(SetupSettings(), inferred: nil))
    }

    @Test func skippedStaysClosed() {
        #expect(!SetupSettings.opensByItself(SetupSettings(seen: true, state: nil), inferred: nil))
    }
}

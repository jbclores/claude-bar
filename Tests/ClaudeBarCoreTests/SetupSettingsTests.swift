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

@Suite struct SetupEntryPointTests {
    @Test func officeCardOnlyWhenNotSetUpOrReduced() {
        // Not set up: .noCatOffice, or no state and no Cat Office known.
        #expect(SetupSettings(seen: true, state: .noCatOffice).card(catOfficeKnown: true) == .notSetUp)
        #expect(SetupSettings().card(catOfficeKnown: false) == .notSetUp)
        // No state but a Cat Office is known (configured or running): no card.
        #expect(SetupSettings(seen: true, state: nil).card(catOfficeKnown: true) == nil)
        #expect(SetupSettings(seen: true, state: .reduced).card(catOfficeKnown: true) == .reduced)
        #expect(SetupSettings(seen: true, state: .full).card(catOfficeKnown: true) == nil)
        #expect(SetupSettings(seen: true, state: .full).card(catOfficeKnown: false) == nil)
    }

    @Test func settingsLineShortensTheFolder() {
        let home = "/Users/x"
        #expect(SetupSettings(seen: true, state: .full).line(catOfficeDir: "/Users/x/Documents/co", home: home)
                == "Full · Cat Office at ~/Documents/co")
        #expect(SetupSettings(seen: true, state: .reduced).line(catOfficeDir: "/Users/x/co", home: home)
                == "Some extras are off · Cat Office at ~/co")
        #expect(SetupSettings(seen: true, state: .full).line(catOfficeDir: "/opt/co", home: home)
                == "Full · Cat Office at /opt/co")
        #expect(SetupSettings(seen: true, state: .noCatOffice).line(catOfficeDir: nil, home: home) == "Cat Office isn't set up")
        #expect(SetupSettings().line(catOfficeDir: nil, home: home) == "Cat Office isn't set up")
        // A known folder without a recorded state (inferred, patch unknown): just where it is.
        #expect(SetupSettings(seen: true, state: nil).line(catOfficeDir: "/Users/x/co", home: home) == "Cat Office at ~/co")
        // "/Users/xy" is not inside "/Users/x".
        #expect(SetupSettings(seen: true, state: .full).line(catOfficeDir: "/Users/xy/co", home: home)
                == "Full · Cat Office at /Users/xy/co")
    }
}

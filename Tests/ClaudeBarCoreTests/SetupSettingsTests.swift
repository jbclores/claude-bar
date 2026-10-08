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

    @Test func settingsLineShowsTheFolderName() {
        let home = "/Users/x"
        #expect(SetupSettings(seen: true, state: .full).line(catOfficeDir: "/Users/x/Documents/co", home: home)
                == "Set up · Cat Office: co")
        #expect(SetupSettings(seen: true, state: .reduced).line(catOfficeDir: "/Users/x/co", home: home)
                == "Some extras are off · Cat Office: co")
        #expect(SetupSettings(seen: true, state: .full).line(catOfficeDir: "/opt/co", home: home)
                == "Set up · Cat Office: co")
        #expect(SetupSettings(seen: true, state: .noCatOffice).line(catOfficeDir: nil, home: home) == "Cat Office isn't set up")
        #expect(SetupSettings().line(catOfficeDir: nil, home: home) == "Cat Office isn't set up")
        // A known folder without a recorded state (inferred, patch unknown): just where it is.
        #expect(SetupSettings(seen: true, state: nil).line(catOfficeDir: "/Users/x/co", home: home) == "Cat Office: co")
        // Found through the running Cat Office (no configured folder): never "isn't set up" for full / reduced.
        #expect(SetupSettings(seen: true, state: .full).line(catOfficeDir: nil, home: home) == "Set up")
        #expect(SetupSettings(seen: true, state: .reduced).line(catOfficeDir: nil, home: home) == "Some extras are off")
        #expect(SetupSettings(seen: true, state: .full).line(catOfficeDir: nil, runningDir: "/Users/x/co", home: home)
                == "Set up · Cat Office: co")
        // The full path, for hovering: ~-shortened, the configured folder first.
        #expect(SetupSettings.folderPath(catOfficeDir: "/Users/x/Documents/co", runningDir: "/Users/x/other", home: home)
                == "~/Documents/co")
        #expect(SetupSettings.folderPath(catOfficeDir: nil, runningDir: "/opt/co", home: home) == "/opt/co")
        #expect(SetupSettings.folderPath(catOfficeDir: nil, runningDir: nil, home: home) == nil)
        // The configured folder wins over the running one.
        #expect(SetupSettings(seen: true, state: .full).line(catOfficeDir: "/Users/x/a", runningDir: "/Users/x/b", home: home)
                == "Set up · Cat Office: a")
        // "/Users/xy" is not inside "/Users/x".
        #expect(SetupSettings.folderPath(catOfficeDir: "/Users/xy/co", runningDir: nil, home: home) == "/Users/xy/co")
    }
}

@Suite struct PatchWarningTests {
    private func w(patch: Bool = true, here: Bool = false, answers: Bool = false, other: Bool = false, patched: Bool? = false) -> String? {
        SetupSettings.patchWarning(patch: patch, runningHere: here, somethingAnswers: answers, bridgeNamesAnotherFolder: other, alreadyPatched: patched)
    }

    @Test func noWarningWhenNotPatching() {
        #expect(w(patch: false, here: true, answers: true) == nil)
    }

    @Test func noWarningWhenAlreadyPatched() {
        #expect(w(here: true, answers: true, patched: true) == nil)
    }

    @Test func runningHereWarns() {
        #expect(w(here: true, answers: true)?.hasPrefix("Cat Office is running: patching restarts it") == true)
        #expect(w(here: true, patched: nil)?.hasPrefix("Cat Office is running:") == true)
    }

    @Test func unknownCopyAnsweringWarnsConditionally() {
        #expect(w(answers: true)?.hasPrefix("If Cat Office is running from this folder, patching restarts it") == true)
        #expect(w(answers: true, patched: nil) != nil)
    }

    @Test func anotherFolderRunningOrNothingAnsweringIsQuiet() {
        #expect(w(answers: true, other: true) == nil)
        #expect(w() == nil)
    }
}

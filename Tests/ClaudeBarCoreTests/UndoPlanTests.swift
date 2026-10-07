import Foundation
import Testing
@testable import ClaudeBarCore

@Suite struct UndoPlanTests {
    let home = "/Users/cat"
    let dir = "/Users/cat/Documents/cat-office"

    func kinds(_ rows: [UndoRow]) -> [UndoRow.Kind] { rows.map(\.kind) }

    @Test func everythingInPlaceShowsThreeRowsChangesTicked() {
        let rows = UndoPlan.rows(catOfficeDir: dir, unpatch: .patched, statusLine: .claudeBar, canRestore: true, home: home)
        #expect(kinds(rows) == [.unpatch, .statusLine, .remove])
        #expect(rows.allSatisfy { $0.available })
        #expect(UndoPlan.startTicks(rows) == [.unpatch, .statusLine])
        #expect(rows[0].title == "Unpatch Cat Office" && rows[0].detail.contains("~/Documents/cat-office"))
        #expect(rows[1].title == "Restore your old status line")
        #expect(rows[2].title == "Also remove ClaudeBar" && !rows[2].tickedAtStart)
    }

    @Test func nothingToUndoShowsOnlyRemove() {
        let rows = UndoPlan.rows(catOfficeDir: dir, unpatch: .notPatched, statusLine: .none, canRestore: false, home: home)
        #expect(kinds(rows) == [.remove])
        #expect(UndoPlan.startTicks(rows).isEmpty)
        #expect(kinds(UndoPlan.rows(catOfficeDir: nil, unpatch: .unknown, statusLine: .own(command: "x"), canRestore: false, home: home)) == [.remove])
    }

    @Test func patchThatCantComeOutIsGreyedBeforeAnyClick() {
        let rows = UndoPlan.rows(catOfficeDir: dir, unpatch: .cannotUndo, statusLine: .none, canRestore: false, home: home)
        #expect(kinds(rows) == [.unpatch, .remove])
        #expect(!rows[0].available && !rows[0].tickedAtStart)
        #expect(rows[0].detail == UndoText.cannotUnpatch)
        #expect(UndoPlan.startTicks(rows).isEmpty)
    }

    @Test func claudeBarsStatusLineWithoutRecordIsGreyed() {
        let rows = UndoPlan.rows(catOfficeDir: nil, unpatch: .unknown, statusLine: .claudeBar, canRestore: false, home: home)
        #expect(kinds(rows) == [.statusLine, .remove])
        #expect(!rows[0].available && rows[0].detail == UndoText.noRecord)
    }

    @Test func statusLineChangedByHandSinceIsNotOffered() {
        // The record is stale (canRestore false) and the line is the user's own: nothing of ClaudeBar's to undo.
        let rows = UndoPlan.rows(catOfficeDir: nil, unpatch: .unknown, statusLine: .own(command: "npx ccstatusline"), canRestore: false, home: home)
        #expect(kinds(rows) == [.remove])
    }

    @Test func wrappedLineNamesTheirCommand() {
        let rows = UndoPlan.rows(catOfficeDir: nil, unpatch: .unknown, statusLine: .wrapped(original: "npx ccstatusline"), canRestore: true, home: home)
        #expect(rows[0].kind == .statusLine && rows[0].available && rows[0].detail.contains("npx ccstatusline"))
    }

    @Test func setupAfterUndo() {
        let full = SetupSettings(seen: true, state: .full)
        #expect(UndoPlan.setupAfter(full, unpatched: true, statusLineRestored: false) == SetupSettings(seen: true, state: .reduced))
        #expect(UndoPlan.setupAfter(full, unpatched: false, statusLineRestored: true) == SetupSettings(seen: true, state: .reduced))
        #expect(UndoPlan.setupAfter(full, unpatched: false, statusLineRestored: false) == full)
        let none = SetupSettings(seen: true, state: .noCatOffice)
        #expect(UndoPlan.setupAfter(none, unpatched: false, statusLineRestored: true) == none)
        #expect(UndoPlan.setupAfter(SetupSettings(seen: true, state: nil), unpatched: true, statusLineRestored: true).state == nil)
    }

    @Test func warningOnlyWhenUnpatchingSomethingThatMayBeRunning() {
        #expect(UndoPlan.warning(unpatch: false, runningHere: true, somethingAnswers: true, bridgeNamesAnotherFolder: false) == nil)
        #expect(UndoPlan.warning(unpatch: true, runningHere: true, somethingAnswers: false, bridgeNamesAnotherFolder: false)
                == "Cat Office is running: unpatching restarts it, which ends any Claude sessions running inside Cat Office.")
        #expect(UndoPlan.warning(unpatch: true, runningHere: false, somethingAnswers: true, bridgeNamesAnotherFolder: false)
                == "If Cat Office is running from this folder, unpatching restarts it, which ends any Claude sessions running inside Cat Office.")
        #expect(UndoPlan.warning(unpatch: true, runningHere: false, somethingAnswers: true, bridgeNamesAnotherFolder: true) == nil)
        #expect(UndoPlan.warning(unpatch: true, runningHere: false, somethingAnswers: false, bridgeNamesAnotherFolder: false) == nil)
    }

    @Test func doneLines() {
        #expect(UndoText.doneLines(results: [.unpatch: true, .statusLine: true], leftOut: false) == [UndoText.allDone, UndoText.extrasBack])
        #expect(UndoText.doneLines(results: [.unpatch: true], leftOut: true) == [UndoText.extrasBack])
        #expect(UndoText.doneLines(results: [.unpatch: false, .statusLine: true], leftOut: false) == [UndoText.extrasBack])
        #expect(UndoText.doneLines(results: [.statusLine: true, .remove: true], leftOut: false) == [UndoText.removed])
    }

    @Test func wordingIsTheSpecs() {
        #expect(UndoText.title == "Undo ClaudeBar's changes")
        #expect(UndoText.intro == "Pick what to undo. Everything is backed up first, and nothing of yours is deleted.")
        #expect(UndoText.allDone == "All done. Your Mac is back the way it was before ClaudeBar.")
        #expect(UndoText.extrasBack == "Want the extras back later? Settings → Set up ClaudeBar… puts them back in a minute.")
        #expect(UndoText.removed == "ClaudeBar is removed. Thanks for trying it! Come back anytime. ClaudeBar will be right here.")
        #expect(UndoText.failedSafe == "Nothing was changed here, so your setup is safe.")
        #expect(UndoText.nothingChanged == "Nothing was changed.")
    }

    @Test func terminalList() {
        let rows = UndoPlan.rows(catOfficeDir: dir, unpatch: .patched, statusLine: .claudeBar, canRestore: true, home: home)
        let text = UndoText.terminalList(rows: rows, ticked: [.unpatch], warning: "careful")
        #expect(text.hasPrefix("Undo ClaudeBar's changes\nEverything is backed up first, and nothing of yours is deleted.\n"))
        #expect(text.contains("[x] Unpatch Cat Office"))
        #expect(text.contains("[ ] Restore your old status line"))
        #expect(text.contains("[ ] Also remove ClaudeBar"))
        #expect(text.hasSuffix("⚠ careful"))
        let greyed = UndoPlan.rows(catOfficeDir: nil, unpatch: .unknown, statusLine: .claudeBar, canRestore: false, home: home)
        #expect(UndoText.terminalList(rows: greyed, ticked: [], warning: nil).contains("( ) Restore your old status line (not available)"))
        // A greyed row says where the by-hand steps are; available rows don't.
        let page = "/Applications/ClaudeBar.app/Contents/Resources/Help/changes.html"
        let withPage = UndoText.terminalList(rows: greyed, ticked: [], warning: nil, byHand: page)
        #expect(withPage.contains("\(UndoText.noRecord) See: \(page)"))
        #expect(UndoText.terminalList(rows: rows, ticked: [.unpatch], warning: nil, byHand: page).components(separatedBy: "See:").count == 1)
        #expect(!UndoText.terminalList(rows: greyed, ticked: [], warning: nil).contains("See:"))
    }
}

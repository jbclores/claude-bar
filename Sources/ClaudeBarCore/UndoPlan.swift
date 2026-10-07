import Foundation

/// Whether Cat Office's patch can come out (`patch-cat-office.sh --undo --dry-run`).
public enum UnpatchCheck: Equatable, Sendable {
    /// "Would unpatch": the patch (or an older version of it) comes out cleanly.
    case patched
    case notPatched
    /// Exit 3: ClaudeBar patched this folder (it has a patch backup), but the patch doesn't come out cleanly: a patched
    /// file changed since (edited, or a Cat Office update), or a version ClaudeBar doesn't know.
    case cannotUndo
    /// No Cat Office folder, not Cat Office, or the check couldn't run.
    case unknown
}

/// One line of the undo window (and of `ClaudeBar --undo`).
public struct UndoRow: Equatable, Sendable, Identifiable {
    public enum Kind: String, Sendable, CaseIterable { case unpatch, statusLine, remove }
    public var kind: Kind
    public var title: String
    public var detail: String
    /// False: shown greyed, `detail` says why and points to the manual steps.
    public var available: Bool
    public var tickedAtStart: Bool
    public var id: Kind { kind }

    public init(kind: Kind, title: String, detail: String, available: Bool, tickedAtStart: Bool) {
        self.kind = kind; self.title = title; self.detail = detail; self.available = available; self.tickedAtStart = tickedAtStart
    }
}

/// What undo offers, from what's on the Mac now; and what's true after it.
public enum UndoPlan {
    /// Only changes that are in place now, in undo order; "Also remove ClaudeBar" always, unticked.
    public static func rows(catOfficeDir: String?, unpatch: UnpatchCheck, statusLine: StatusLineState, canRestore: Bool,
                            home: String) -> [UndoRow] {
        var rows: [UndoRow] = []
        let shown = catOfficeDir.map { $0.hasPrefix(home + "/") ? "~" + $0.dropFirst(home.count) : $0 } ?? "Cat Office"
        switch unpatch {
        case .patched:
            rows.append(UndoRow(kind: .unpatch, title: "Unpatch Cat Office",
                                detail: "\(shown) · its changed files are backed up first.", available: true, tickedAtStart: true))
        case .cannotUndo:
            rows.append(UndoRow(kind: .unpatch, title: "Unpatch Cat Office", detail: UndoText.cannotUnpatch,
                                available: false, tickedAtStart: false))
        case .notPatched, .unknown:
            break
        }
        if canRestore {
            let detail: String
            if case .wrapped(let original) = statusLine {
                detail = "Back to your own status line (\(original))."
            } else {
                detail = "Back to how it was before ClaudeBar set it up."
            }
            rows.append(UndoRow(kind: .statusLine, title: "Restore your old status line", detail: detail,
                                available: true, tickedAtStart: true))
        } else if statusLine == .claudeBar {
            rows.append(UndoRow(kind: .statusLine, title: "Restore your old status line", detail: UndoText.noRecord,
                                available: false, tickedAtStart: false))
        }
        rows.append(UndoRow(kind: .remove, title: "Also remove ClaudeBar", detail: UndoText.removeDetail,
                            available: true, tickedAtStart: false))
        return rows
    }

    public static func startTicks(_ rows: [UndoRow]) -> Set<UndoRow.Kind> {
        Set(rows.filter { $0.available && $0.tickedAtStart }.map(\.kind))
    }

    /// Something stays as ClaudeBar set it: a change row that is greyed (can't be undone here) or not ticked.
    public static func leftOut(rows: [UndoRow], ticked: Set<UndoRow.Kind>) -> Bool {
        rows.contains { $0.kind != .remove && (!$0.available || !ticked.contains($0.kind)) }
    }

    /// Unpatched or usage off: a full setup is now reduced. `seen` stays, so the window never opens by itself.
    public static func setupAfter(_ s: SetupSettings, unpatched: Bool, statusLineRestored: Bool) -> SetupSettings {
        (unpatched || statusLineRestored) && s.state == .full ? SetupSettings(seen: s.seen, state: .reduced) : s
    }

    /// Unpatching makes Vite reload, which ends Claude sessions running inside Cat Office (as patching does).
    public static func warning(unpatch: Bool, runningHere: Bool, somethingAnswers: Bool, bridgeNamesAnotherFolder: Bool) -> String? {
        guard unpatch else { return nil }
        if runningHere {
            return "Cat Office is running: unpatching restarts it, which ends any Claude sessions running inside Cat Office."
        }
        if somethingAnswers, !bridgeNamesAnotherFolder {
            return "If Cat Office is running from this folder, unpatching restarts it, which ends any Claude sessions running inside Cat Office."
        }
        return nil
    }
}

/// Undo's wording (spec section 6), shared by the window and `ClaudeBar --undo`.
public enum UndoText {
    public static let title = "Undo ClaudeBar's changes"
    public static let intro = "Pick what to undo. Everything is backed up first, and nothing of yours is deleted."
    public static let promise = "Everything is backed up first, and nothing of yours is deleted."
    public static let removeDetail = "Turns off Launch at Login, then ClaudeBar quits (drag the app to the Trash yourself). "
        + "Its own files go to the Trash, so you can still get them back."
    public static let noRecord = "ClaudeBar has no record of your earlier status line, so it won't guess. Here's how to change it by hand."
    public static let cannotUnpatch = "ClaudeBar can't take its patch out cleanly (this Cat Office changed since ClaudeBar patched it), so it won't guess. "
        + "Here's how to do it by hand."
    public static let allDone = "All done. Your Mac is back the way it was before ClaudeBar."
    public static let extrasBack = "Want the extras back later? Settings → Set up ClaudeBar… puts them back in a minute."
    public static let removed = "ClaudeBar is removed. Thanks for trying it! Come back anytime. ClaudeBar will be right here."
    public static let failedSafe = "Nothing was changed here, so your setup is safe."
    public static let nothingChanged = "Nothing was changed."
    public static let question = "Undo these? [y/N] "

    /// `text` trimmed, with a full stop added unless it already ends with punctuation (for joining messages).
    public static func sentence(_ text: String) -> String {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let last = t.last, !".!?".contains(last) else { return t }
        return t + "."
    }

    /// The closing lines: removed; or all done (every change undone and worked) and the way back; or just the way back.
    public static func doneLines(results: [UndoRow.Kind: Bool], leftOut: Bool) -> [String] {
        if results[.remove] == true { return [removed] }
        if !leftOut, !results.isEmpty, results.values.allSatisfy({ $0 }) { return [allDone, extrasBack] }
        return [extrasBack]
    }

    /// The Terminal listing: `[x]` ticked, `[ ]` not, `( )` greyed; then the warning.
    public static func terminalList(rows: [UndoRow], ticked: Set<UndoRow.Kind>, warning: String?) -> String {
        var lines = [title, promise, ""]
        for row in rows {
            if row.available {
                lines.append("  \(ticked.contains(row.kind) ? "[x]" : "[ ]") \(row.title) — \(row.detail)")
            } else {
                lines.append("  ( ) \(row.title) (not available) — \(row.detail)")
            }
        }
        if let warning { lines.append(""); lines.append("⚠ \(warning)") }
        return lines.joined(separator: "\n")
    }
}

import Foundation

public enum SetupState: String, Sendable { case full, reduced, noCatOffice }

/// Onboarding: whether the setup window was shown, and how far setup got. In projects.json under "setup".
public struct SetupSettings: Equatable, Sendable {
    public var seen: Bool
    public var state: SetupState?

    public init(seen: Bool = false, state: SetupState? = nil) {
        self.seen = seen
        self.state = state
    }

    /// Infer setup status from existing Cat Office and status line configuration.
    /// Returns nil if there's no usage (status line not active) or no Cat Office found.
    /// Otherwise uses bridgeDir (running and patched) or patched flag (disk check: true/false/unknown).
    public static func inferred(catOfficeDir: String?, bridgeDir: String?, patched: Bool?, statusLine: StatusLineState) -> SetupSettings? {
        let usage: Bool = switch statusLine { case .claudeBar, .wrapped: true; default: false }
        guard usage, catOfficeDir != nil || bridgeDir != nil else { return nil }
        // BridgeDir indicates Cat Office is running and patched. Otherwise use the on-disk patch check.
        if bridgeDir != nil || patched == true {
            return SetupSettings(seen: true, state: .full)
        } else if patched == false {
            return SetupSettings(seen: true, state: .reduced)
        } else {
            // patched == nil: unknown whether Cat Office is patched
            return SetupSettings(seen: true, state: nil)
        }
    }

    /// The same, for the folder ClaudeBar knows: the configured one if it exists, else the one last seen running
    /// (CatOfficeDiscovery.folderToStart); `patched` checks that folder on disk.
    public static func inferred(configured: String?, remembered: String?, bridgeDir: String?, statusLine: StatusLineState,
                                patched: (String) async -> Bool?) async -> SetupSettings? {
        let dir = CatOfficeDiscovery.folderToStart(configured: configured, remembered: remembered)
        var isPatched: Bool?
        if let dir { isPatched = await patched(dir) }
        return inferred(catOfficeDir: dir, bridgeDir: bridgeDir, patched: isPatched, statusLine: statusLine)
    }

    /// The Connect step's warning under "Patch Cat Office": patching makes Vite reload, which ends Claude sessions running
    /// inside Cat Office. Known when the chosen copy is running (`runningHere`); a possibility when something answers at
    /// Cat Office's address and no live bridge names another folder (an unpatched copy writes no bridge). Nil when not
    /// patching or already patched (nothing changes, no reload).
    public static func patchWarning(patch: Bool, runningHere: Bool, somethingAnswers: Bool, bridgeNamesAnotherFolder: Bool,
                                    alreadyPatched: Bool?) -> String? {
        guard patch, alreadyPatched != true else { return nil }
        if runningHere {
            return "Cat Office is running: patching restarts it, which ends any Claude sessions running inside Cat Office."
        }
        if somethingAnswers, !bridgeNamesAnotherFolder {
            return "If Cat Office is running from this folder, patching restarts it, which ends any Claude sessions running inside Cat Office."
        }
        return nil
    }

    /// After "Restore my old status line": usage is off, so a full setup is now reduced.
    public func afterStatusLineRestore() -> SetupSettings {
        state == .full ? SetupSettings(seen: seen, state: .reduced) : self
    }

    public static func opensByItself(_ s: SetupSettings, inferred: SetupSettings?) -> Bool {
        !s.seen && inferred == nil
    }

    public enum Card: Equatable, Sendable { case notSetUp, reduced }

    /// The Office tab's card: "isn't set up" for no Cat Office (chosen, or no state and none known), "Some extras are
    /// off" for reduced; nothing for a full setup or an inferred one whose Cat Office is known.
    public func card(catOfficeKnown: Bool) -> Card? {
        switch state {
        case .noCatOffice: .notSetUp
        case .reduced: .reduced
        case .full: nil
        case nil: catOfficeKnown ? nil : .notSetUp
        }
    }

    /// Settings' setup line: "Full · Cat Office at ~/…", "Some extras are off · Cat Office at ~/…", or
    /// "Cat Office isn't set up". The folder is the configured one, else the running (or remembered) one; a full or
    /// reduced setup without either still reads "Full" / "Some extras are off", never "isn't set up".
    public func line(catOfficeDir: String?, runningDir: String? = nil, home: String) -> String {
        let shown = (catOfficeDir ?? runningDir).map { dir in dir.hasPrefix(home + "/") ? "~" + dir.dropFirst(home.count) : dir }
        let at = shown.map { " · Cat Office at \($0)" } ?? ""
        switch state {
        case .full: return "Full" + at
        case .reduced: return "Some extras are off" + at
        case .noCatOffice: return "Cat Office isn't set up"
        case nil: return shown.map { "Cat Office at \($0)" } ?? "Cat Office isn't set up"
        }
    }
}

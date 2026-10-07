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
    /// "Cat Office isn't set up".
    public func line(catOfficeDir: String?, home: String) -> String {
        guard state != .noCatOffice, let dir = catOfficeDir else { return "Cat Office isn't set up" }
        let shown = dir.hasPrefix(home + "/") ? "~" + dir.dropFirst(home.count) : dir
        switch state {
        case .full: return "Full · Cat Office at \(shown)"
        case .reduced: return "Some extras are off · Cat Office at \(shown)"
        default: return "Cat Office at \(shown)"
        }
    }
}

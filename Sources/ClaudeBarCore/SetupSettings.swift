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
}

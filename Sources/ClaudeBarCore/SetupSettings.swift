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

    public static func inferred(catOfficeDir: String?, bridgeDir: String?, statusLine: StatusLineState) -> SetupSettings? {
        let usage: Bool = switch statusLine { case .claudeBar, .wrapped: true; default: false }
        guard usage, catOfficeDir != nil || bridgeDir != nil else { return nil }
        // Only a patched Cat Office writes bridge.json with its folder.
        return SetupSettings(seen: true, state: bridgeDir != nil ? .full : .reduced)
    }

    public static func opensByItself(_ s: SetupSettings, inferred: SetupSettings?) -> Bool {
        !s.seen && inferred == nil
    }
}

import Foundation

/// One ClaudeBar in the menu bar: a copy launched while another runs quits (renders and click tests excepted).
public enum SingleInstance {
    public static func shouldQuit(arguments: [String], me: Int32, running: [Int32]) -> Bool {
        let renderOrTest = arguments.dropFirst().contains { $0.hasPrefix("--render") || $0.hasPrefix("--test") }
        return !renderOrTest && running.contains { $0 != me }
    }
}

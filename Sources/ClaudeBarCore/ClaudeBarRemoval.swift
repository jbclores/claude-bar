import Foundation

/// "Also remove ClaudeBar": moves ClaudeBar's own folders to the Trash (never deletes), skipping missing ones, and its
/// helper scripts in ~/.claude when settings.json doesn't run the wrapper. Leaves everything else: settings.json,
/// statusline-command.sh (Claude Code may still run it), the status line record and every backup.
public struct ClaudeBarRemoval: Sendable {
    public struct Result: Equatable, Sendable {
        public var trashed: [URL] = []
        public var failures: [String] = []
    }

    let home: URL
    let trash: @Sendable (URL) throws -> Void

    public init(home: URL, trash: @escaping @Sendable (URL) throws -> Void = ClaudeBarRemoval.moveToTrash) {
        self.home = home
        self.trash = trash
    }

    /// Settings, usage files from the status line, the art cache, the log.
    public var folders: [URL] {
        [".config/claude-bar", ".claude/claude-bar", "Library/Caches/ClaudeBar", "Library/Logs/ClaudeBar"]
            .map { home.appendingPathComponent($0, isDirectory: true) }
    }

    var claudeDir: URL { home.appendingPathComponent(".claude", isDirectory: true) }

    /// ClaudeBar's wrapper and the hook it runs (only "keep my own status line" writes them).
    public var helperScripts: [URL] {
        [StatusLineSetup.wrapperName, StatusLineSetup.hookName].map { claudeDir.appendingPathComponent($0) }
    }

    /// settings.json's statusLine runs ClaudeBar's wrapper; when unreadable, assume it does (the helpers then stay).
    var wrapperInUse: Bool {
        let settings = claudeDir.appendingPathComponent("settings.json")
        guard let data = try? Data(contentsOf: settings) else { return false }
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return true }
        let command = (object["statusLine"] as? [String: Any])?["command"] as? String
        return command?.contains(StatusLineSetup.wrapperName) == true
    }

    public func remove() -> Result {
        var result = Result()
        let helpers = wrapperInUse ? [] : helperScripts
        for folder in folders + helpers where FileManager.default.fileExists(atPath: folder.path) {
            do {
                try trash(folder)
                result.trashed.append(folder)
            } catch {
                result.failures.append("\(folder.path): \(error.localizedDescription)")
            }
        }
        return result
    }

    public static func moveToTrash(_ url: URL) throws {
        try FileManager.default.trashItem(at: url, resultingItemURL: nil)
    }
}

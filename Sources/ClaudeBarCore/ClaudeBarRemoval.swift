import Foundation

/// "Also remove ClaudeBar": moves ClaudeBar's own folders to the Trash (never deletes), skipping missing ones. Leaves
/// everything else, including its scripts in ~/.claude (settings.json may still run them) and every backup.
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
            .map { home.appendingPathComponent($0) }
    }

    public func remove() -> Result {
        var result = Result()
        for folder in folders where FileManager.default.fileExists(atPath: folder.path) {
            do {
                try trash(folder)
                // Normalize the URL to remove any trailing slash for consistent comparison
                let normalizedFolder = URL(fileURLWithPath: folder.path)
                result.trashed.append(normalizedFolder)
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

import Foundation

public enum Paths {
    public static var home: URL { FileManager.default.homeDirectoryForCurrentUser }
    public static var snapshotsDir: URL { home.appendingPathComponent(".claude/claude-bar/sessions", isDirectory: true) }
    public static var claudeSessionsDir: URL { home.appendingPathComponent(".claude/sessions", isDirectory: true) }
    public static var configFile: URL { home.appendingPathComponent(".config/claude-bar/projects.json") }
    public static var artCacheDir: URL {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("ClaudeBar/art", isDirectory: true)
    }

    /// Expands `~`, standardizes, and resolves symlinks, so two spellings of one folder compare equal.
    public static func normalize(_ path: String) -> String {
        guard !path.isEmpty else { return "" }
        let expanded = (path as NSString).expandingTildeInPath
        return URL(fileURLWithPath: expanded).standardizedFileURL.resolvingSymlinksInPath().path
    }

    /// True when `path` is `folder` or inside it. Both must already be normalized.
    public static func isInside(_ path: String, _ folder: String) -> Bool {
        guard !path.isEmpty, !folder.isEmpty else { return false }
        if folder == "/" { return true }
        return path == folder || path.hasPrefix(folder + "/")
    }
}

import Foundation

public enum StatusLineState: Equatable, Sendable {
    case none
    case claudeBar
    case wrapped(original: String)
    case own(command: String)
    case unreadable
}

public struct StatusLineError: Error, Equatable { public let message: String }

/// Claude Code's status line (~/.claude/settings.json "statusLine") as ClaudeBar sets it up: install ClaudeBar's script,
/// or wrap the user's own command so ClaudeBar's data is saved quietly and their output is unchanged; every change
/// backed up and restorable.
public struct StatusLineSetup: Sendable {
    public static let scriptName = "statusline-command.sh"
    public static let hookName = "claude-bar-hook.sh"
    public static let wrapperName = "claude-bar-statusline.sh"
    public static let originalName = "claude-bar-statusline-original.json"
    /// Every ClaudeBar status line script (any version) writes here.
    public static let marker = "~/.claude/claude-bar"
    static let claudeBarCommand = "bash ~/.claude/statusline-command.sh"

    let claudeDir: URL
    let script: String
    let now: @Sendable () -> Date

    public init(claudeDir: URL, script: String, now: @escaping @Sendable () -> Date = Date.init) {
        self.claudeDir = claudeDir
        self.script = script
        self.now = now
    }

    var settingsFile: URL { claudeDir.appendingPathComponent("settings.json") }
    func file(_ name: String) -> URL { claudeDir.appendingPathComponent(name) }
    var stamp: String {
        let f = DateFormatter(); f.dateFormat = "yyyyMMdd-HHmmss"; f.timeZone = TimeZone(identifier: "UTC")
        return f.string(from: now())
    }

    func readSettings() throws -> [String: Any] {
        guard let data = try? Data(contentsOf: settingsFile) else { return [:] }
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw StatusLineError(message: "~/.claude/settings.json isn't valid JSON")
        }
        return object
    }

    func command(in settings: [String: Any]) -> String? {
        (settings["statusLine"] as? [String: Any])?["command"] as? String
    }

    struct Original: Codable { var command: String?; var scriptBackup: String? }

    func readOriginal() -> Original? {
        (try? Data(contentsOf: file(Self.originalName))).flatMap { try? JSONDecoder().decode(Original.self, from: $0) }
    }

    public var canRestore: Bool { readOriginal() != nil }

    public func state() -> StatusLineState {
        guard let settings = try? readSettings() else { return .unreadable }
        guard let command = command(in: settings), !command.trimmingCharacters(in: .whitespaces).isEmpty else { return .none }
        if command.contains(Self.wrapperName), let original = readOriginal()?.command { return .wrapped(original: original) }
        if command.contains(Self.scriptName),
           let text = try? String(contentsOf: file(Self.scriptName), encoding: .utf8), text.contains(Self.marker) {
            return .claudeBar
        }
        return .own(command: command)
    }

    /// Copies `source` to "<name>.claude-bar-backup-<stamp>" (numbered if that exists); returns the backup's file name.
    func backUp(_ source: URL, as name: String) throws -> String {
        var candidate = "\(name).claude-bar-backup-\(stamp)"
        var n = 2
        while FileManager.default.fileExists(atPath: file(candidate).path) {
            candidate = "\(name).claude-bar-backup-\(stamp)-\(n)"; n += 1
        }
        try FileManager.default.copyItem(at: source, to: file(candidate))
        return candidate
    }

    func writeSettings(_ settings: [String: Any]) throws {
        if FileManager.default.fileExists(atPath: settingsFile.path) {
            _ = try backUp(settingsFile, as: "settings.json")
        }
        try FileManager.default.createDirectory(at: claudeDir, withIntermediateDirectories: true)
        let data = try JSONSerialization.data(withJSONObject: settings, options: [.prettyPrinted, .sortedKeys])
        try data.write(to: settingsFile, options: .atomic)
    }

    func setCommand(_ command: String?, in settings: [String: Any]) -> [String: Any] {
        var s = settings
        if let command { s["statusLine"] = ["type": "command", "command": command] } else { s.removeValue(forKey: "statusLine") }
        return s
    }

    func recordOriginal(_ original: Original) throws {
        try JSONEncoder().encode(original).write(to: file(Self.originalName), options: .atomic)
    }

    /// ClaudeBar's status line. The user's previous command and script (if any) are recorded and backed up first.
    public func useClaudeBar() throws {
        let settings = try readSettings()
        let previous = command(in: settings)
        var backup: String?
        let scriptFile = file(Self.scriptName)
        if let existing = try? String(contentsOf: scriptFile, encoding: .utf8), existing != script {
            backup = try backUp(scriptFile, as: Self.scriptName)
        }
        if readOriginal() == nil, previous != nil || backup != nil { try recordOriginal(Original(command: previous, scriptBackup: backup)) }
        try FileManager.default.createDirectory(at: claudeDir, withIntermediateDirectories: true)
        try Data(script.utf8).write(to: scriptFile, options: .atomic)
        try writeSettings(setCommand(Self.claudeBarCommand, in: settings))
    }

    /// Keeps the user's own status line: ClaudeBar's hook saves its data quietly, then their command runs unchanged.
    public func wrap() throws {
        let settings = try readSettings()
        guard let theirs = command(in: settings) else { throw StatusLineError(message: "There is no status line to keep") }
        try Data(script.utf8).write(to: file(Self.hookName), options: .atomic)
        let quoted = "'" + theirs.replacingOccurrences(of: "'", with: "'\\''") + "'"
        let wrapper = """
        #!/bin/bash
        # ClaudeBar: saves ClaudeBar's data (quietly), then runs your own status line, unchanged.
        input=$(cat)
        printf '%s' "$input" | CLAUDEBAR_STATUSLINE_QUIET=1 bash "${CLAUDEBAR_HOOK:-$HOME/.claude/\(Self.hookName)}" >/dev/null 2>&1
        printf '%s' "$input" | /bin/bash -c \(quoted)

        """
        try Data(wrapper.utf8).write(to: file(Self.wrapperName), options: .atomic)
        try recordOriginal(Original(command: theirs, scriptBackup: nil))
        try writeSettings(setCommand("bash ~/.claude/\(Self.wrapperName)", in: settings))
    }

    /// Back to what the user had before ClaudeBar changed it.
    public func restore() throws {
        guard let original = readOriginal() else { return }
        if let backup = original.scriptBackup {
            let scriptFile = file(Self.scriptName)
            try? FileManager.default.removeItem(at: scriptFile)
            try FileManager.default.copyItem(at: file(backup), to: scriptFile)
        }
        try writeSettings(setCommand(original.command, in: try readSettings()))
        try FileManager.default.removeItem(at: file(Self.originalName))
    }
}

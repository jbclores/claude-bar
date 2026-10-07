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

    func statusLine(in settings: [String: Any]) -> [String: Any]? { settings["statusLine"] as? [String: Any] }

    func command(in settings: [String: Any]) -> String? {
        (statusLine(in: settings)?["command"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// The whole original "statusLine" object (as JSON text, nil = there was none) and the user's script backup, if any.
    struct Original: Codable { var statusLine: String?; var scriptBackup: String? }

    func readOriginal() -> Original? {
        (try? Data(contentsOf: file(Self.originalName))).flatMap { try? JSONDecoder().decode(Original.self, from: $0) }
    }

    func originalCommand(_ original: Original) -> String? {
        guard let text = original.statusLine,
              let object = try? JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any] else { return nil }
        return command(in: ["statusLine": object])
    }

    public var canRestore: Bool { readOriginal() != nil }

    /// True when `command` runs ~/.claude/statusline-command.sh itself (written with ~, $HOME or the absolute home path).
    func namesOurScript(_ command: String) -> Bool {
        func normalised(_ t: String) -> String {
            t.replacingOccurrences(of: "\"", with: "").replacingOccurrences(of: "'", with: "")
                .split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
        }
        let home = claudeDir.deletingLastPathComponent().path
        let paths = ["~/.claude/\(Self.scriptName)", "$HOME/.claude/\(Self.scriptName)", "${HOME}/.claude/\(Self.scriptName)",
                     "\(home)/.claude/\(Self.scriptName)", claudeDir.appendingPathComponent(Self.scriptName).path]
        let c = normalised(command)
        return paths.contains { c == "bash \($0)" || c == $0 }
    }

    public func state() -> StatusLineState {
        guard let settings = try? readSettings() else { return .unreadable }
        guard let command = command(in: settings), !command.isEmpty else { return .none }
        if command.contains(Self.wrapperName), let record = readOriginal(), let original = originalCommand(record) {
            return .wrapped(original: original)
        }
        if namesOurScript(command),
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
        if FileManager.default.fileExists(atPath: settingsFile.path) { _ = try backUp(settingsFile, as: "settings.json") }
        try FileManager.default.createDirectory(at: claudeDir, withIntermediateDirectories: true)
        let data = try JSONSerialization.data(withJSONObject: settings, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
        try data.write(to: settingsFile, options: .atomic)
    }

    /// Sets the command, keeping the statusLine object's other keys (e.g. "padding").
    func settingCommand(_ command: String, in settings: [String: Any]) -> [String: Any] {
        var s = settings
        var line = statusLine(in: settings) ?? [:]
        line["type"] = "command"; line["command"] = command
        s["statusLine"] = line
        return s
    }

    func recordOriginal(_ original: Original) throws {
        try JSONEncoder().encode(original).write(to: file(Self.originalName), options: .atomic)
    }

    func json(_ object: [String: Any]?) throws -> String? {
        guard let object else { return nil }
        return String(decoding: try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys, .withoutEscapingSlashes]), as: UTF8.self)
    }

    /// ClaudeBar's status line. The user's previous status line and script (if any) are recorded and backed up first.
    public func useClaudeBar() throws {
        if case .wrapped = state() { try restore() }
        let settings = try readSettings()
        let previous = statusLine(in: settings)
        var backup: String?
        let scriptFile = file(Self.scriptName)
        if let existing = try? Data(contentsOf: scriptFile), existing != Data(script.utf8) {
            backup = try backUp(scriptFile, as: Self.scriptName)
        }
        if readOriginal() == nil, previous != nil || backup != nil {
            try recordOriginal(Original(statusLine: try json(previous), scriptBackup: backup))
        }
        try FileManager.default.createDirectory(at: claudeDir, withIntermediateDirectories: true)
        try Data(script.utf8).write(to: scriptFile, options: .atomic)
        try writeSettings(settingCommand(Self.claudeBarCommand, in: settings))
    }

    /// Keeps the user's own status line: ClaudeBar's hook saves its data quietly, then their command runs unchanged.
    public func wrap() throws {
        if case .claudeBar = state(), canRestore { try restore() }
        guard case .own(let theirs) = state(), !theirs.contains(Self.wrapperName) else {
            throw StatusLineError(message: "There is no status line of your own to keep (or it is already kept)")
        }
        let settings = try readSettings()
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
        if readOriginal() == nil { try recordOriginal(Original(statusLine: try json(statusLine(in: settings)), scriptBackup: nil)) }
        try writeSettings(settingCommand("bash ~/.claude/\(Self.wrapperName)", in: settings))
    }

    /// Back to what the user had before ClaudeBar changed it. Checks everything first; nothing of the user's is deleted.
    public func restore() throws {
        guard let original = readOriginal() else { return }
        var settings = try readSettings()
        if let backup = original.scriptBackup, !FileManager.default.fileExists(atPath: file(backup).path) {
            throw StatusLineError(message: "The backup of your status line script (\(backup)) is missing, so nothing was changed")
        }
        if let backup = original.scriptBackup {
            let scriptFile = file(Self.scriptName)
            if let current = try? Data(contentsOf: scriptFile), current != Data(script.utf8) {
                _ = try backUp(scriptFile, as: Self.scriptName)   // they edited it since: keep their version too
            }
            let temp = file(".claude-bar-restore-\(UUID().uuidString)")
            try FileManager.default.copyItem(at: file(backup), to: temp)
            if FileManager.default.fileExists(atPath: scriptFile.path) {
                _ = try FileManager.default.replaceItemAt(scriptFile, withItemAt: temp)
            } else {
                try FileManager.default.moveItem(at: temp, to: scriptFile)
            }
        }
        if let text = original.statusLine, let object = try JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any] {
            settings["statusLine"] = object
        } else {
            settings.removeValue(forKey: "statusLine")
        }
        try writeSettings(settings)
        try FileManager.default.removeItem(at: file(Self.originalName))
    }
}

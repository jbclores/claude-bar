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
    /// Apple's command line tools are installed (ClaudeBar's status line and hook run python3 and git; without the
    /// tools those are shims that pop an install dialog).
    let toolsInstalled: @Sendable () -> Bool

    public static let toolsMissing = "Usage needs Apple's command line tools: run xcode-select --install, then Settings → Set up ClaudeBar…"

    public init(claudeDir: URL, script: String, now: @escaping @Sendable () -> Date = Date.init,
                toolsInstalled: @escaping @Sendable () -> Bool = { true }) {
        self.claudeDir = claudeDir
        self.script = script
        self.now = now
        self.toolsInstalled = toolsInstalled
    }

    /// Whether Apple's command line tools are installed: `xcode-select -p` exits 0.
    public static func commandLineToolsInstalled() -> Bool {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/xcode-select")
        p.arguments = ["-p"]
        p.standardOutput = FileHandle.nullDevice; p.standardError = FileHandle.nullDevice
        do { try p.run() } catch { return false }
        p.waitUntilExit()
        return p.terminationStatus == 0
    }

    /// Before installing or wrapping: the tools ClaudeBar's script needs, and a real ClaudeBar script to install.
    func checkCanInstall() throws {
        guard !script.isEmpty, script.contains(Self.marker) else {
            throw StatusLineError(message: "ClaudeBar's status line script is missing from the app; nothing was changed")
        }
        guard toolsInstalled() else { throw StatusLineError(message: Self.toolsMissing) }
    }

    var settingsFile: URL { claudeDir.appendingPathComponent("settings.json") }
    func file(_ name: String) -> URL { claudeDir.appendingPathComponent(name) }
    /// Where a write goes: the file a symlink points at (dotfiles setups), so the link stays a link.
    func target(_ url: URL) -> URL { url.resolvingSymlinksInPath() }
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

    /// A record is live only while ClaudeBar's status line (or its wrapper) is what settings.json runs.
    func recordIsLive() -> Bool {
        guard let record = readOriginal() else { return false }
        guard let settings = try? readSettings(), let command = command(in: settings) else { return false }
        if command.contains(Self.wrapperName) { return true }
        guard namesOurScript(command) else { return false }
        // We backed up their script: whatever is there now (even an edit of ours) is ours to swap back; restore keeps it.
        if record.scriptBackup != nil { return true }
        // Nothing of theirs was backed up: a script without ClaudeBar's marker is one they put there since (e.g. /statusline).
        let text = try? String(contentsOf: file(Self.scriptName), encoding: .utf8)
        return text?.contains(Self.marker) == true
    }

    public var canRestore: Bool { recordIsLive() }

    /// A record that outlived ClaudeBar's status line (it was changed by hand) is archived, never restored.
    func archiveStaleRecord() throws {
        _ = try readSettings()   // unreadable settings: throw before changing anything
        guard readOriginal() != nil, !recordIsLive() else { return }
        var candidate = "\(Self.originalName)-stale-\(stamp)"
        var n = 2
        while FileManager.default.fileExists(atPath: file(candidate).path) { candidate = "\(Self.originalName)-stale-\(stamp)-\(n)"; n += 1 }
        try FileManager.default.moveItem(at: file(Self.originalName), to: file(candidate))
    }

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
        // The content (of the file a link points at), never the link itself.
        try FileManager.default.copyItem(at: target(source), to: file(candidate))
        return candidate
    }

    func writeSettings(_ settings: [String: Any]) throws {
        if FileManager.default.fileExists(atPath: settingsFile.path) { _ = try backUp(settingsFile, as: "settings.json") }
        try FileManager.default.createDirectory(at: claudeDir, withIntermediateDirectories: true)
        let data = try JSONSerialization.data(withJSONObject: settings, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
        try data.write(to: target(settingsFile), options: .atomic)
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
        try checkCanInstall()
        if case .wrapped = state() { try restore() }
        try archiveStaleRecord()
        let settings = try readSettings()
        let previous = statusLine(in: settings)
        var backup: String?
        let scriptFile = file(Self.scriptName)
        if let existing = try? Data(contentsOf: scriptFile), existing != Data(script.utf8) {
            backup = try backUp(scriptFile, as: Self.scriptName)
        }
        if readOriginal() == nil {   // also when they had none: restore then removes ours
            try recordOriginal(Original(statusLine: try json(previous), scriptBackup: backup))
        }
        try FileManager.default.createDirectory(at: claudeDir, withIntermediateDirectories: true)
        try Data(script.utf8).write(to: target(scriptFile), options: .atomic)
        try writeSettings(settingCommand(Self.claudeBarCommand, in: settings))
    }

    /// Keeps the user's own status line: ClaudeBar's hook saves its data quietly, then their command runs unchanged.
    public func wrap() throws {
        try checkCanInstall()
        let unable = StatusLineError(message: "There is no status line of your own to keep (or it is already kept)")
        if case .claudeBar = state(), let record = readOriginal() {
            // Work out what restoring would give back before changing anything.
            guard let back = originalCommand(record), !back.contains(Self.wrapperName),
                  record.scriptBackup != nil || !namesOurScript(back) else { throw unable }
            if let backup = record.scriptBackup, namesOurScript(back),
               let text = try? String(contentsOf: file(backup), encoding: .utf8), text.contains(Self.marker) { throw unable }
            try restore()
        } else {
            try archiveStaleRecord()
        }
        guard case .own(let theirs) = state(), !theirs.contains(Self.wrapperName) else { throw unable }
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
        guard (try? readSettings()) != nil else {
            throw StatusLineError(message: "~/.claude/settings.json isn't valid JSON; nothing was changed")
        }
        guard let original = readOriginal(), recordIsLive() else {
            throw StatusLineError(message: "There is nothing of ClaudeBar's to undo: the status line was changed since")
        }
        var settings = try readSettings()
        var restored: [String: Any]?
        if let text = original.statusLine {
            guard let object = try? JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any] else {
                throw StatusLineError(message: "ClaudeBar's saved copy of your status line is unreadable, so nothing was changed")
            }
            restored = object
        }
        if let backup = original.scriptBackup, !FileManager.default.fileExists(atPath: file(backup).path) {
            throw StatusLineError(message: "The backup of your status line script (\(backup)) is missing, so nothing was changed")
        }
        if let backup = original.scriptBackup {
            let scriptFile = file(Self.scriptName)
            if let current = try? Data(contentsOf: scriptFile), current != Data(script.utf8) {
                _ = try backUp(scriptFile, as: Self.scriptName)   // they edited it since: keep their version too
            }
            // Next to the file it replaces (a symlinked script's target may be on another volume).
            let destination = target(scriptFile)
            let temp = destination.deletingLastPathComponent().appendingPathComponent(".claude-bar-restore-\(UUID().uuidString)")
            try FileManager.default.copyItem(at: file(backup), to: temp)
            if FileManager.default.fileExists(atPath: scriptFile.path) {
                _ = try FileManager.default.replaceItemAt(destination, withItemAt: temp)
            } else {
                try FileManager.default.moveItem(at: temp, to: scriptFile)
            }
        }
        if let restored {
            settings["statusLine"] = restored
        } else {
            settings.removeValue(forKey: "statusLine")
        }
        try writeSettings(settings)
        try FileManager.default.removeItem(at: file(Self.originalName))
    }
}

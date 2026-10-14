import AppKit
import ClaudeBarCore

/// "Show terminal": the session's process → its tty → the Terminal or iTerm tab using it, brought forward.
enum TerminalFinder {
    /// The tty of `pid` ("/dev/ttys004"), nil when it has none or isn't running.
    static func tty(of pid: Int32) -> String? {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/ps")
        p.arguments = ["-o", "tty=", "-p", String(pid)]
        let out = Pipe()
        p.standardOutput = out
        p.standardError = FileHandle.nullDevice
        guard (try? p.run()) != nil else { return nil }
        let data = out.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        return TerminalTTY.path(psOutput: String(decoding: data, as: UTF8.self))
    }

    /// The app the session's terminal belongs to (Terminal or iTerm), from the commands of `pid` and its parents; nil
    /// for any other (VS Code, Orca…), where "Show terminal" can't help.
    static func host(of pid: Int32) -> TerminalHost? {
        var commands: [String] = [], current = pid
        for _ in 0..<20 where current > 1 {
            let p = Process()
            p.executableURL = URL(fileURLWithPath: "/bin/ps")
            p.arguments = ["-o", "ppid=,command=", "-p", String(current)]
            let out = Pipe()
            p.standardOutput = out
            p.standardError = FileHandle.nullDevice
            guard (try? p.run()) != nil else { break }
            let line = String(decoding: out.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
            p.waitUntilExit()
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard let space = trimmed.firstIndex(of: " "), let parent = Int32(trimmed[..<space]) else { break }
            commands.append(trimmed[space...].trimmingCharacters(in: .whitespaces))
            current = parent
        }
        return TerminalHost.of(ancestorCommands: commands)
    }

    /// Terminal and iTerm, those running.
    static var terminalsRunning: [String] {
        ["com.apple.Terminal", "com.googlecode.iterm2"].filter { !NSRunningApplication.runningApplications(withBundleIdentifier: $0).isEmpty }
    }

    /// Brings forward the Terminal / iTerm tab on `tty`. False when none was found (or macOS didn't let ClaudeBar ask).
    /// Runs on a background queue (`AppState.showTerminal`): the first time, macOS asks to let ClaudeBar control the app,
    /// and the menu mustn't freeze while it waits.
    @discardableResult
    static func show(tty: String, in host: TerminalHost) -> Bool {
        let scripts = [
            "com.apple.Terminal": """
            tell application "Terminal"
              repeat with w in windows
                repeat with t in tabs of w
                  if tty of t is "\(tty)" then
                    set selected of t to true
                    set index of w to 1
                    activate
                    return "ok"
                  end if
                end repeat
              end repeat
            end tell
            """,
            "com.googlecode.iterm2": """
            tell application "iTerm2"
              repeat with w in windows
                repeat with t in tabs of w
                  repeat with s in sessions of t
                    if tty of s is "\(tty)" then
                      select w
                      select t
                      activate
                      return "ok"
                    end if
                  end repeat
                end repeat
              end repeat
            end tell
            """,
        ]
        var error: NSDictionary?
        guard terminalsRunning.contains(host.bundleId), let source = scripts[host.bundleId] else { return false }
        return NSAppleScript(source: source)?.executeAndReturnError(&error).stringValue == "ok"
    }
}

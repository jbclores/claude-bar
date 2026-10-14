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

    /// Terminal and iTerm, those running.
    static var terminalsRunning: [String] {
        ["com.apple.Terminal", "com.googlecode.iterm2"].filter { !NSRunningApplication.runningApplications(withBundleIdentifier: $0).isEmpty }
    }

    /// Brings forward the Terminal / iTerm tab on `tty`. False when none was found (or macOS didn't let ClaudeBar ask).
    @discardableResult
    static func show(tty: String) -> Bool {
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
        for app in terminalsRunning {
            var error: NSDictionary?
            if let source = scripts[app], NSAppleScript(source: source)?.executeAndReturnError(&error).stringValue == "ok" { return true }
        }
        return false
    }
}

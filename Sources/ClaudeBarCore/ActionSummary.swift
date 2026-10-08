import Foundation

/// The Office tab's calm last-action column: Cat Office's raw label ("Bash: cd ~/x && grep -n …", "Read a/b/c.md")
/// in plain words ("Running a command · grep", "Read a file · c.md"). Commands show only the program, files only their
/// name, searches and web pages nothing typed, so private text stays off the screen. The raw label is for hovering.
public enum ActionSummary {
    public static func calm(_ label: String, working: Bool) -> String {
        let label = label.trimmingCharacters(in: .whitespaces)
        guard !label.isEmpty else { return "" }
        // Cat Office's labels: "Tool: rest", "Tool rest", or a whole phrase ("Asked a question", "server · tool").
        let tool = String(label.prefix { !$0.isWhitespace && $0 != ":" })
        let rest = label.dropFirst(tool.count).drop { $0 == ":" || $0.isWhitespace }.description
        func verb(_ now: String, _ done: String) -> String { working ? now : done }
        func file() -> String? { rest.isEmpty ? nil : URL(fileURLWithPath: rest).lastPathComponent }

        switch tool {
        case "Bash":
            let ran = verb("Running a command", "Ran a command")
            return program(in: rest).map { "\(ran) · \($0)" } ?? ran
        case "Read":
            let read = verb("Reading a file", "Read a file")
            return file().map { "\(read) · \($0)" } ?? read
        case "Edit", "NotebookEdit":
            return file().map { "\(verb("Editing", "Edited")) \($0)" } ?? verb("Editing a file", "Edited a file")
        case "Write":
            return file().map { "\(verb("Writing", "Wrote")) \($0)" } ?? verb("Writing a file", "Wrote a file")
        case "Grep": return verb("Searching the code", "Searched the code")
        case "Glob": return verb("Looking for files", "Looked for files")
        case "WebSearch": return verb("Searching the web", "Searched the web")
        case "WebFetch":
            let opened = verb("Opening a web page", "Opened a web page")
            return URL(string: rest)?.host.map { "\(opened) · \($0)" } ?? opened
        case "Agent", "Task": return verb("Starting a helper", "Started a helper")
        case "Skill":
            let used = verb("Using a skill", "Used a skill")
            return rest.isEmpty ? used : "\(used) · \(rest)"
        case "SendMessage": return verb("Sending a message", "Sent a message")
        default:
            // An MCP tool ("server · tool"): just the server.
            if label.contains(" · ") {
                return "\(verb("Using a tool", "Used a tool")) · \(label.prefix { $0 != " " })"
            }
            return label
        }
    }

    /// The program doing the work in a shell command: the first word of the first part that isn't `cd` and friends,
    /// past `VAR=value` and `sudo`, without its folder. Nil when there is none (e.g. just `cd x`).
    static func program(in command: String) -> String? {
        let skip: Set<String> = ["cd", "pushd", "popd", "export", "source", ".", "set", "unset", "sudo", "env", "time", "exec"]
        let parts = command.components(separatedBy: CharacterSet(charactersIn: "&|;()\n"))
        for part in parts {
            for word in part.split(whereSeparator: { $0.isWhitespace }).map(String.init) {
                if word.contains("=") && !word.hasPrefix("=") { continue }   // FOO=1
                let name = URL(fileURLWithPath: word).lastPathComponent
                if skip.contains(name) {
                    if name == "sudo" || name == "env" || name == "time" || name == "exec" { continue }
                    break   // cd x: the rest of this part is its argument
                }
                guard name.first.map({ $0.isLetter || $0.isNumber }) == true, name != "…" else { break }
                return name
            }
        }
        return nil
    }
}

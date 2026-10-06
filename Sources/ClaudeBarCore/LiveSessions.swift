import Foundation

public enum AgentStatus: String, Sendable, Equatable {
    case working, waiting, idle, ended

    /// For picking one status to show for several sessions: waiting > working > idle > ended.
    public var urgency: Int {
        switch self {
        case .waiting: 3
        case .working: 2
        case .idle: 1
        case .ended: 0
        }
    }
}

/// A Claude Code session whose process is running.
public struct LiveSession: Equatable, Sendable {
    /// The session id (or Cat Office's agent id when it has none); the key snapshots use too.
    public var key: String
    /// Normalized folder the session runs in.
    public var cwd: String
    public var status: AgentStatus
    public var name: String
    public var model: String?
    public var isOffice: Bool
    public var task: String?

    public init(key: String, cwd: String, status: AgentStatus, name: String, model: String? = nil, isOffice: Bool = false, task: String? = nil) {
        self.key = key
        self.cwd = cwd
        self.status = status
        self.name = name
        self.model = model
        self.isOffice = isOffice
        self.task = task
    }
}

public func processIsAlive(_ pid: Int32) -> Bool {
    kill(pid, 0) == 0 || errno == EPERM
}

/// Reads Claude Code's own session registry (~/.claude/sessions/<pid>.json); the fallback when Cat Office isn't running.
public struct LiveSessionReader: Sendable {
    public var dir: URL
    public var isAlive: @Sendable (Int32) -> Bool

    public init(dir: URL = Paths.claudeSessionsDir, isAlive: @escaping @Sendable (Int32) -> Bool = processIsAlive) {
        self.dir = dir
        self.isAlive = isAlive
    }

    public func read() -> [LiveSession] {
        guard let names = try? FileManager.default.contentsOfDirectory(atPath: dir.path) else { return [] }
        var out: [LiveSession] = []
        for name in names.sorted() where name.hasSuffix(".json") {
            guard let data = try? Data(contentsOf: dir.appendingPathComponent(name)),
                  let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let pid = obj["pid"] as? Int,
                  let sessionId = obj["sessionId"] as? String, !sessionId.isEmpty,
                  isAlive(Int32(pid)) else { continue }
            let waitingFor = obj["waitingFor"]
            let raw = obj["status"] as? String
            let status: AgentStatus
            if let w = waitingFor, !(w is NSNull), !((w as? String)?.isEmpty ?? false) {
                status = .waiting
            } else if raw == "busy" {
                status = .working
            } else if raw == "waiting" {
                status = .waiting
            } else {
                status = .idle
            }
            let sessionName = obj["name"] as? String ?? sessionId
            out.append(LiveSession(
                key: sessionId,
                cwd: Paths.normalize(obj["cwd"] as? String ?? ""),
                status: status,
                name: sessionName,
                isOffice: sessionName.hasPrefix("office-") && obj["entrypoint"] as? String == "sdk-cli"
            ))
        }
        return out
    }
}

public struct GitBranchReader: Sendable {
    public var timeout: TimeInterval

    public init(timeout: TimeInterval = 2) {
        self.timeout = timeout
    }

    /// The checked-out branch, "detached" for a detached HEAD, or nil when `path` isn't in a git work tree
    /// (or git fails or takes longer than `timeout`).
    public func branch(at path: String) -> String? {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        p.arguments = ["-C", path, "--no-optional-locks", "symbolic-ref", "--short", "-q", "HEAD"]
        let out = Pipe()
        p.standardOutput = out
        p.standardError = FileHandle.nullDevice
        let done = DispatchSemaphore(value: 0)
        p.terminationHandler = { _ in done.signal() }
        do { try p.run() } catch { return nil }
        if done.wait(timeout: .now() + timeout) == .timedOut {
            p.terminate()
            return nil
        }
        let text = String(decoding: out.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        switch p.terminationStatus {
        case 0: return text.isEmpty ? nil : text
        case 1: return "detached"
        default: return nil
        }
    }
}

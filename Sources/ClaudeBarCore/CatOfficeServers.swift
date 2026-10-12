import Foundation

/// Every Cat Office dev server running from a folder, on any port. Two copies of one Cat Office each run their own
/// office (the browser shares with one, ClaudeBar may read the other), so the cats disagree.
public enum CatOfficeServers {
    public struct Server: Equatable, Sendable {
        public var pid: Int32
        public var port: Int

        public init(pid: Int32, port: Int) {
            self.pid = pid
            self.port = port
        }
    }

    /// `lsof -iTCP -sTCP:LISTEN -Fpn` output: each process's lowest listening port (vite's own; its HMR socket is higher).
    static func listening(_ out: String) -> [Int32: Int] {
        var ports: [Int32: Int] = [:]
        var pid: Int32?
        for line in out.split(separator: "\n") {
            if line.hasPrefix("p") { pid = Int32(line.dropFirst()) }
            if line.hasPrefix("n"), let pid, let colon = line.lastIndex(of: ":"), let port = Int(line[line.index(after: colon)...]) {
                ports[pid] = min(ports[pid] ?? port, port)
            }
        }
        return ports
    }

    /// `lsof -d cwd -Fpn` output: each process's working folder.
    static func folders(_ out: String) -> [Int32: String] {
        var dirs: [Int32: String] = [:]
        var pid: Int32?
        for line in out.split(separator: "\n") {
            if line.hasPrefix("p") { pid = Int32(line.dropFirst()) }
            if line.hasPrefix("n"), let pid { dirs[pid] = String(line.dropFirst()) }
        }
        return dirs
    }

    /// The Cat Office (vite) dev servers listening with `folder` as their working folder, lowest port first.
    public static func find(folder: String) -> [Server] {
        let want = Paths.normalize(folder)
        guard !want.isEmpty else { return [] }
        let ports = listening(run("/usr/sbin/lsof", ["-nP", "-iTCP", "-sTCP:LISTEN", "-a", "-c", "node", "-Fpn"]))
        guard !ports.isEmpty else { return [] }
        let dirs = folders(run("/usr/sbin/lsof", ["-a", "-p", ports.keys.map(String.init).joined(separator: ","), "-d", "cwd", "-Fpn"]))
        return ports.compactMap { pid, port in
            guard let dir = dirs[pid], Paths.normalize(dir) == want,
                  run("/bin/ps", ["-o", "command=", "-p", String(pid)]).contains("vite") else { return nil }
            return Server(pid: pid, port: port)
        }
        .sorted { $0.port < $1.port }
    }

    /// The copies to stop so one is left: all but the one ClaudeBar reads (`connectedPort`), else all but the lowest port.
    public static func extra(_ servers: [Server], connectedPort: Int?) -> [Server] {
        guard servers.count > 1 else { return [] }
        let keep = servers.first { $0.port == connectedPort } ?? servers.min { $0.port < $1.port }!
        return servers.filter { $0 != keep }
    }

    /// Stops one copy: its vite server (its `npm run dev` exits with it).
    public static func stop(_ server: Server) {
        kill(server.pid, SIGTERM)
    }

    private static func run(_ path: String, _ args: [String]) -> String {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: path)
        p.arguments = args
        let out = Pipe()
        p.standardOutput = out
        p.standardError = FileHandle.nullDevice
        do { try p.run() } catch { return "" }
        let data = out.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        return String(decoding: data, as: UTF8.self)
    }
}

/// Settings' line on ClaudeBar's link to Cat Office, in plain words ("Connected, copying your browser page"), and the
/// address and how fresh it is for hovering ("localhost:5173, updated 2 s ago").
public enum ConnectionLine {
    public static func text(url: URL?, lastUpdate: Date?, placesLive: Bool, copies: Int, now: Date) -> (line: String, detail: String?) {
        guard let url, let lastUpdate else { return ("Not connected to Cat Office", nil) }
        let host = url.host.map { h in url.port.map { "\(h):\($0)" } ?? h } ?? url.absoluteString
        let age = now.timeIntervalSince(lastUpdate)
        let updated = age < 1 ? "just now" : age < 60 ? "\(Int(age)) s ago" : "\(Int(age / 60)) min ago"
        let line = copies > 1 ? "Connected, but two copies of Cat Office are running"
            : placesLive ? "Connected, copying your browser page"
            : "Connected. No browser page is open, so ClaudeBar runs the office itself"
        return (line, "\(host), updated \(updated)")
    }
}

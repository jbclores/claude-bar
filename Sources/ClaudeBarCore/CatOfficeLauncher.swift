import Foundation

/// Starts Cat Office's dev server (`npm run dev` in its folder) when nothing answers at its address.
public struct CatOfficeLauncher: Sendable {
    public enum Result: Equatable, Sendable {
        case started
        case alreadyRunning
        /// No `catOffice.dir`, or it isn't a folder.
        case notConfigured
        case npmNotFound
        case failed(String)
    }

    public static var logFile: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Logs/ClaudeBar/cat-office.log")
    }

    public init() {}

    public func start(settings: CatOfficeSettings, log: URL = CatOfficeLauncher.logFile) async -> Result {
        var isDir: ObjCBool = false
        guard let dir = settings.dir, FileManager.default.fileExists(atPath: dir, isDirectory: &isDir), isDir.boolValue else {
            return .notConfigured
        }
        if await Self.answers(settings.url) { return .alreadyRunning }
        guard let bin = Self.nodeBinDir(home: NSHomeDirectory()) else { return .npmNotFound }
        do {
            try FileManager.default.createDirectory(at: log.deletingLastPathComponent(), withIntermediateDirectories: true)
            if !FileManager.default.fileExists(atPath: log.path) { FileManager.default.createFile(atPath: log.path, contents: nil) }
            let handle = try FileHandle(forWritingTo: log)
            handle.seekToEndOfFile()
            handle.write(Data("\n--- ClaudeBar started Cat Office \(Date()) ---\n".utf8))
            let p = Process()
            p.executableURL = URL(fileURLWithPath: bin).appendingPathComponent("npm")
            p.arguments = ["run", "dev"]
            p.currentDirectoryURL = URL(fileURLWithPath: dir)
            let base = ProcessInfo.processInfo.environment
            p.environment = Self.environment(binDir: bin, base: base,
                                             loginPath: Self.loginShellPath(shell: base["SHELL"] ?? "/bin/zsh"),
                                             home: NSHomeDirectory())
            p.standardInput = FileHandle.nullDevice
            p.standardOutput = handle
            p.standardError = handle
            try p.run()
            try? handle.close() // the child keeps its own copy
            return .started
        } catch {
            return .failed(error.localizedDescription)
        }
    }

    /// True when anything answers HTTP at `url` within 2 seconds.
    public static func answers(_ url: URL) async -> Bool {
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 2)
        request.httpMethod = "GET"
        return (try? await URLSession.shared.data(for: request)) != nil
    }

    /// Node.js (with npm) is installed where ClaudeBar can start Cat Office with it.
    public static func hasNode(home: String) -> Bool { nodeBinDir(home: home) != nil }

    /// The first folder holding both `npm` and `node`: the system folders, then Volta, then the newest nvm version.
    public static func nodeBinDir(home: String, systemDirs: [String] = ["/opt/homebrew/bin", "/usr/local/bin"]) -> String? {
        let fm = FileManager.default
        var candidates = systemDirs + [home + "/.volta/bin"]
        let nvm = home + "/.nvm/versions/node"
        if let versions = try? fm.contentsOfDirectory(atPath: nvm), let newest = newestVersion(versions) {
            candidates.append("\(nvm)/\(newest)/bin")
        }
        return candidates.first { fm.fileExists(atPath: $0 + "/npm") && fm.fileExists(atPath: $0 + "/node") }
    }

    static func newestVersion(_ names: [String]) -> String? {
        func parts(_ name: String) -> [Int]? {
            guard name.hasPrefix("v") else { return nil }
            let nums = name.dropFirst().split(separator: ".").compactMap { Int($0) }
            return nums.isEmpty ? nil : nums
        }
        return names.compactMap { name in parts(name).map { (name, $0) } }
            .max { $0.1.lexicographicallyPrecedes($1.1) }?.0
    }

    /// A PATH like a terminal's (Cat Office passes it on to its agents and tools): node's folder, the usual
    /// user and Homebrew folders, the login shell's PATH, then what the app got from launchd.
    static func environment(binDir: String, base: [String: String], loginPath: String?, home: String) -> [String: String] {
        var env = base
        let usual: [String] = [binDir, home + "/.local/bin", "/opt/homebrew/bin", "/opt/homebrew/sbin", "/usr/local/bin"]
        let login: [String] = (loginPath ?? "").split(separator: ":").map(String.init)
        let inherited: [String] = (base["PATH"] ?? "/usr/bin:/bin:/usr/sbin:/sbin").split(separator: ":").map(String.init)
        let parts = usual + login + inherited
        var seen = Set<String>()
        env["PATH"] = parts.filter { !$0.isEmpty && seen.insert($0).inserted }.joined(separator: ":")
        return env
    }

    /// The PATH a login shell sets up (apps opened from Finder don't get it), or nil when the shell fails or hangs.
    static func loginShellPath(shell: String, timeout: TimeInterval = 3) -> String? {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: shell)
        p.arguments = ["-l", "-c", "printf %s \"$PATH\""]
        let out = Pipe()
        p.standardOutput = out
        p.standardError = FileHandle.nullDevice
        p.standardInput = FileHandle.nullDevice
        let done = DispatchSemaphore(value: 0)
        p.terminationHandler = { _ in done.signal() }
        do { try p.run() } catch { return nil }
        if done.wait(timeout: .now() + timeout) == .timedOut {
            p.terminate()
            return nil
        }
        let path = String(decoding: out.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return p.terminationStatus == 0 && path.contains("/") ? path : nil
    }
}

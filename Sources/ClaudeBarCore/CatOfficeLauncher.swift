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
            p.environment = Self.environment(binDir: bin, base: ProcessInfo.processInfo.environment)
            p.standardInput = FileHandle.nullDevice
            p.standardOutput = handle
            p.standardError = handle
            try p.run()
            return .started
        } catch {
            return .failed(error.localizedDescription)
        }
    }

    /// True when anything answers HTTP at `url` within 2 seconds.
    static func answers(_ url: URL) async -> Bool {
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 2)
        request.httpMethod = "GET"
        return (try? await URLSession.shared.data(for: request)) != nil
    }

    /// The first folder holding both `npm` and `node`: the system folders, then Volta, then the newest nvm version.
    static func nodeBinDir(home: String, systemDirs: [String] = ["/opt/homebrew/bin", "/usr/local/bin"]) -> String? {
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

    static func environment(binDir: String, base: [String: String]) -> [String: String] {
        var env = base
        env["PATH"] = [binDir, base["PATH"] ?? "/usr/bin:/bin:/usr/sbin:/sbin"].joined(separator: ":")
        return env
    }
}

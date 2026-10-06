import Foundation

public struct Project: Equatable, Sendable {
    /// Normalized absolute path.
    public var path: String
    public var name: String

    public init(path: String, name: String) {
        self.path = path
        self.name = name
    }
}

public struct CatOfficeSettings: Equatable, Sendable {
    public static let defaultURL = URL(string: "http://localhost:5173")!
    /// Normalized path of the Cat Office folder (holds .cat-office/bridge.json), if configured.
    public var dir: String?
    public var url: URL

    public init(dir: String? = nil, url: URL = CatOfficeSettings.defaultURL) {
        self.dir = dir
        self.url = url
    }
}

public struct Config: Equatable, Sendable {
    public var projects: [Project]
    public var catOffice: CatOfficeSettings
    public var notifications: Bool

    public static let empty = Config(projects: [], catOffice: CatOfficeSettings(), notifications: true)

    public init(projects: [Project], catOffice: CatOfficeSettings, notifications: Bool) {
        self.projects = projects
        self.catOffice = catOffice
        self.notifications = notifications
    }

    public static func parse(_ data: Data) throws -> Config {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw ConfigError(message: "not a JSON object")
        }
        var config = Config.empty
        if let raw = root["projects"] {
            guard let list = raw as? [[String: Any]] else { throw ConfigError(message: "\"projects\" must be a list") }
            config.projects = try list.map { item in
                guard let path = item["path"] as? String, !path.isEmpty else {
                    throw ConfigError(message: "every project needs a \"path\"")
                }
                let normalized = Paths.normalize(path)
                let name = (item["name"] as? String).flatMap { $0.isEmpty ? nil : $0 }
                    ?? (normalized as NSString).lastPathComponent
                return Project(path: normalized, name: name)
            }
        }
        if let office = root["catOffice"] as? [String: Any] {
            if let dir = office["dir"] as? String, !dir.isEmpty { config.catOffice.dir = Paths.normalize(dir) }
            if let s = office["url"] as? String, let url = URL(string: s) { config.catOffice.url = url }
        }
        if let n = root["notifications"] as? Bool { config.notifications = n }
        return config
    }
}

public struct ConfigError: Error, Equatable {
    public var message: String
}

/// The user's config file (~/.config/claude-bar/projects.json): read, watched by modification time, and edited.
public final class ConfigStore {
    public let file: URL
    public private(set) var config: Config = .empty
    /// Set while the file can't be parsed; `config` then holds the last good one.
    public private(set) var error: String?
    private var lastModified: Date?
    private var loaded = false

    public init(file: URL = Paths.configFile) {
        self.file = file
    }

    /// Creates the file if it's missing, then re-reads it when its modification time changed.
    /// Returns true when `config` or `error` changed.
    @discardableResult
    public func reload() -> Bool {
        let fm = FileManager.default
        if !fm.fileExists(atPath: file.path) {
            try? fm.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? Data("{\n  \"projects\" : []\n}\n".utf8).write(to: file, options: .atomic)
        }
        let modified = (try? fm.attributesOfItem(atPath: file.path))?[.modificationDate] as? Date
        if loaded, modified == lastModified { return false }
        loaded = true
        lastModified = modified
        let before = (config, error)
        do {
            config = try Config.parse(Data(contentsOf: file))
            error = nil
        } catch let e as ConfigError {
            error = "Config error (\(e.message)) — using last good list"
        } catch {
            self.error = "Config error — using last good list"
        }
        return before.0 != config || before.1 != error
    }

    /// Adds folders not already listed (compared after normalizing), keeping the order and every other key.
    public func add(paths: [String]) throws {
        try editProjects { projects in
            var seen = Set(projects.compactMap { ($0["path"] as? String).map(Paths.normalize) })
            for path in paths where seen.insert(Paths.normalize(path)).inserted {
                projects.append(["path": (path as NSString).abbreviatingWithTildeInPath])
            }
        }
    }

    public func remove(path: String) throws {
        let target = Paths.normalize(path)
        try editProjects { projects in
            projects.removeAll { ($0["path"] as? String).map(Paths.normalize) == target }
        }
    }

    private func editProjects(_ change: (inout [[String: Any]]) -> Void) throws {
        var root: [String: Any] = [:]
        if let data = try? Data(contentsOf: file) {
            guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                throw ConfigError(message: "the config file is invalid; fix it before editing from the app")
            }
            root = object
        }
        var projects = root["projects"] as? [[String: Any]] ?? []
        change(&projects)
        root["projects"] = projects
        let data = try JSONSerialization.data(withJSONObject: root, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: file, options: .atomic)
        loaded = false
        reload()
    }
}

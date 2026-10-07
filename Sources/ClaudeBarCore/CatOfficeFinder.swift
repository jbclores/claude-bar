import Foundation

/// A Cat Office folder found on this Mac.
public struct CatOfficeCandidate: Equatable, Sendable {
    public var path: String
    public var modified: Date
    public var running: Bool

    public init(path: String, modified: Date, running: Bool) {
        self.path = path
        self.modified = modified
        self.running = running
    }
}

/// Finds Cat Office copies: the running one, the saved one, then the usual places (two levels deep).
public enum CatOfficeFinder {
    /// Cat Office: a package.json and its server/agent-bridge folder.
    public static func isCatOffice(_ path: String) -> Bool {
        var dir: ObjCBool = false
        return FileManager.default.fileExists(atPath: path + "/package.json")
            && FileManager.default.fileExists(atPath: path + "/server/agent-bridge", isDirectory: &dir) && dir.boolValue
    }

    public static func defaultRoots(home: String) -> [String] {
        ["Documents", "Documents/projects", "Downloads", "Desktop", "Developer", "Projects"].map { home + "/" + $0 }
    }

    /// Cat Office folders under `roots`, up to `depth` levels down; never inside one already found, never hidden or
    /// node_modules folders.
    public static func search(roots: [String], depth: Int = 2) -> [String] {
        var found: [String] = []
        func walk(_ dir: String, _ level: Int) {
            guard level <= depth, let names = try? FileManager.default.contentsOfDirectory(atPath: dir) else { return }
            for name in names.sorted() where !name.hasPrefix(".") && name != "node_modules" {
                let path = dir + "/" + name
                var isDir: ObjCBool = false
                guard FileManager.default.fileExists(atPath: path, isDirectory: &isDir), isDir.boolValue else { continue }
                if isCatOffice(path) { found.append(path) } else { walk(path, level + 1) }
            }
        }
        for root in roots { walk(root, 1) }
        return found
    }

    /// The running copy first, then the saved one, then the rest newest first; each real folder once.
    public static func candidates(running: String?, saved: String?, roots: [String]) -> [CatOfficeCandidate] {
        var seen = Set<String>()
        var out: [CatOfficeCandidate] = []
        func add(_ path: String, running: Bool) {
            let real = URL(fileURLWithPath: path).resolvingSymlinksInPath().path
            guard isCatOffice(real), seen.insert(real).inserted else { return }
            out.append(CatOfficeCandidate(path: real, modified: modified(real), running: running))
        }
        if let running { add(running, running: true) }
        if let saved { add(saved, running: false) }
        let head = out.count
        for path in search(roots: roots) { add(path, running: false) }
        // Sort the searched part (from index head onwards) by modification date (newest first)
        let searchedPart = out[head...].sorted { $0.modified > $1.modified }
        out = Array(out[..<head]) + searchedPart
        return out
    }

    static func modified(_ path: String) -> Date {
        ((try? FileManager.default.attributesOfItem(atPath: path + "/package.json"))?[.modificationDate] as? Date) ?? .distantPast
    }
}

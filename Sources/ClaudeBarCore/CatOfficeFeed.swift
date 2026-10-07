import Foundation

/// Splits a server-sent event stream into each event's data, one byte at a time.
public struct SSEParser: Sendable {
    private var buffer: [UInt8] = []

    public init() {}

    /// Returns the event's data (data lines joined by "\n") when `byte` completes an event that has any.
    public mutating func feed(_ byte: UInt8) -> String? {
        if byte == 13 { return nil } // CRLF counts as LF
        buffer.append(byte)
        guard byte == 10, buffer.count >= 2, buffer[buffer.count - 2] == 10 else { return nil }
        let block = String(decoding: buffer, as: UTF8.self)
        buffer.removeAll(keepingCapacity: true)
        let lines = block.split(separator: "\n").filter { $0.hasPrefix("data:") }.map { line -> Substring in
            let value = line.dropFirst(5)
            return value.first == " " ? value.dropFirst() : value
        }
        return lines.isEmpty ? nil : lines.joined(separator: "\n")
    }
}

public enum CatOfficeEvent: Equatable, Sendable {
    case snapshot(OfficeSnapshot)
    case other

    public static func decode(_ data: String) -> CatOfficeEvent? {
        struct Envelope: Decodable {
            var type: String
            var snapshot: OfficeSnapshot?
        }
        guard let envelope = try? JSONDecoder().decode(Envelope.self, from: Data(data.utf8)) else { return nil }
        if envelope.type == "snapshot", let snapshot = envelope.snapshot { return .snapshot(snapshot) }
        return .other
    }
}

public struct BridgeInfo: Equatable, Sendable {
    public var url: URL
    public var token: String
    /// Cat Office's folder, when the patched Cat Office reported it.
    public var dir: String?

    public init(url: URL, token: String, dir: String? = nil) {
        self.url = url
        self.token = token
        self.dir = dir
    }
}

/// Which start of Cat Office wrote the bridge file: its pid and per-start token, and its folder.
public struct BridgeStamp: Equatable, Sendable {
    public var pid: Int32
    public var token: String
    public var dir: String?

    public init(pid: Int32, token: String, dir: String?) {
        self.pid = pid
        self.token = token
        self.dir = dir
    }
}

public enum CatOfficeDiscovery {
    /// The per-start token Cat Office puts in its page as `window.__CAT_OFFICE_TOKEN__ = "…"`.
    public static func token(inPage html: String) -> String? {
        guard let range = html.range(of: #"__CAT_OFFICE_TOKEN__\s*=\s*"[^"]+""#, options: .regularExpression) else { return nil }
        let match = html[range]
        guard let open = match.firstIndex(of: "\"") else { return nil }
        let rest = match[match.index(after: open)...]
        guard let close = rest.firstIndex(of: "\"") else { return nil }
        return String(rest[..<close])
    }

    /// Where the patched Cat Office says where it runs, wherever its folder is.
    public static var bridgeFile: URL { Paths.home.appendingPathComponent(".cat-office/bridge.json") }

    /// The bridge file's address, token and folder, only while the process that wrote it runs.
    public static func bridgeInfo(file: URL = bridgeFile, isAlive: (Int32) -> Bool) -> BridgeInfo? {
        guard let data = try? Data(contentsOf: file),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let urlString = obj["url"] as? String, let url = URL(string: urlString),
              let token = obj["token"] as? String, !token.isEmpty,
              let pid = obj["pid"] as? Int, isAlive(Int32(pid)) else { return nil }
        let dir = (obj["dir"] as? String).flatMap { $0.isEmpty ? nil : Paths.normalize($0) }
        return BridgeInfo(url: url, token: token, dir: dir)
    }

    /// The bridge file's pid, token and folder, only while that process runs.
    public static func bridgeStamp(file: URL = bridgeFile, isAlive: (Int32) -> Bool) -> BridgeStamp? {
        guard let data = try? Data(contentsOf: file),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let token = obj["token"] as? String, !token.isEmpty,
              let pid = obj["pid"] as? Int, isAlive(Int32(pid)) else { return nil }
        return BridgeStamp(pid: Int32(pid), token: token, dir: (obj["dir"] as? String).flatMap { $0.isEmpty ? nil : Paths.normalize($0) })
    }

    /// Cat Office reloaded (after the patch changed its server files): the bridge names `dir` again, written by a new
    /// start (another pid, or the same process with a new token).
    public static func reloaded(before: BridgeStamp?, after: BridgeStamp?, dir: String) -> Bool {
        guard let after, after.dir.map(Paths.normalize) == Paths.normalize(dir) else { return false }
        guard let before else { return true }
        return after.pid != before.pid || after.token != before.token
    }

    /// The process's executable is node (or npm): Cat Office's dev server, not a stale pid reused by something else.
    public static func isNodeOrNpm(_ pid: Int32) -> Bool {
        var buffer = [CChar](repeating: 0, count: 4 * Int(MAXPATHLEN))
        guard proc_pidpath(pid, &buffer, UInt32(buffer.count)) > 0 else { return false }
        let name = URL(fileURLWithPath: String(cString: buffer)).lastPathComponent
        return name == "node" || name == "npm"
    }

    /// A bridge pid to trust: alive and node/npm.
    public static func isCatOfficeProcess(_ pid: Int32) -> Bool {
        pid > 0 && processIsAlive(pid) && isNodeOrNpm(pid)
    }

    /// The folder to start Cat Office from: the configured one if it exists, else the one last seen running.
    public static func folderToStart(configured: String?, remembered: String?) -> String? {
        [configured, remembered].compactMap { $0 }.first { path in
            var isDir: ObjCBool = false
            return FileManager.default.fileExists(atPath: path, isDirectory: &isDir) && isDir.boolValue
        }
    }
}

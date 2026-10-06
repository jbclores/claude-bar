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

    public init(url: URL, token: String) {
        self.url = url
        self.token = token
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

    /// `<dir>/.cat-office/bridge.json` (written by the patched Cat Office), only while its process runs.
    public static func bridgeInfo(catOfficeDir: String, isAlive: (Int32) -> Bool) -> BridgeInfo? {
        let file = URL(fileURLWithPath: Paths.normalize(catOfficeDir)).appendingPathComponent(".cat-office/bridge.json")
        guard let data = try? Data(contentsOf: file),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let urlString = obj["url"] as? String, let url = URL(string: urlString),
              let token = obj["token"] as? String, !token.isEmpty,
              let pid = obj["pid"] as? Int, isAlive(Int32(pid)) else { return nil }
        return BridgeInfo(url: url, token: token)
    }
}

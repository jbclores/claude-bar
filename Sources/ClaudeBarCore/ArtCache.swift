import Foundation
import ImageIO

public enum CatPose: String, Sendable {
    case typing, waving, sleeping

    public init(status: AgentStatus) {
        switch status {
        case .working: self = .typing
        case .waiting: self = .waving
        case .idle, .ended: self = .sleeping
        }
    }
}

/// Cat Office's cat list and sprite path templates (/data/cats.json).
public struct CatCatalog: Equatable, Sendable {
    public var catIds: [String]
    var standingPath: String
    var typePath: String
    var sleepPath: String

    public static func parse(_ data: Data) -> CatCatalog? {
        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let cats = obj["cats"] as? [[String: Any]] else { return nil }
        return CatCatalog(
            catIds: cats.compactMap { $0["id"] as? String },
            standingPath: obj["path"] as? String ?? "assets/cats/{cat}/{direction}/{gesture}.png",
            typePath: obj["typePath"] as? String ?? "assets/cats/{cat}/{direction}/type.png",
            sleepPath: obj["sleepPath"] as? String ?? "assets/cats/{cat}/sleep.png")
    }

    public func path(cat: String, pose: CatPose) -> String {
        let template: String
        var direction = "front-left"
        switch pose {
        case .typing:
            template = typePath
            direction = "back-left" // facing the desk, away from us
        case .waving: template = standingPath
        case .sleeping: template = sleepPath
        }
        return template
            .replacingOccurrences(of: "{cat}", with: cat)
            .replacingOccurrences(of: "{direction}", with: direction)
            .replacingOccurrences(of: "{gesture}", with: "right-up")
    }
}

public enum CatPicker {
    /// FNV-1a over UTF-16 code units, as Cat Office's `portraitCat` does.
    public static func fnv1a(_ s: String) -> UInt32 {
        var hash: UInt32 = 0x811C_9DC5
        for unit in s.utf16 {
            hash ^= UInt32(unit)
            hash = hash &* 0x0100_0193
        }
        return hash
    }

    /// Cat Office's fallback face for an agent with no cat assigned.
    public static func portraitCat(_ agentId: String, catIds: [String]) -> String {
        catIds.isEmpty ? "" : catIds[Int(fnv1a(agentId) % UInt32(catIds.count))]
    }

    /// The browser's cat when the patched Cat Office reports it, else the fallback.
    public static func cat(for agent: OfficeAgent, catIds: [String]) -> String {
        if let cat = agent.cat, !cat.isEmpty { return cat }
        return portraitCat(agent.id, catIds: catIds)
    }
}

/// Sprites from Cat Office (served without a token), shrunk and kept in ~/Library/Caches/ClaudeBar/art.
public final class ArtCache: @unchecked Sendable {
    private let dir: URL
    private let baseURL: @Sendable () -> URL
    private let session: URLSession
    private let memory = LockedBox<[String: Data]>([:])
    private let catalogBox = LockedBox<CatCatalog?>(nil)
    private let deskBox = LockedBox<String?>(nil)

    public init(dir: URL = Paths.artCacheDir, baseURL: @escaping @Sendable () -> URL, session: URLSession = .shared) {
        self.dir = dir
        self.baseURL = baseURL
        self.session = session
    }

    public func catalog() async -> CatCatalog? {
        if let cached = catalogBox.get() { return cached }
        guard let data = await json("data/cats.json"), let catalog = CatCatalog.parse(data) else { return nil }
        catalogBox.set(catalog)
        return catalog
    }

    public func catImage(cat: String, pose: CatPose) async -> Data? {
        guard let catalog = await catalog() else { return nil }
        return await image(path: catalog.path(cat: cat, pose: pose))
    }

    /// The first desk in Cat Office's /data/desks.json.
    public func deskImage() async -> Data? {
        if deskBox.get() == nil,
           let data = await json("data/desks.json"),
           let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let desks = obj["desks"] as? [[String: Any]],
           let image = desks.first?["image"] as? String {
            deskBox.set(image)
        }
        guard let path = deskBox.get() else { return nil }
        return await image(path: path)
    }

    /// A shrunken PNG of the asset at `path`, from memory, then disk, then Cat Office.
    public func image(path: String, maxPixelSize: Int = 128) async -> Data? {
        let key = path.replacingOccurrences(of: "/", with: "_")
        if let data = memory.get()[key] { return data }
        let file = dir.appendingPathComponent(key)
        if let data = try? Data(contentsOf: file) {
            memory.update { $0[key] = data }
            return data
        }
        guard let raw = await fetch(path), let small = Self.shrink(raw, maxPixelSize: maxPixelSize) else { return nil }
        save(small, to: file)
        memory.update { $0[key] = small }
        return small
    }

    /// A JSON file from Cat Office, refreshed when it answers, else the copy cached last time.
    private func json(_ path: String) async -> Data? {
        let file = dir.appendingPathComponent(path.replacingOccurrences(of: "/", with: "_"))
        if let data = await fetch(path) {
            save(data, to: file)
            return data
        }
        return try? Data(contentsOf: file)
    }

    private func fetch(_ path: String) async -> Data? {
        let url = baseURL().appendingPathComponent(path)
        guard let (data, response) = try? await session.data(from: url),
              (response as? HTTPURLResponse)?.statusCode == 200 else { return nil }
        return data
    }

    private func save(_ data: Data, to file: URL) {
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try? data.write(to: file, options: .atomic)
    }

    /// The image cropped to its non-transparent pixels (so a sprite fills a small icon), as PNG.
    public static func trimmed(_ data: Data) -> Data? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else { return nil }
        let w = image.width, h = image.height
        guard let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                                  space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue),
              let pixels = ctx.data?.assumingMemoryBound(to: UInt8.self) else { return nil }
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        var minX = w, minY = h, maxX = -1, maxY = -1
        for y in 0..<h {
            for x in 0..<w where pixels[(y * w + x) * 4 + 3] > 10 {
                minX = min(minX, x); maxX = max(maxX, x); minY = min(minY, y); maxY = max(maxY, y)
            }
        }
        guard maxX >= minX, maxY >= minY,
              let cropped = ctx.makeImage()?.cropping(to: CGRect(x: minX, y: minY, width: maxX - minX + 1, height: maxY - minY + 1))
        else { return nil }
        let out = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(out, "public.png" as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(dest, cropped, nil)
        return CGImageDestinationFinalize(dest) ? out as Data : nil
    }

    static func shrink(_ data: Data, maxPixelSize: Int) -> Data? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                  kCGImageSourceCreateThumbnailFromImageAlways: true,
                  kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
                  kCGImageSourceCreateThumbnailWithTransform: true,
              ] as CFDictionary) else { return nil }
        let out = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(out, "public.png" as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(dest, image, nil)
        return CGImageDestinationFinalize(dest) ? out as Data : nil
    }
}

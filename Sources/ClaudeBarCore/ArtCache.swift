import Foundation
import ImageIO

public enum CatPose: String, Sendable {
    case typing, waving, sleeping
    /// Standing, paws down: working at a turned desk (Cat Office has no front-facing typing sprite).
    case standing

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

    /// The sprite for a pose; `direction` defaults to back-left for typing and front-left otherwise.
    public func path(cat: String, pose: CatPose, direction: String? = nil) -> String {
        let template: String
        var gesture = "right-up"
        switch pose {
        case .typing: template = typePath
        case .waving: template = standingPath
        case .standing:
            template = standingPath
            gesture = "both-down"
        case .sleeping: template = sleepPath
        }
        return template
            .replacingOccurrences(of: "{cat}", with: cat)
            .replacingOccurrences(of: "{direction}", with: direction ?? (pose == .typing ? "back-left" : "front-left"))
            .replacingOccurrences(of: "{gesture}", with: gesture)
    }
}

/// Cat Office's desk designs (/data/desks.json): front and rear sprite per design.
public struct DeskCatalog: Equatable, Sendable {
    struct Entry: Equatable, Sendable {
        var id: String
        var image: String
        var rearImage: String?
    }

    var entries: [Entry]

    public static func parse(_ data: Data) -> DeskCatalog {
        let obj = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        let desks = obj?["desks"] as? [[String: Any]] ?? []
        return DeskCatalog(entries: desks.compactMap { d in
            guard let id = d["id"] as? String, let image = d["image"] as? String else { return nil }
            return Entry(id: id, image: image, rearImage: (d["rear"] as? [String: Any])?["image"] as? String)
        })
    }

    /// The sprite for a design (its rear view when turned, if it has one); the first design when unknown.
    public func image(for id: String?, rear: Bool) -> String? {
        guard let entry = entries.first(where: { $0.id == id }) ?? entries.first else { return nil }
        return rear ? (entry.rearImage ?? entry.image) : entry.image
    }
}

/// How a cat and its desk are drawn, following Cat Office: at a front-view desk the cat types with its back to us,
/// facing back-right (back-left when the desk is mirrored); at a turned desk it works on the far side, facing us,
/// standing; waiting, it turns to us with a paw up.
public struct DeskScene: Equatable, Sendable {
    /// The reported design; nil draws the default desk.
    public var deskId: String?
    public var mirrored: Bool
    public var rear: Bool
    public var pose: CatPose
    public var direction: String

    public init(deskId: String?, mirrored: Bool, rear: Bool, pose: CatPose, direction: String) {
        self.deskId = deskId
        self.mirrored = mirrored
        self.rear = rear
        self.pose = pose
        self.direction = direction
    }

    public init(_ agent: OfficeAgent) {
        guard let desk = agent.desk else {
            self.init(deskId: nil, mirrored: false, rear: false, pose: CatPose(status: agent.status),
                      direction: agent.status == .working ? "back-left" : "front-left")
            return
        }
        let side = desk.flip ? "right" : "left"
        switch (agent.status, desk.rear) {
        case (.working, false):
            self.init(deskId: desk.id, mirrored: desk.flip, rear: false, pose: .typing, direction: desk.flip ? "back-left" : "back-right")
        case (.working, true):
            self.init(deskId: desk.id, mirrored: desk.flip, rear: true, pose: .standing, direction: "front-\(side)")
        default:
            self.init(deskId: desk.id, mirrored: desk.flip, rear: desk.rear, pose: CatPose(status: agent.status), direction: "front-\(side)")
        }
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
    private let deskCatalogBox = LockedBox<DeskCatalog?>(nil)

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

    public func catImage(cat: String, pose: CatPose, direction: String? = nil) async -> Data? {
        guard let catalog = await catalog() else { return nil }
        return await image(path: catalog.path(cat: cat, pose: pose, direction: direction))
    }

    /// A desk design's sprite (its rear view when turned); the default desk when `id` is nil or unknown.
    public func deskImage(id: String?, rear: Bool) async -> Data? {
        var catalog = deskCatalogBox.get()
        if catalog == nil, let data = await json("data/desks.json") {
            catalog = DeskCatalog.parse(data)
            deskCatalogBox.set(catalog)
        }
        guard let path = catalog?.image(for: id, rear: rear) else { return nil }
        return await image(path: path)
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

    /// A shrunken PNG of the asset at `path`, from memory, then disk, then Cat Office. The default size keeps
    /// sprites sharp in the office zoomed to 3× on a Retina screen.
    public func image(path: String, maxPixelSize: Int = 384) async -> Data? {
        let key = "\(maxPixelSize)_" + path.replacingOccurrences(of: "/", with: "_")
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

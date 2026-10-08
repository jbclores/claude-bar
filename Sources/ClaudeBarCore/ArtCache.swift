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
        var geometry: DeskGeometry?
    }

    var entries: [Entry]

    public static func parse(_ data: Data) -> DeskCatalog {
        let obj = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        let desks = obj?["desks"] as? [[String: Any]] ?? []
        return DeskCatalog(entries: desks.compactMap { d in
            guard let id = d["id"] as? String, let image = d["image"] as? String else { return nil }
            let rear = d["rear"] as? [String: Any]
            return Entry(id: id, image: image, rearImage: rear?["image"] as? String, geometry: DeskGeometry(json: d))
        })
    }

    /// Where a design's anchor and stand point are, for placing its cat; the first design when unknown.
    public func geometry(for id: String?) -> DeskGeometry? {
        (entries.first(where: { $0.id == id }) ?? entries.first)?.geometry
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
                      direction: agent.status == .working ? "back-right" : "front-left")
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
///
/// Each saved file keeps Cat Office's version tag (its ETag) beside it. A picture in use is checked again at most once a
/// minute (`revalidate`) with an "If-None-Match" request: Cat Office answers 304 when it's unchanged (nothing is
/// downloaded), or the new picture when a character or piece of furniture was edited. With Cat Office off, the saved
/// copies are used as before.
public final class ArtCache: @unchecked Sendable {
    private let dir: URL
    private let baseURL: @Sendable () -> URL
    private let session: URLSession
    private let now: @Sendable () -> Date
    private let memory = LockedBox<[String: Data]>([:])
    /// The pictures in use: cache key → (Cat Office path, size, when last checked).
    private let inUse = LockedBox<[String: (path: String, size: Int, checked: Date)]>([:])
    private let catalogBox = LockedBox<CatCatalog?>(nil)
    /// How long a checked picture is trusted before it is checked again.
    public static let recheckAfter: TimeInterval = 60
    private let deskBox = LockedBox<String?>(nil)
    private let deskCatalogBox = LockedBox<DeskCatalog?>(nil)

    public init(dir: URL = Paths.artCacheDir, baseURL: @escaping @Sendable () -> URL, session: URLSession = .shared,
                now: @escaping @Sendable () -> Date = Date.init) {
        self.dir = dir
        self.baseURL = baseURL
        self.session = session
        self.now = now
    }

    /// Cat Office's cat list. `refresh` checks Cat Office for a changed list (a character added or edited in its cat
    /// builder); otherwise the list loaded before is used.
    public func catalog(refresh: Bool = false) async -> CatCatalog? {
        if !refresh, let cached = catalogBox.get() { return cached }
        guard let data = await json("data/cats.json"), let catalog = CatCatalog.parse(data) else { return catalogBox.get() }
        catalogBox.set(catalog)
        return catalog
    }

    /// Cat Office's building (floors, desks, textures), refreshed when Cat Office answers, else the cached copy.
    /// Only a building that parses replaces the cached copy (Cat Office can answer 200 with a page that isn't one).
    public func building() async -> Building? {
        let paths = ["data/building.json", "data/room-parts.json"]
        let files = paths.map { dir.appendingPathComponent($0.replacingOccurrences(of: "/", with: "_")) }
        if let floors = await fetch(paths[0]), let parts = await fetch(paths[1]),
           (try? JSONSerialization.jsonObject(with: parts)) is [String: Any],
           let building = Building.parse(building: floors, parts: parts) {
            save(floors, to: files[0])
            save(parts, to: files[1])
            return building
        }
        guard let floors = try? Data(contentsOf: files[0]), let parts = try? Data(contentsOf: files[1]) else { return nil }
        return Building.parse(building: floors, parts: parts)
    }

    /// Cat Office's room catalogue (room parts, props, desks, wall-item art), refreshed when Cat Office answers,
    /// else the cached copies. Only a catalogue that parses replaces the cached files.
    public func roomCatalogue() async -> RoomCatalogue? {
        let paths = ["data/room-parts.json", "data/props.json", "data/desks.json", "src/world/wall-item-art.json"]
        let files = paths.map { dir.appendingPathComponent($0.replacingOccurrences(of: "/", with: "_")) }
        if let parts = await fetch(paths[0]), let props = await fetch(paths[1]), let desks = await fetch(paths[2]) {
            let art = await fetch(paths[3])
            if let catalogue = RoomCatalogue.parse(roomParts: parts, props: props, desks: desks, wallItemArt: art) {
                for (data, file) in zip([parts, props, desks], files) { save(data, to: file) }
                if let art { save(art, to: files[3]) }
                return catalogue
            }
        }
        guard let parts = try? Data(contentsOf: files[0]), let props = try? Data(contentsOf: files[1]),
              let desks = try? Data(contentsOf: files[2]) else { return nil }
        return RoomCatalogue.parse(roomParts: parts, props: props, desks: desks, wallItemArt: try? Data(contentsOf: files[3]))
    }

    public func catImage(cat: String, pose: CatPose, direction: String? = nil) async -> Data? {
        guard let catalog = await catalog() else { return nil }
        return await image(path: catalog.path(cat: cat, pose: pose, direction: direction))
    }

    /// A walk frame (1–4) facing `direction`; frame 0 is the still, paws-down stand.
    public func walkImage(cat: String, direction: String, frame: Int) async -> Data? {
        guard let catalog = await catalog() else { return nil }
        let path = catalog.path(cat: cat, pose: .standing, direction: direction)
        return await image(path: frame == 0 ? path : path.replacingOccurrences(of: "both-down.png", with: "walk-\(frame).png"))
    }

    /// A desk design's geometry (anchor, stand point); the default desk's when `id` is nil or unknown.
    public func deskGeometry(id: String?) async -> DeskGeometry? {
        if deskCatalogBox.get() == nil, let data = await json("data/desks.json") { deskCatalogBox.set(DeskCatalog.parse(data)) }
        return deskCatalogBox.get()?.geometry(for: id)
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
    /// sprites sharp in the office zoomed to 3× on a Retina screen. A saved copy older than `recheckAfter` is checked
    /// with Cat Office first (a cheap "has it changed?").
    public func image(path: String, maxPixelSize: Int = 384) async -> Data? {
        let key = "\(maxPixelSize)_" + path.replacingOccurrences(of: "/", with: "_")
        let file = dir.appendingPathComponent(key)
        if let checked = inUse.get()[key]?.checked, now().timeIntervalSince(checked) < Self.recheckAfter,
           let data = memory.get()[key] {
            return data
        }
        let saved = memory.get()[key] ?? (try? Data(contentsOf: file))
        switch await fetch(path, etag: saved == nil ? nil : etag(of: file)) {
        case .fresh(let raw, let tag):
            if let small = Self.shrink(raw, maxPixelSize: maxPixelSize) {
                save(small, to: file)
                saveTag(tag, of: file)
                remember(key, path: path, size: maxPixelSize, data: small)
                return small
            }
            if let saved { remember(key, path: path, size: maxPixelSize, data: saved) }
            return saved
        case .unchanged, .failed:
            if let saved { remember(key, path: path, size: maxPixelSize, data: saved) }
            return saved
        }
    }

    /// Checks every picture in use that wasn't checked within `recheckAfter` (all of them with `force`), and fetches
    /// the ones Cat Office changed. True when any changed (the office should redraw).
    @discardableResult
    public func revalidate(force: Bool = false) async -> Bool {
        let due = inUse.get().filter { force || now().timeIntervalSince($0.value.checked) >= Self.recheckAfter }
        var changed = false
        for (key, entry) in due {
            let file = dir.appendingPathComponent(key)
            switch await fetch(entry.path, etag: etag(of: file)) {
            case .fresh(let raw, let tag):
                guard let small = Self.shrink(raw, maxPixelSize: entry.size) else { continue }
                if small != memory.get()[key] { changed = true }
                save(small, to: file)
                saveTag(tag, of: file)
                remember(key, path: entry.path, size: entry.size, data: small)
            case .unchanged:
                inUse.update { $0[key]?.checked = now() }
            case .failed:
                // Cat Office off: keep the saved copy, and don't knock again until the next round.
                inUse.update { $0[key]?.checked = now() }
            }
        }
        return changed
    }

    private func remember(_ key: String, path: String, size: Int, data: Data) {
        memory.update { $0[key] = data }
        inUse.update { $0[key] = (path, size, now()) }
    }

    /// A JSON file from Cat Office, refreshed when it answers (a 304 keeps the saved copy), else the copy cached last time.
    private func json(_ path: String) async -> Data? {
        let file = dir.appendingPathComponent(path.replacingOccurrences(of: "/", with: "_"))
        let saved = try? Data(contentsOf: file)
        switch await fetch(path, etag: saved == nil ? nil : etag(of: file)) {
        case .fresh(let data, let tag):
            save(data, to: file)
            saveTag(tag, of: file)
            return data
        case .unchanged, .failed:
            return saved
        }
    }

    private func fetch(_ path: String) async -> Data? {
        if case .fresh(let data, _) = await fetch(path, etag: nil) { return data }
        return nil
    }

    enum Fetched { case fresh(Data, String?), unchanged, failed }

    /// A file from Cat Office; with `etag`, Cat Office answers 304 (unchanged) when its copy has the same version.
    private func fetch(_ path: String, etag: String?) async -> Fetched {
        var request = URLRequest(url: baseURL().appendingPathComponent(path))
        if let etag { request.setValue(etag, forHTTPHeaderField: "If-None-Match") }
        guard let (data, response) = try? await session.data(for: request), let http = response as? HTTPURLResponse else { return .failed }
        switch http.statusCode {
        case 200: return .fresh(data, http.value(forHTTPHeaderField: "ETag"))
        case 304: return .unchanged
        default: return .failed
        }
    }

    /// The version tag saved beside a cached file ("<file>.etag").
    private func etag(of file: URL) -> String? {
        (try? String(contentsOf: file.appendingPathExtension("etag"), encoding: .utf8)).flatMap { $0.isEmpty ? nil : $0 }
    }

    private func saveTag(_ tag: String?, of file: URL) {
        let tagFile = file.appendingPathExtension("etag")
        if let tag { save(Data(tag.utf8), to: tagFile) } else { try? FileManager.default.removeItem(at: tagFile) }
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

/// A desk design's sprite geometry from desks.json: size, anchor (the point placed on the floor) and the stand
/// offset from the anchor where its working cat's feet go; the same for its rear (turned) sprite.
public struct DeskGeometry: Equatable, Sendable {
    public struct Sprite: Equatable, Sendable {
        public var width: CGFloat
        public var height: CGFloat
        public var anchor: CGPoint

        public init(width: CGFloat, height: CGFloat, anchor: CGPoint) {
            self.width = width
            self.height = height
            self.anchor = anchor
        }
    }

    public var front: Sprite
    public var stand: CGVector
    public var rear: Sprite?

    public init(width: CGFloat, height: CGFloat, anchor: CGPoint, stand: CGVector, rear: Sprite?) {
        front = Sprite(width: width, height: height, anchor: anchor)
        self.stand = stand
        self.rear = rear
    }

    init?(json d: [String: Any]) {
        func sprite(_ o: [String: Any]?) -> Sprite? {
            guard let o, let w = (o["width"] as? NSNumber)?.doubleValue, let h = (o["height"] as? NSNumber)?.doubleValue,
                  let a = o["anchor"] as? [String: Any], let ax = (a["x"] as? NSNumber)?.doubleValue,
                  let ay = (a["y"] as? NSNumber)?.doubleValue else { return nil }
            return Sprite(width: w, height: h, anchor: CGPoint(x: ax, y: ay))
        }
        guard let front = sprite(d), let s = d["stand"] as? [String: Any],
              let dx = (s["dx"] as? NSNumber)?.doubleValue, let dy = (s["dy"] as? NSNumber)?.doubleValue else { return nil }
        self.front = front
        stand = CGVector(dx: dx, dy: dy)
        rear = sprite(d["rear"] as? [String: Any])
    }
}

/// A desk and its working cat laid out the way Cat Office places them (src/world/desks.ts), in floor pixels with the
/// desk's anchor at the origin: the desk sprite (mirrored about the anchor when flipped), the cat's feet on the
/// stand point (mirrored too), the cat facing the desk; a turned desk puts the cat on the far side, facing us.
public struct DeskComposition: Equatable, Sendable {
    /// Cats are drawn at catHeight / bodyHeight (building.json 160, cats.json 210) of their 360×380 canvas, feet at (180, 300).
    public static let catScale: CGFloat = 160.0 / 210.0
    static let catCanvas = CGSize(width: 360, height: 380)
    static let catFeet = CGPoint(x: 180, y: 300)

    public var desk: CGRect
    public var cat: CGRect
    /// Front desk: the cat stands at the front edge, drawn over the desk. Turned desk: behind it.
    public var catInFront: Bool
    public var facing: String
    public var bounds: CGRect { desk.union(cat) }

    public init(_ g: DeskGeometry, flip: Bool, rear: Bool) {
        let sprite = rear ? (g.rear ?? g.front) : g.front
        let left = flip ? -(sprite.width - sprite.anchor.x) : -sprite.anchor.x
        desk = CGRect(x: left, y: -sprite.anchor.y, width: sprite.width, height: sprite.height)
        var feet = CGPoint(x: flip ? -g.stand.dx : g.stand.dx, y: g.stand.dy)
        if rear {
            // Turned round its middle: the stand point goes to the far side. Cat Office does this on the floor's
            // axes; mirroring through the desk's middle (a little above the anchor, in depth) comes close.
            let middle = CGPoint(x: desk.midX, y: -sprite.anchor.y * 0.3)
            feet = CGPoint(x: 2 * middle.x - feet.x, y: 2 * middle.y - feet.y)
        }
        let s = Self.catScale
        cat = CGRect(x: feet.x - Self.catFeet.x * s, y: feet.y - Self.catFeet.y * s,
                     width: Self.catCanvas.width * s, height: Self.catCanvas.height * s)
        catInFront = !rear
        facing = rear ? (flip ? "front-right" : "front-left") : (flip ? "back-left" : "back-right")
    }
}

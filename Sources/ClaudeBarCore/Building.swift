// Sources/ClaudeBarCore/Building.swift
import CoreGraphics
import Foundation

/// A floor/wall texture from Cat Office's room-parts.json.
public struct RoomTexture: Equatable, Sendable {
    public var id: String
    public var image: String
    public var tile: CGSize
    public var color: String

    public init(id: String, image: String, tile: CGSize, color: String) {
        self.id = id
        self.image = image
        self.tile = tile
        self.color = color
    }
}

/// Wall-item art (the elevator, signs): its image, size and the elevator's number plate.
public struct WallItemArt: Equatable, Sendable {
    public var id: String
    public var image: String
    public var size: CGSize
    public var plate: CGRect?
    public var plateColor: String?
}

/// A desk placed on a floor (building.json room.desks): its design, mirrored, turned.
public struct FloorDesk: Equatable, Sendable {
    public var id: String
    public var design: String
    public var flip: Bool
    public var rear: Bool
    /// Where it stands on the floor's own axes (0 when building.json gives none).
    public var u: Double
    public var v: Double

    public init(id: String, design: String, flip: Bool, rear: Bool, u: Double = 0, v: Double = 0) {
        self.id = id
        self.design = design
        self.flip = flip
        self.rear = rear
        self.u = u
        self.v = v
    }
}

public struct Floor: Equatable, Sendable, Identifiable {
    public var id: Int
    public var name: String
    /// Normalized project folder for a project floor; nil for shared floors.
    public var repoRoot: String?
    public var floorTexture: RoomTexture?
    public var wallTexture: RoomTexture?
    public var desks: [FloorDesk]
    public var elevator: WallItemArt?
    public var hasLoungeSign: Bool
    /// The floor diamond's corners and its room, when building.json gives them.
    public var corners: FloorCorners?
    public var room: FloorRoom?
    /// Cells along each side of the floor's walk grid (building.json floor.grid.size): sizes props measured in cells.
    public var gridSize: Double?
    /// building.json floor.grid.walkable: `size` rows of `size` "1"/"0" cells (nil when missing or malformed).
    public var walkable: [String]?

    public init(id: Int, name: String, repoRoot: String?, floorTexture: RoomTexture?, wallTexture: RoomTexture?,
                desks: [FloorDesk], elevator: WallItemArt?, hasLoungeSign: Bool,
                corners: FloorCorners? = nil, room: FloorRoom? = nil, gridSize: Double? = nil, walkable: [String]? = nil) {
        self.id = id
        self.name = name
        self.repoRoot = repoRoot
        self.floorTexture = floorTexture
        self.wallTexture = wallTexture
        self.desks = desks
        self.elevator = elevator
        self.hasLoungeSign = hasLoungeSign
        self.corners = corners
        self.room = room
        self.gridSize = gridSize
        self.walkable = walkable
    }

    /// Floor 1 is the Lounge in Cat Office (src/world/floors.ts LOUNGE_FLOOR).
    public var isLounge: Bool { id == 1 }
}

/// Cat Office's building (public/data/building.json + room-parts.json).
public struct Building: Equatable, Sendable {
    public var floors: [Floor]
    /// building.json catHeight: a cat's height in world px (nil when not given: BuiltRoom.defaultCatHeight).
    public var catHeight: Double? = nil

    /// Without Cat Office's data: just a Lounge, drawn with ClaudeBar's own room art.
    public static let fallback = Building(floors: [
        Floor(id: 1, name: "Lounge", repoRoot: nil, floorTexture: nil, wallTexture: nil, desks: [], elevator: nil, hasLoungeSign: false),
    ])

    public func floor(id: Int) -> Floor? { floors.first { $0.id == id } }
    public var lounge: Floor? { floors.first(where: \.isLounge) }
    /// The floor named "Desk pool", else the first shared (repo-less) floor other than the Lounge.
    public var deskPool: Floor? {
        floors.first { $0.name == "Desk pool" } ?? floors.first { !$0.isLounge && $0.repoRoot == nil }
    }

    public static func parse(building: Data, parts: Data) -> Building? {
        guard let root = try? JSONSerialization.jsonObject(with: building) as? [String: Any],
              let rawFloors = root["floors"] as? [[String: Any]] else { return nil }
        let partsRoot = (try? JSONSerialization.jsonObject(with: parts) as? [String: Any]) ?? [:]
        func list(_ key: String) -> [[String: Any]] { partsRoot[key] as? [[String: Any]] ?? [] }
        func texture(_ id: String?, in key: String) -> RoomTexture? {
            guard let id, let t = list(key).first(where: { $0["id"] as? String == id }), let image = t["image"] as? String else { return nil }
            let tile = (t["tile"] as? [NSNumber]).map { CGSize(width: $0.first?.doubleValue ?? 1024, height: $0.last?.doubleValue ?? 528) }
            return RoomTexture(id: id, image: image, tile: tile ?? CGSize(width: 1024, height: 528), color: t["color"] as? String ?? "#e3a56c")
        }
        func wallItem(_ id: String) -> WallItemArt? {
            guard let w = list("wallItems").first(where: { $0["id"] as? String == id }), let image = w["image"] as? String else { return nil }
            let n = { (k: String) in (w[k] as? NSNumber)?.doubleValue ?? 0 }
            let plate = (w["plate"] as? [String: Any]).map { p -> CGRect in
                let v = { (k: String) in (p[k] as? NSNumber)?.doubleValue ?? 0 }
                return CGRect(x: v("x"), y: v("y"), width: v("width"), height: v("height"))
            }
            return WallItemArt(id: id, image: image, size: CGSize(width: n("width"), height: n("height")), plate: plate,
                               plateColor: (w["plate"] as? [String: Any])?["color"] as? String)
        }
        let floors = rawFloors.compactMap { f -> Floor? in
            guard let id = (f["id"] as? NSNumber)?.intValue else { return nil }
            let room = f["room"] as? [String: Any] ?? [:]
            let items = (room["wallItems"] as? [[String: Any]] ?? []).compactMap { $0["item"] as? String }
            let desks = (room["desks"] as? [[String: Any]] ?? []).compactMap { d -> FloorDesk? in
                guard let did = d["id"] as? String, let design = d["desk"] as? String else { return nil }
                return FloorDesk(id: did, design: design, flip: d["flip"] as? Bool ?? false, rear: d["rear"] as? Bool ?? false,
                                 u: (d["u"] as? NSNumber)?.doubleValue ?? 0, v: (d["v"] as? NSNumber)?.doubleValue ?? 0)
            }
            return Floor(
                id: id, name: f["name"] as? String ?? "Floor \(id)",
                repoRoot: ((f["repo"] as? [String: Any])?["root"] as? String).map(Paths.normalize),
                floorTexture: texture(room["floor"] as? String, in: "floors"),
                wallTexture: texture(room["wall"] as? String, in: "walls"),
                desks: desks,
                elevator: items.first { $0.hasPrefix("elevator") }.flatMap(wallItem),
                hasLoungeSign: items.contains { $0.hasPrefix("sign-lounge") },
                corners: f["corners"].flatMap { decode($0) },
                room: f["room"].flatMap { decode($0) },
                gridSize: ((f["grid"] as? [String: Any])?["size"] as? NSNumber)?.doubleValue,
                walkable: walkableRows(f["grid"] as? [String: Any]))
        }
        guard !floors.isEmpty else { return nil }
        let catHeight = (root["catHeight"] as? NSNumber).map(\.doubleValue).flatMap { $0.isFinite && $0 > 0 ? $0 : nil }
        return Building(floors: floors.sorted { $0.id < $1.id }, catHeight: catHeight)
    }
}

/// `grid.walkable` when `grid.size` is an integer >= 1 and there are exactly that many rows of that many characters.
private func walkableRows(_ grid: [String: Any]?) -> [String]? {
    guard let size = (grid?["size"] as? NSNumber)?.doubleValue, size >= 1, size == size.rounded(), size < 4096,
          let rows = grid?["walkable"] as? [String], rows.count == Int(size),
          rows.allSatisfy({ $0.count == Int(size) }) else { return nil }
    return rows
}

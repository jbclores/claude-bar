// Sources/ClaudeBarCore/RoomCatalogue.swift
import Foundation

public struct ArtBounds: Codable, Equatable, Sendable {
    public var l: Double
    public var t: Double
    public var r: Double
    public var b: Double
    public init(l: Double, t: Double, r: Double, b: Double) { self.l = l; self.t = t; self.r = r; self.b = b }
    public static let whole = ArtBounds(l: 0, t: 0, r: 1, b: 1)
}

public struct SpotOffset: Codable, Equatable, Sendable {
    public var dx: Double
    public var dy: Double
    public init(dx: Double, dy: Double) { self.dx = dx; self.dy = dy }
}

public struct SliceDef: Codable, Equatable, Sendable {
    public var left: Double?
    public var right: Double?
    public var top: Double?
    public var bottom: Double?
}

public struct PlateDef: Codable, Equatable, Sendable {
    public var x: Double
    public var y: Double
    public var width: Double
    public var height: Double
    public var color: String?
}

public struct SurfaceMaterial: Codable, Equatable, Sendable {
    public var id: String
    public var image: String
    public var tile: [Double]?
    public var color: String
}

public struct WallMaterial: Codable, Equatable, Sendable {
    public var id: String
    public var image: String
    public var tile: [Double]?
    public var color: String
    public var slice: SliceDef?
    public var floorRows: Double?
}

public struct RugDef: Codable, Equatable, Sendable {
    public var id: String
    public var image: String
    public var shape: String?
    /// Added to the brief: the rug art's size, image px.
    public var size: [Double]?
}

/// A window's decoration over its glass: a strip of lights or a hung lantern (Cat Office's WindowDecorDef).
public struct WindowDecorDef: Codable, Equatable, Sendable {
    public var kind: String
    public var image: String
    public var emissiveImage: String?
    public var emissive: String?
    public var width: Double
    public var height: Double
}

public struct WallItemDef: Codable, Equatable, Sendable {
    public var id: String
    public var width: Double
    public var height: Double
    public var kind: String?
    public var image: String?
    public var imageRight: String?
    public var mirror: Bool?
    public var drawnFor: String?
    public var resizable: Bool?
    public var fullHeight: Bool?
    public var top: Double?
    public var bottom: Double?
    public var floorGap: Double?
    public var art: ArtBounds?
    public var artRight: ArtBounds?
    public var plate: PlateDef?
    public var doorway: [Double]?
    public var standOut: Double?
    public var seat: [Double]?
    public var seatDepth: Double?
    public var mount: String?
    public var anchor: WorldPoint?
    public var anchorRight: WorldPoint?
    public var reach: Double?
    public var frame: String?
    public var mullion: String?
    public var slice: SliceDef?
    public var paneWidth: Double?
    public var mullionWidth: Double?
    public var glassLeft: Double?
    public var glassRight: Double?
    public var glassTop: Double?
    public var glassBottom: Double?
    public var glass: String?
    public var skyline: String?
    public var skylineHeight: Double?
    public var transom: String?
    public var transomHeight: Double?
    public var transomAt: Double?
    public var transomOptional: Bool?
    public var sill: Double?
    public var decor: WindowDecorDef?
    public var color: String?
}

public struct PropSprite: Codable, Equatable, Sendable {
    public var image: String
    public var width: Double
    public var height: Double
    public var anchor: WorldPoint
}

/// One art size of a panel row (the JSON's `sizes` is a list of these, fewest panels first).
public struct PanelSize: Codable, Equatable, Sendable {
    public var panels: Int
    public var image: String
    public var width: Double
    public var height: Double
    public var anchor: WorldPoint
}

public struct PanelDef: Codable, Equatable, Sendable {
    public var `default`: Int
    public var step: Double
    public var min: Int?
    public var max: Int?
    public var sizes: [PanelSize]?
}

public struct CompanionAt: Codable, Equatable, Sendable {
    public var du: Double
    public var dv: Double
}

public struct CompanionDef: Codable, Equatable, Sendable {
    public var prop: String?
    public var rug: String?
    public var at: CompanionAt
    public var label: String?
}

public struct SpotSlot: Codable, Equatable, Sendable {
    public var stand: SpotOffset
    public var facing: String
}

public struct PropSpotDef: Codable, Equatable, Sendable {
    public var id: String?
    public var kind: String
    public var pose: String?
    public var stand: SpotOffset
    public var facing: String
    public var capacity: Int?
    public var lift: Double?
    public var optional: Bool?
    public var slots: [SpotSlot]?
}

public struct PropTop: Codable, Equatable, Sendable {
    public var height: Double
    public var inset: Double
}

public struct PropDef: Codable, Equatable, Sendable {
    public var id: String
    public var image: String?
    public var width: Double?
    public var height: Double?
    public var anchor: WorldPoint?
    public var length: Double
    public var depth: Double
    public var mirror: Bool?
    public var cells: Int?
    public var rear: PropSprite?
    public var panels: PanelDef?
    public var raised: Double?
    public var placeOn: String?
    public var companions: [CompanionDef]?
    public var spots: [PropSpotDef]?
    public var slots: [PropSpotDef]?
    public var cover: [WorldPoint]?
    public var facings: [Int]?
    /// Added to the brief: a table's top (table bits stand on it) and the corner prop's open share.
    public var top: PropTop?
    public var notch: Double?
}

public struct DeskDef: Codable, Equatable, Sendable {
    public var id: String
    public var image: String
    public var width: Double
    public var height: Double
    public var anchor: WorldPoint
    public var length: Double
    public var depth: Double
    public var stand: SpotOffset
    public var rear: PropSprite?
}

/// Cat Office's room-parts.json, props.json, desks.json (and wall-item-art.json) indexed by id.
public struct RoomCatalogue: Equatable, Sendable {
    public var wallHeight: Double
    public var wallHeights: [String: Double]
    public var floors: [String: SurfaceMaterial]
    public var walls: [String: WallMaterial]
    public var rugs: [String: RugDef]
    public var wallItems: [String: WallItemDef]
    public var props: [String: PropDef]
    public var desks: [String: DeskDef]

    /// Entries that don't decode are dropped one by one; nil only when a required file isn't usable.
    public static func parse(roomParts: Data, props: Data, desks: Data, wallItemArt: Data?) -> RoomCatalogue? {
        guard let parts = (try? JSONSerialization.jsonObject(with: roomParts)) as? [String: Any],
              let wallHeight = (parts["wallHeight"] as? NSNumber)?.doubleValue,
              let propsRoot = (try? JSONSerialization.jsonObject(with: props)) as? [String: Any],
              let propList = propsRoot["props"] as? [Any],
              let desksRoot = (try? JSONSerialization.jsonObject(with: desks)) as? [String: Any],
              let deskList = desksRoot["desks"] as? [Any] else { return nil }

        var art: [String: ArtBounds] = [:]
        if let wallItemArt, let raw = (try? JSONSerialization.jsonObject(with: wallItemArt)) as? [String: Any] {
            for (path, value) in raw { if let b: ArtBounds = decode(value) { art[path] = b } }
        }
        var heights: [String: Double] = [:]
        for (k, v) in parts["wallHeights"] as? [String: Any] ?? [:] { if let n = (v as? NSNumber)?.doubleValue { heights[k] = n } }

        func index<T: Decodable>(_ list: Any?, _ id: (T) -> String, map: (T) -> T = { $0 }) -> [String: T] {
            var out: [String: T] = [:]
            for case let entry in (list as? [Any] ?? []) { if let t: T = decode(entry) { out[id(t)] = map(t) } }
            return out
        }
        return RoomCatalogue(
            wallHeight: wallHeight, wallHeights: heights,
            floors: index(parts["floors"], { (m: SurfaceMaterial) in m.id }),
            walls: index(parts["walls"], { (m: WallMaterial) in m.id }),
            rugs: index(parts["rugs"], { (r: RugDef) in r.id }),
            wallItems: index(parts["wallItems"], { (w: WallItemDef) in w.id }, map: { withArt($0, art) }),
            props: index(propList, { (p: PropDef) in p.id }),
            desks: index(deskList, { (d: DeskDef) in d.id }))
    }

    /// A wall item with the bounds of its visible art, unless the catalogue gives its own (room.ts withArt).
    static func withArt(_ def: WallItemDef, _ art: [String: ArtBounds]) -> WallItemDef {
        var out = def
        out.art = def.art ?? def.image.flatMap { art[$0] }
        out.artRight = def.artRight ?? def.imageRight.flatMap { art[$0] }
        return out
    }

    /// A room's own wall height, else its floor's, else the default (room.ts roomWallHeight).
    public func wallHeight(floorId: Int, room: FloorRoom) -> Double {
        room.wallHeight ?? wallHeights[String(floorId)] ?? wallHeight
    }
}

/// Decodes one raw JSON value, nil when it doesn't fit.
func decode<T: Decodable>(_ value: Any) -> T? {
    guard JSONSerialization.isValidJSONObject(value) || value is NSNumber || value is String,
          let data = try? JSONSerialization.data(withJSONObject: value, options: [.fragmentsAllowed]) else { return nil }
    return try? JSONDecoder().decode(T.self, from: data)
}

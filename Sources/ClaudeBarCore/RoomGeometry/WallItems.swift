import CoreGraphics
import Foundation

/// One layer of a window's art, in the item box's own px (RoomShell.tsx WindowArt).
public enum WindowPiece: Equatable, Sendable {
    case nineSlice(image: String, rect: CGRect, slice: SliceDef)
    case stretch(image: String, rect: CGRect)
    case repeatX(image: String, rect: CGRect)
    case decor(image: String, rect: CGRect)
    case fill(color: String, rect: CGRect)
}

/// A wall item in its wall's plane (RoomShell.tsx WallItem).
public struct PlacedWallItem: Equatable, Sendable {
    public var id: String
    public var item: String
    public var wall: WallSide
    public var image: String?
    public var mirrored: Bool
    /// In the wall frame's local px (FloorFrame.wall).
    public var box: CGRect
    /// The elevator's floor-number plate, in the same px.
    public var plate: CGRect?
    /// A window's layers, back to front. Empty: draw `image` over the box.
    public var pieces: [WindowPiece]
    public var isElevator: Bool
    /// The art's height kept (px from the box's top) when the catalogue cuts it at a `sill`; the box stays whole.
    public var clipHeight: Double?
}

public struct ElevatorSpot: Equatable, Sendable {
    public var id: String
    public var wall: WallSide
    public var standAt: FloorPoint
    public var facing: String
}

/// A wall fixture drawn upright with the props (room.ts PlacedFixture).
public struct PlacedFixture: Equatable, Sendable {
    public var id: String
    public var image: String?
    public var mirrored: Bool
    public var rect: CGRect
    public var box: OccluderBox
}

public enum WallItems {
    static let wallTopMarginPx = 26.0
    static let elevatorStandOutPx = 40.0
    static let whole = ArtBounds.whole

    // MARK: room.ts 168-230

    static func width(_ def: WallItemDef, _ item: WallItemPlacement) -> Double {
        (def.resizable ?? false) ? (item.width ?? def.width) : def.width
    }

    static func raisable(_ def: WallItemDef) -> Bool {
        def.kind != "elevator" && !(def.fullHeight ?? false) && def.floorGap == nil
    }

    static func upRange(height: Double, wallHeight: Double, art: ArtBounds = whole) -> (min: Double, max: Double) {
        let raw = (art.b - 1) * height
        let lo = (raw == 0 || raw.isNaN) ? 0 : raw
        return (lo, max(lo, wallHeight - (1 - art.t) * height - wallTopMarginPx))
    }

    static func clampUp(_ up: Double, height: Double, wallHeight: Double, art: ArtBounds = whole) -> Double {
        let r = upRange(height: height, wallHeight: wallHeight, art: art)
        return min(r.max, max(r.min, up))
    }

    /// room.ts wallItemSize: size in wall px and how far below the wall's top the bottom edge sits.
    static func size(_ def: WallItemDef, _ item: WallItemPlacement, wallHeight: Double) -> (width: Double, height: Double, bottom: Double) {
        let w = width(def, item)
        if def.fullHeight ?? false { return (w, wallHeight - (def.top ?? wallTopMarginPx), wallHeight) }
        if let gap = def.floorGap { return (w, def.height, wallHeight - gap) }
        let resizable = def.resizable ?? false
        let height = resizable ? (item.height ?? def.height) : def.height
        let own = (resizable ? (item.bottom ?? def.bottom) : def.bottom) ?? 0
        if let up = item.up, raisable(def) {
            return (w, height, wallHeight - clampUp(up, height: height, wallHeight: wallHeight, art: def.art ?? whole))
        }
        return (w, height, min(own, wallHeight))
    }

    // MARK: room.ts 324-332

    static func mirrored(_ item: WallItemPlacement, _ def: WallItemDef) -> Bool {
        if item.wall == .right && def.imageRight != nil { return false }
        return def.mirror != false && item.wall != (WallSide(rawValue: def.drawnFor ?? "left") ?? .left)
    }

    static func image(_ item: WallItemPlacement, _ def: WallItemDef) -> String? {
        item.wall == .right && def.imageRight != nil ? def.imageRight : def.image
    }

    private static func length(_ frame: FloorFrame, _ side: WallSide) -> Double { frame.wall(side, height: 0).length }

    /// room.ts wallItemAt: `at` along the wall of a point `x` image px across the item's art.
    static func at(_ item: WallItemPlacement, _ def: WallItemDef, frame: FloorFrame, x: Double) -> Double {
        let sign = (item.wall == .left) == !mirrored(item, def) ? 1.0 : -1.0
        return item.at + (sign * (width(def, item) / 2 - x)) / length(frame, item.wall)
    }

    // MARK: RoomShell.tsx 122-147

    private static func glass(_ def: WallItemDef, width: Double, height: Double) -> (x0: Double, x1: Double, y0: Double, y1: Double) {
        let s = def.slice
        let x0 = def.glassLeft ?? (s?.left ?? 0) - 4
        let x1 = width - (def.glassRight.map { def.width - $0 } ?? ((s?.right ?? 0) - 4))
        let y0 = def.glassTop ?? (s?.top ?? 0)
        let y1 = height - (def.height - (def.glassBottom ?? def.height - (s?.bottom ?? 0)))
        return (x0, x1, y0, y1)
    }

    private static func mullions(_ def: WallItemDef, x0: Double, x1: Double) -> [Double] {
        let mw = def.mullionWidth ?? 0
        guard def.mullion != nil, let pane = def.paneWidth, pane != 0, mw != 0 else { return [] }
        let panes = max(1, Int(((x1 - x0 + mw) / (pane + mw) + 0.5).rounded(.down)))
        return (0..<(panes - 1)).map { k in x0 + Double(k + 1) * (x1 - x0) / Double(panes) - mw / 2 }
    }

    // MARK: RoomShell.tsx 182-255

    private static func windowPieces(_ def: WallItemDef, _ item: WallItemPlacement, width: Double, height: Double) -> [WindowPiece] {
        guard let frame = def.frame, let slice = def.slice else { return [] }
        let g = glass(def, width: width, height: height)
        let gw = g.x1 - g.x0, gh = g.y1 - g.y0
        let mw = def.mullionWidth ?? 0
        let frameBox = CGRect(x: 0, y: 0, width: width, height: height)
        var out: [WindowPiece] = []
        if def.fullHeight ?? false {
            let sky = def.skylineHeight ?? 0
            let bar = def.transomHeight ?? 12
            if let glassImage = def.glass, !glassImage.isEmpty {
                out.append(.stretch(image: glassImage, rect: CGRect(x: g.x0, y: g.y0, width: gw, height: gh)))
            }
            if let skyline = def.skyline, !skyline.isEmpty, sky > 0 {
                out.append(.repeatX(image: skyline, rect: CGRect(x: g.x0, y: g.y1 - sky, width: gw, height: sky)))
            }
            if let m = def.mullion {
                for x in mullions(def, x0: g.x0, x1: g.x1) {
                    out.append(.stretch(image: m, rect: CGRect(x: x, y: g.y0 - 2, width: mw, height: gh + 4)))
                }
            }
            if let t = def.transom, !t.isEmpty, !(def.transomOptional ?? false) || item.transom != false {
                // room.css .wall-item__transom: background-size 100% 100%, no-repeat (stretched).
                out.append(.stretch(image: t, rect: CGRect(x: g.x0 - 2, y: g.y0 + (1 - (def.transomAt ?? 0.75)) * gh - bar / 2, width: gw + 4, height: bar)))
            }
            out.append(.nineSlice(image: frame, rect: frameBox, slice: slice))
            return out
        }
        out.append(.nineSlice(image: frame, rect: frameBox, slice: slice))
        if let m = def.mullion {
            for x in mullions(def, x0: g.x0, x1: g.x1) {
                out.append(.stretch(image: m, rect: CGRect(x: x, y: g.y0, width: mw, height: g.y1 - g.y0)))
            }
        }
        // RoomShell.tsx DecorArt (153-179): the unlit art; the glow copy is not drawn.
        if let d = def.decor {
            if d.kind == "strip" {
                // Repeated a whole number of times across the glass, along its top.
                let k = max(1, Int((gw / d.width + 0.5).rounded(.down)))
                for i in 0..<k {
                    out.append(.decor(image: d.image, rect: CGRect(x: g.x0 + Double(i) * gw / Double(k), y: g.y0 + 1, width: gw / Double(k), height: d.height)))
                }
            } else {
                // Tied to the glass's top, centred, no taller than the glass leaves room for.
                let h = max(8, min(d.height, gh - 6))
                let w = d.width * h / d.height
                out.append(.decor(image: d.image, rect: CGRect(x: g.x0 + (gw - w) / 2, y: g.y0, width: w, height: h)))
            }
        }
        return out
    }

    // MARK: RoomShell.tsx 269-333

    public static func place(_ item: WallItemPlacement, frame: FloorFrame, catalogue: RoomCatalogue, wallHeight: Double) -> PlacedWallItem? {
        guard let def = catalogue.wallItems[item.item], def.mount != "sprite" else { return nil }
        let s = size(def, item, wallHeight: wallHeight)
        let len = length(frame, item.wall)
        let x = (item.wall == .left ? 1 - item.at : item.at) * len
        let left = x - s.width / 2, top = s.bottom - s.height
        let mir = mirrored(item, def)
        let art = image(item, def)
        let pieces = def.kind == "window" ? windowPieces(def, item, width: s.width, height: s.height) : []
        var plate: CGRect?
        if let p = def.plate, let img = def.image, !img.isEmpty {
            plate = CGRect(x: left + (mir ? s.width - p.x - p.width : p.x), y: top + p.y, width: p.width, height: p.height)
        }
        return PlacedWallItem(
            id: item.id, item: item.item, wall: item.wall, image: art, mirrored: mir,
            box: CGRect(x: left, y: top, width: s.width, height: s.height), plate: plate, pieces: pieces,
            isElevator: def.kind == "elevator",
            clipHeight: def.kind != "window" && art != nil ? def.sill.map { $0 + 1 } : nil)
    }

    // MARK: room.ts 340-362

    public static func elevatorSpot(_ item: WallItemPlacement, frame: FloorFrame, catalogue: RoomCatalogue) -> ElevatorSpot? {
        guard let def = catalogue.wallItems[item.item], def.kind == "elevator" else { return nil }
        let out = (def.standOut ?? elevatorStandOutPx) * frame.outUnit(item.wall)
        let door = def.doorway ?? [0, def.width]
        let doorAt = at(item, def, frame: frame, x: (door[0] + door[1]) / 2)
        return ElevatorSpot(
            id: item.id, wall: item.wall,
            standAt: FloorFrame.wallFloorPoint(item.wall, at: doorAt, out: out),
            facing: item.wall == .left ? "back-left" : "back-right")
    }

    // MARK: room.ts 886-909

    public static func fixture(_ item: WallItemPlacement, frame: FloorFrame, catalogue: RoomCatalogue, wallHeight: Double) -> PlacedFixture? {
        guard let def = catalogue.wallItems[item.item], def.mount == "sprite" else { return nil }
        let s = size(def, item, wallHeight: wallHeight)
        let own = item.wall == .right && def.imageRight != nil ? def.anchorRight : def.anchor
        let anchor = own ?? WorldPoint(x: s.width / 2, y: s.height / 2)
        let pt = frame.wallPoint(item.wall, at: item.at, up: wallHeight - s.bottom + s.height - anchor.y)
        let mir = mirrored(item, def)
        let left = pt.x - (mir ? s.width - anchor.x : anchor.x)
        let top = pt.y - anchor.y
        let rect = CGRect(x: left, y: top, width: s.width, height: s.height)
        let half = s.width / 2 / length(frame, item.wall)
        let out = (def.reach ?? 0) * frame.outUnit(item.wall)
        let front = FloorFrame.wallFloorPoint(item.wall, at: min(1, item.at + half), out: out)
        return PlacedFixture(
            id: item.id, image: image(item, def), mirrored: mir, rect: rect,
            box: OccluderBox.make(front: front, rect: rect, back: max(0, item.at - half), id: item.id))
    }
}

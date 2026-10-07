import CoreGraphics
import Foundation

/// A desk standing on a floor, with everything derived from its placement (desks.ts PlacedDesk).
public struct PlacedDesk: Equatable, Sendable {
    public var id: String
    public var design: String
    /// The picture drawn: the desk's own, or its rear view when turned round.
    public var image: String
    public var flip: Bool
    public var rear: Bool
    public var footprint: Footprint
    /// Sprite box on screen in world px (the mirrored box when flipped).
    public var rect: CGRect
    public var box: OccluderBox
    /// Work spot: where the cat's feet go, and which way it faces.
    public var standAt: FloorPoint
    public var facing: String
}

/// Ports desks.ts deskFootprint, deskStandPoint, deskFacing and placeDesk.
public enum DeskPlacer {
    static func footprint(_ frame: FloorFrame, _ def: DeskDef, u: Double, v: Double, flip: Bool) -> Footprint {
        let du = (flip ? def.length : def.depth) / frame.eu
        let dv = (flip ? def.depth : def.length) / frame.ev
        return Footprint(u0: u - du, u1: u, v0: v - dv, v1: v)
    }

    static func standPoint(_ frame: FloorFrame, _ def: DeskDef, u: Double, v: Double, flip: Bool, rear: Bool) -> FloorPoint {
        let a = frame.px(FloorPoint(u: u, v: v))
        let front = frame.uv(WorldPoint(x: a.x + (flip ? -def.stand.dx : def.stand.dx), y: a.y + def.stand.dy))
        if !rear { return front }
        let fp = footprint(frame, def, u: u, v: v, flip: flip)
        return FloorPoint(u: fp.u0 + fp.u1 - front.u, v: fp.v0 + fp.v1 - front.v)
    }

    static func facing(flip: Bool, rear: Bool) -> String {
        if rear { return flip ? "front-right" : "front-left" }
        return flip ? "back-left" : "back-right"
    }

    /// nil when the placement's design isn't in the catalogue.
    public static func place(_ d: DeskPlacement, frame: FloorFrame, catalogue: RoomCatalogue) -> PlacedDesk? {
        guard let def = catalogue.desks[d.desk] else { return nil }
        let flip = d.flip
        let rear = (d.rear ?? false) && def.rear != nil
        let sprite = rear ? (def.rear ?? PropSprite(image: def.image, width: def.width, height: def.height, anchor: def.anchor))
                          : PropSprite(image: def.image, width: def.width, height: def.height, anchor: def.anchor)
        let a = frame.px(FloorPoint(u: d.u, v: d.v))
        let left = flip ? a.x - (sprite.width - sprite.anchor.x) : a.x - sprite.anchor.x
        let top = a.y - sprite.anchor.y
        let rect = CGRect(x: left, y: top, width: sprite.width, height: sprite.height)
        let fp = footprint(frame, def, u: d.u, v: d.v, flip: flip)
        return PlacedDesk(
            id: d.id, design: d.desk, image: sprite.image, flip: flip, rear: rear, footprint: fp, rect: rect,
            box: OccluderBox.make(front: FloorPoint(u: d.u, v: d.v), rect: rect, back: fp.u0 + fp.v0, id: d.id),
            standAt: standPoint(frame, def, u: d.u, v: d.v, flip: flip, rear: rear),
            facing: facing(flip: flip, rear: rear))
    }
}

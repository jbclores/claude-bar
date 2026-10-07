import CoreGraphics
import Foundation

/// One floor fully placed: its frame, materials and everything standing or hanging in it.
public struct BuiltRoom: Equatable, Sendable {
    public var floorId: Int
    public var frame: FloorFrame
    public var wallHeight: Double
    public var floorTexture: SurfaceMaterial?
    public var wallTexture: WallMaterial?
    public var rugs: [PlacedRug]
    public var wallItems: [PlacedWallItem]
    public var elevator: ElevatorSpot?
    public var fixtures: [PlacedFixture]
    public var desks: [PlacedDesk]
    public var props: [PlacedProp]
    /// Lounge seat spots: `sleep` first, then `sit`, each in placement order.
    public var seats: [RoomSpot]
    /// The floor parallelogram and both walls' boxes, in world px.
    public var bounds: CGRect
}

extension BuiltRoom {
    /// Everything that can cover a cat, as Office.tsx 329-337 lists it.
    public var boxes: [OccluderBox] {
        desks.map(\.box) + props.map(\.box) + fixtures.map(\.box)
    }
}

public enum RoomGeometry {
    private static func finite(_ p: WorldPoint) -> Bool { p.x.isFinite && p.y.isFinite }

    private static func finite(_ r: CGRect) -> Bool {
        r.origin.x.isFinite && r.origin.y.isFinite && r.size.width.isFinite && r.size.height.isFinite
    }

    private static func finite(_ f: FloorPoint) -> Bool { f.u.isFinite && f.v.isFinite }

    private static func finite(_ b: OccluderBox) -> Bool {
        finite(b.front) && finite(b.rect) && (b.back?.isFinite ?? true)
    }

    private static func finite(_ f: Footprint) -> Bool {
        f.u0.isFinite && f.u1.isFinite && f.v0.isFinite && f.v1.isFinite
    }

    private static func finite(_ s: RoomSpot) -> Bool { finite(s.standAt) && s.lift.isFinite }

    /// nil when the floor has no room, corners or grid size, the frame is degenerate, or any number in the result
    /// isn't finite.
    public static func build(floor: Floor, catalogue: RoomCatalogue) -> BuiltRoom? {
        guard let room = floor.room, let corners = floor.corners, let grid = floor.gridSize,
              grid.isFinite, grid > 0,
              [corners.top, corners.left, corners.bottom, corners.right].allSatisfy(finite) else { return nil }
        let wallHeight = catalogue.wallHeight(floorId: floor.id, room: room)
        guard wallHeight.isFinite, let frame = FloorFrame(corners: corners),
              frame.eu.isFinite, frame.ev.isFinite else { return nil }

        let wallItems = room.wallItems.compactMap { WallItems.place($0, frame: frame, catalogue: catalogue, wallHeight: wallHeight) }
        let fixtures = room.wallItems.compactMap { WallItems.fixture($0, frame: frame, catalogue: catalogue, wallHeight: wallHeight) }
        let elevator = room.wallItems.lazy.compactMap { WallItems.elevatorSpot($0, frame: frame, catalogue: catalogue) }.first
        let desks = room.desks.compactMap { DeskPlacer.place($0, frame: frame, catalogue: catalogue) }
        let props = PropPlacer.place(room: room, frame: frame, catalogue: catalogue, desks: desks, gridSize: grid)
        let rugs = PropPlacer.rugs(room: room, frame: frame, catalogue: catalogue, gridSize: grid)
        let rugSpots = PropPlacer.rugSpots(room: room, frame: frame, catalogue: catalogue, gridSize: grid)

        let all = props.flatMap(\.spots) + rugSpots
        let isSeat = { (s: RoomSpot) in (s.pose == "sleep" || s.pose == "sit") && s.kind != "meeting" }
        let seats = all.filter { isSeat($0) && $0.pose == "sleep" } + all.filter { isSeat($0) && $0.pose != "sleep" }

        var bounds = CGRect(x: corners.top.x, y: corners.top.y, width: 0, height: 0)
        for p in [corners.left, corners.bottom, corners.right] {
            bounds = bounds.union(CGRect(x: p.x, y: p.y, width: 0, height: 0))
        }
        for side in [WallSide.left, .right] {
            let w = frame.wall(side, height: wallHeight)
            bounds = bounds.union(CGRect(x: 0, y: 0, width: w.length, height: wallHeight).applying(w.transform))
        }

        guard finite(bounds), wallHeight.isFinite,
              rugs.allSatisfy({ finite($0.rect) }),
              wallItems.allSatisfy({ finite($0.box) }),
              fixtures.allSatisfy({ finite($0.rect) && finite($0.box) }),
              desks.allSatisfy({ finite($0.rect) && finite($0.box) && finite($0.footprint) && finite($0.standAt) }),
              props.allSatisfy({ finite($0.rect) && finite($0.box) && finite($0.footprint) && $0.spots.allSatisfy(finite) }),
              rugSpots.allSatisfy(finite),
              elevator.map({ finite($0.standAt) }) ?? true else { return nil }

        return BuiltRoom(
            floorId: floor.id, frame: frame, wallHeight: wallHeight,
            floorTexture: catalogue.floors[room.floor], wallTexture: catalogue.walls[room.wall],
            rugs: rugs, wallItems: wallItems, elevator: elevator, fixtures: fixtures,
            desks: desks, props: props, seats: seats, bounds: bounds)
    }

    /// Office.tsx 209: a rough figure box (body, ears, tail, shadow) for finding the furniture it overlaps.
    public static func figure(feet: WorldPoint, catHeight h: Double, lift: Double) -> CGRect {
        let left = feet.x - h * 0.5, right = feet.x + h * 0.5
        let top = feet.y - lift - h * 1.1, bottom = feet.y + h * 0.1
        return CGRect(x: left, y: top, width: right - left, height: bottom - top)
    }

    /// occlusion.ts OVER_STEPS.
    static let overSteps = 8

    /// occlusion.ts 42-47.
    static func overZ(_ b: OccluderBox, depth: Double) -> Int {
        guard let back = b.back else { return b.z + 1 }
        let span = b.front.u + b.front.v - back
        let t = span > 0 ? min(1, max(0, (depth - back) / span)) : 1
        return b.z + 1 + Int((t * Double(overSteps) + 0.5).rounded(.down))
    }

    /// occlusion.ts 54-55 (strict overlap).
    private static func overlaps(_ a: CGRect, _ b: CGRect) -> Bool {
        a.minX < b.maxX && b.minX < a.maxX && a.minY < b.maxY && b.minY < a.maxY
    }

    /// occlusion.ts 65-76: z-index for a cat at `feet` whose figure covers `figure`.
    public static func catZ(feet: FloorPoint, figure: CGRect, boxes: [OccluderBox], perch: String?) -> Int {
        let depth = feet.u + feet.v
        var above = Int.min
        var below = Int.max
        for b in boxes {
            guard overlaps(figure, b.rect) else { continue }
            if let perch, b.id == perch {
                above = max(above, overZ(b, depth: depth))
            } else if feet.u < b.front.u && feet.v < b.front.v {
                below = min(below, b.z - 1)
            } else {
                above = max(above, overZ(b, depth: depth))
            }
        }
        return min(max(FloorFrame.depthZ(depth), above), below)
    }
}

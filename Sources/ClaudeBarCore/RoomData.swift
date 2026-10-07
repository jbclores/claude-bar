// Sources/ClaudeBarCore/RoomData.swift
import Foundation

/// A point in Cat Office's world (screen) pixels. Not CGPoint, so Codable and Equatable are plain.
public struct WorldPoint: Codable, Equatable, Sendable {
    public var x: Double
    public var y: Double
    public init(x: Double, y: Double) { self.x = x; self.y = y }
}

/// A point on a floor's own axes (u, v), as Cat Office places things.
public struct FloorPoint: Codable, Equatable, Sendable {
    public var u: Double
    public var v: Double
    public init(u: Double, v: Double) { self.u = u; self.v = v }
}

/// The floor diamond's corners in world px (building.json floor.corners).
public struct FloorCorners: Codable, Equatable, Sendable {
    public var top: WorldPoint
    public var left: WorldPoint
    public var bottom: WorldPoint
    public var right: WorldPoint
    public init(top: WorldPoint, left: WorldPoint, bottom: WorldPoint, right: WorldPoint) {
        self.top = top; self.left = left; self.bottom = bottom; self.right = right
    }
}

public enum WallSide: String, Codable, Sendable { case left, right }

public struct RugPlacement: Codable, Equatable, Sendable {
    public var id: String
    public var rug: String
    public var u: Double
    public var v: Double
    public var w: Double
    public var d: Double
    public var turned: Bool?
}

public struct WallItemPlacement: Codable, Equatable, Sendable {
    public var id: String
    public var item: String
    public var wall: WallSide
    public var at: Double
    public var width: Double?
    public var height: Double?
    public var bottom: Double?
    public var up: Double?
    public var transom: Bool?
}

public struct PropPlacement: Codable, Equatable, Sendable {
    public var id: String
    public var prop: String
    public var u: Double
    public var v: Double
    public var facing: Int
    public var decor: Bool?
    public var panels: Int?
    public var companionsOff: Bool?
}

public struct DeskPlacement: Codable, Equatable, Sendable {
    public var id: String
    public var desk: String
    public var u: Double
    public var v: Double
    public var flip: Bool
    public var rear: Bool?
}

/// A floor's room (building.json floor.room): its materials and everything placed in it.
public struct FloorRoom: Codable, Equatable, Sendable {
    public var floor: String
    public var wall: String
    public var wallHeight: Double?
    public var rugs: [RugPlacement]
    public var wallItems: [WallItemPlacement]
    public var props: [PropPlacement]
    public var desks: [DeskPlacement]

    public init(floor: String, wall: String, wallHeight: Double? = nil, rugs: [RugPlacement] = [],
                wallItems: [WallItemPlacement] = [], props: [PropPlacement] = [], desks: [DeskPlacement] = []) {
        self.floor = floor; self.wall = wall; self.wallHeight = wallHeight
        self.rugs = rugs; self.wallItems = wallItems; self.props = props; self.desks = desks
    }
}

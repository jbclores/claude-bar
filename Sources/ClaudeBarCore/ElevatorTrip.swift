// Sources/ClaudeBarCore/ElevatorTrip.swift
import CoreGraphics
import Foundation

/// A cat's ride between floors, Cat Office's sequence (simulation-engine.ts:32-34, 1134-1152) at 2× speed: walk to the
/// elevator, board (fade out), ride (base + per floor), arrive (fade in), then walk to its spot (WalkPath).
public struct ElevatorTrip: Equatable, Sendable {
    public static let board: TimeInterval = 0.35
    public static let rideBase: TimeInterval = 0.7
    public static let perFloor: TimeInterval = 0.35
    public static let arrive: TimeInterval = 0.35

    public enum Phase: Equatable, Sendable {
        case walkingIn(Double), boarding(Double), riding, arriving(Double), arrived
    }

    public var from: Int
    public var to: Int
    public var start: Date
    /// How long the walk to the elevator takes (from WalkPath length and the cat's speed).
    public var walkIn: TimeInterval

    public init(from: Int, to: Int, start: Date, walkIn: TimeInterval) {
        self.from = from
        self.to = to
        self.start = start
        self.walkIn = walkIn
    }

    public static func rideTime(floors: Int) -> TimeInterval { rideBase + perFloor * Double(max(1, floors)) }

    /// Cats waiting for the elevator stand in 3 places (Cat Office: (index % 3) - 1).
    public static func waitingOffset(index: Int) -> CGFloat { CGFloat(index % 3 - 1) * 12 }

    /// room.ts ELEVATOR_WAIT_SPREAD: how far apart (floor u, v) the waiting places are.
    public static let waitSpread = (u: 0.014, v: 0.035)

    /// simulation-engine.ts elevatorPoint: the `index`th waiting place by the elevator's door spot (the walk grid
    /// check that Cat Office makes is not ported).
    public static func waitingPlace(_ door: FloorPoint, index: Int) -> FloorPoint {
        let k = Double(index % 3 - 1)
        return FloorPoint(u: door.u + k * waitSpread.u, v: door.v + k * waitSpread.v)
    }

    public var arrivalTime: Date { start + walkIn + Self.board + Self.rideTime(floors: abs(to - from)) }
    public var doneTime: Date { arrivalTime + Self.arrive }

    public func phase(at now: Date) -> Phase {
        let t = now.timeIntervalSince(start)
        if t < walkIn { return .walkingIn(walkIn > 0 ? t / walkIn : 1) }
        if t < walkIn + Self.board { return .boarding((t - walkIn) / Self.board) }
        if now < arrivalTime { return .riding }
        if now < doneTime { return .arriving(now.timeIntervalSince(arrivalTime) / Self.arrive) }
        return .arrived
    }
}

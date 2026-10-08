import Foundation

/// Where one of Cat Office's cats is and what it's doing, as the patched bridge shares it
/// (server/agent-bridge/cat-assignments.ts `place`, built by src/agents/live/places-share.ts `buildPlaces`).
public struct MirrorPlace: Equatable, Sendable, Decodable {
    public var floor: Int
    /// Position on the floor, in Cat Office's tile units (finite).
    public var u: Double
    public var v: Double
    public var direction: String
    /// Cat Office's CatState (agent.types.ts): idle, walking, working, talking, blocked, celebrating, resting, riding-elevator.
    public var state: String
    public var gesture: String
    public var expression: String
    /// A nap (activities.ts `asleep`, or a spot with a sleeping pose).
    public var asleep: Bool

    public struct Activity: Equatable, Sendable, Decodable {
        /// The spot's activity kind (activities.ts), "elevator" while riding, or "other" with no spot.
        public var kind: String
        /// The badge Cat Office shows.
        public var label: String
        public init(kind: String, label: String) {
            self.kind = kind
            self.label = label
        }
    }
    public var activity: Activity?
    /// The spot the cat is at now.
    public var spotId: String?
    public var minutesLeft: Double?
    /// walking, using, elevator or idle.
    public var phase: String
    public var ridingTo: Int?
    /// The cat's sprite set.
    public var catId: String?
    /// When the page posted it (ms since 1970).
    public var at: Double
    /// The cat's own name (spares only).
    public var name: String?
    /// "spare:<sim id>" (spares only).
    public var key: String?

    /// typing / standing / sitting / asleep. Asleep wins; "working" types (except at the printer); "resting" (reading, relaxing on a rug or
    /// window seat: activities.ts) and the window seat sit; everything else stands.
    public var pose: MirrorPose {
        if asleep { return .asleep }
        // Printing is also state "working" (activities.ts printer) but the cat stands at the printer.
        if state == "working" { return activity?.kind == "printer" ? .standing : .typing }
        if state == "resting" || activity?.kind == "window-seat" { return .sitting }
        return .standing
    }

    private enum CodingKeys: String, CodingKey {
        case floor, u, v, direction, state, gesture, expression, asleep, activity, spotId, minutesLeft, phase, ridingTo, catId, at, name, key
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        floor = try c.decode(Int.self, forKey: .floor)
        u = try c.decode(Double.self, forKey: .u)
        v = try c.decode(Double.self, forKey: .v)
        guard u.isFinite, v.isFinite else {
            throw DecodingError.dataCorruptedError(forKey: .u, in: c, debugDescription: "position is not finite")
        }
        direction = try c.decode(String.self, forKey: .direction)
        state = try c.decode(String.self, forKey: .state)
        gesture = try c.decodeIfPresent(String.self, forKey: .gesture) ?? "none"
        expression = try c.decodeIfPresent(String.self, forKey: .expression) ?? "default"
        asleep = try c.decodeIfPresent(Bool.self, forKey: .asleep) ?? false
        activity = (try? c.decodeIfPresent(Activity.self, forKey: .activity)) ?? nil
        spotId = try? c.decodeIfPresent(String.self, forKey: .spotId)
        minutesLeft = (try? c.decodeIfPresent(Double.self, forKey: .minutesLeft)).flatMap { $0 }.flatMap { $0.isFinite ? $0 : nil }
        phase = try c.decodeIfPresent(String.self, forKey: .phase) ?? "idle"
        ridingTo = (try? c.decodeIfPresent(Int.self, forKey: .ridingTo)) ?? nil
        catId = try? c.decodeIfPresent(String.self, forKey: .catId)
        at = try c.decode(Double.self, forKey: .at)
        guard at.isFinite else {
            throw DecodingError.dataCorruptedError(forKey: .at, in: c, debugDescription: "time is not finite")
        }
        name = try? c.decodeIfPresent(String.self, forKey: .name)
        key = try? c.decodeIfPresent(String.self, forKey: .key)
    }
}

public enum MirrorPose: Equatable, Sendable { case typing, standing, sitting, asleep }

public enum MirrorPlaces {
    /// The places count as live for this long after the page last posted them (the page posts every 2 s while shown).
    public static let liveFor: TimeInterval = 10
    /// How far ahead of this Mac's clock a post may be and still count (clock skew).
    static let skew: TimeInterval = 1

    /// The mirror is live: the newest place (`placesAt`, ms since 1970) is within `liveFor` of `now`, and at most
    /// `skew` ahead of it. Nil or non-finite is not live.
    public static func isLive(placesAt: Double?, now: Date) -> Bool {
        guard let placesAt, placesAt.isFinite else { return false }
        let age = now.timeIntervalSince1970 - placesAt / 1000
        return age <= liveFor && age >= -skew
    }
}

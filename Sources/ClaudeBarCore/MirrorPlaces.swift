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

    /// What the cat is doing, for its hover card: "Coffee break · 4 min left" (minutes rounded up), just the label with
    /// no time left, nil with no activity.
    public var activityLine: String? {
        guard let label = activity?.label, !label.isEmpty else { return nil }
        guard let left = minutesLeft, left > 0 else { return label }
        return "\(label) · \(Int(left.rounded(.up))) min left"
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

/// The browser's office as ClaudeBar draws it: each session cat's place (agent id → place) while the mirror is live,
/// none otherwise. Built from the agents' own places only: spare cats never count here (floors, the busy strip, Follow).
public struct OfficeMirror: Equatable, Sendable {
    public var places: [String: MirrorPlace]
    /// The browser's spare cats (no session) while the switch is on and the mirror is live. Drawn only: they are in no
    /// count, Follow, menu bar cat, "N working", sound or notification (those read the agents).
    public var spares: [MirrorPlace] = []

    public static let off = OfficeMirror(places: [:])

    public init(places: [String: MirrorPlace]) {
        self.places = places
    }

    /// The agents' places when the snapshot's places are live at `now` (MirrorPlaces.isLive), else `.off`; with
    /// `showSpares`, also the spare cats that carry a key.
    public init(_ snapshot: OfficeSnapshot?, now: Date, showSpares: Bool = false) {
        guard let snapshot, MirrorPlaces.isLive(placesAt: snapshot.placesAt, now: now) else { self = .off; return }
        places = Dictionary(snapshot.agents.compactMap { a in a.place.map { (a.id, $0) } }, uniquingKeysWith: { a, _ in a })
        if showSpares { spares = snapshot.spares.filter { $0.key != nil } }
    }

    /// How far past the floor's edges (0…1) a mirrored point may be: spots against a wall stand just outside it (the
    /// Lounge's window seat is at u −0.015, room.ts spots on wall props).
    public static let edge = 0.1

    /// Where the browser has this agent's cat, if it can be drawn there: on the floor (u, v within 0…1, give or take `edge`) of a floor the
    /// building has. A cat riding the elevator (phase "elevator") counts on the floor it rides to, if the building has
    /// it. Nil (the rules place the cat) for an ended agent, no place, an unknown floor or a point off the floor.
    public func floor(of agent: OfficeAgent, in building: Building) -> (id: Int, place: MirrorPlace)? {
        guard agent.status != .ended, let p = places[agent.id], let id = Self.floorId(of: p, in: building) else { return nil }
        return (id, p)
    }

    /// The floor a place is drawn on (see `floor(of:in:)`), nil when it can't be drawn.
    public static func floorId(of p: MirrorPlace, in building: Building) -> Int? {
        let onFloor = (-edge...(1 + edge))
        guard onFloor.contains(p.u), onFloor.contains(p.v) else { return nil }
        if p.phase == "elevator", let to = p.ridingTo, building.floor(id: to) != nil { return to }
        return building.floor(id: p.floor) != nil ? p.floor : nil
    }

    /// The spare cats drawn on `floorId`.
    public func spares(on floorId: Int, in building: Building) -> [MirrorPlace] {
        spares.filter { Self.floorId(of: $0, in: building) == floorId }
    }

    /// The `owner` of a spare cat's stand-in agent.
    public static let spareOwner = "spare"

    /// A spare cat as an agent to draw and hover: its key as id, its own name, its own cat, never working or waiting.
    public static func spareAgent(_ p: MirrorPlace) -> OfficeAgent {
        var a = OfficeAgent(id: p.key ?? "spare", name: p.name ?? "Cat", owner: spareOwner, status: .idle, cwd: "", cat: p.catId)
        a.place = p
        return a
    }

    /// The places of `agents` the mirror has on `floorId` (agent id → place), for SceneCast.
    public func places(on floorId: Int, agents: [OfficeAgent], in building: Building) -> [String: MirrorPlace] {
        guard !places.isEmpty else { return [:] }
        var out: [String: MirrorPlace] = [:]
        for a in agents { if let f = floor(of: a, in: building), f.id == floorId { out[a.id] = f.place } }
        return out
    }
}

extension CatPose {
    /// The sprite for a mirrored pose, as Cat Office's cat.sprite.ts catSpriteFor picks it: asleep sleeps; typing
    /// facing away types (no front-facing typing sprite: it stands, as at a turned desk); sitting facing us sits (a
    /// back-facing sit stands); standing with a paw up waves.
    public init(_ place: MirrorPlace) {
        let back = place.direction.hasPrefix("back")
        switch place.pose {
        case .asleep: self = .sleeping
        case .typing: self = back ? .typing : .standing
        case .sitting: self = back ? .standing : .sitting
        case .standing: self = place.gesture == "right-up" ? .waving : .standing
        }
    }
}

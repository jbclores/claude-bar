import Foundation

/// activities.ts ActivityDef: what a cat does at a spot of a kind.
public struct SimActivity: Equatable, Sendable {
    /// A brief pose on arrival (arms up at the snack table).
    public struct Arrival: Equatable, Sendable {
        public var gesture: String
        public var state: SimCatState
        public var seconds: Double
    }

    public var kind: String
    /// Short label for bubbles and the inspector.
    public var label: String
    public var icon: String
    /// Log line when the cat starts; the spot's label is appended.
    public var verb: String
    public var state: SimCatState
    public var gesture: String
    public var expression: String
    public var arrival: Arrival?
    /// Use time in sim minutes.
    public var duration: (min: Double, max: Double)
    /// Total need gain over a full use (keys absent give nothing).
    public var gains: [SimNeedKey: Double]
    /// Lounge activities happen on floor 1; used for travel scoring only.
    public var lounge: Bool
    /// A nap: the cat dozes with its eyes closed.
    public var asleep: Bool

    public static func == (a: SimActivity, b: SimActivity) -> Bool {
        a.kind == b.kind && a.label == b.label && a.icon == b.icon && a.verb == b.verb && a.state == b.state
            && a.gesture == b.gesture && a.expression == b.expression && a.arrival == b.arrival
            && a.duration == b.duration && a.gains == b.gains && a.lounge == b.lounge && a.asleep == b.asleep
    }
}

/// activities.ts ACTIVITIES and activityFor.
public enum SimActivities {
    private static func def(_ kind: String, _ label: String, _ icon: String, _ verb: String, _ state: SimCatState, _ gesture: String,
                            _ expression: String, arrival: SimActivity.Arrival? = nil, _ duration: (Double, Double),
                            _ gains: [SimNeedKey: Double], lounge: Bool, asleep: Bool = false) -> SimActivity {
        SimActivity(kind: kind, label: label, icon: icon, verb: verb, state: state, gesture: gesture, expression: expression,
                    arrival: arrival, duration: (duration.0, duration.1), gains: gains, lounge: lounge, asleep: asleep)
    }

    /// activities.ts 30-103, in its order.
    static let table: [SimActivity] = [
        def("desk", "Working", "laptop", "sat down to work at the", .working, "both-down", "default",
            (30, 60), [:], lounge: false),
        def("coffee", "Coffee break", "coffee", "is making coffee at the", .idle, "both-down", "happy",
            (6, 12), [.energy: 35, .thirst: 20, .social: 5], lounge: false),
        def("water", "Drinking water", "droplet", "is getting water from the", .idle, "both-down", "default",
            (4, 7), [.thirst: 55], lounge: false),
        def("printer", "Printing", "printer", "is printing at the", .working, "right-up", "default",
            (4, 8), [.fun: 5], lounge: false),
        def("meeting", "In a meeting", "message", "joined a chat at the", .talking, "left-up", "happy",
            (18, 35), [.social: 65, .fun: 10], lounge: false),
        def("plant", "Watering plants", "sprout", "is watering the", .idle, "right-up", "happy",
            (4, 8), [.fun: 20], lounge: false),
        def("sofa", "Napping", "moon", "is napping on the", .resting, "both-down", "happy",
            (18, 35), [.energy: 65, .social: 10], lounge: true, asleep: true),
        def("beanbag", "Lounging", "smile", "is lounging on the", .resting, "both-down", "happy",
            (14, 26), [.energy: 45, .fun: 20], lounge: true, asleep: true),
        def("cat-bed", "Cat nap", "moon", "curled up in the", .resting, "both-down", "happy",
            (20, 40), [.energy: 80], lounge: true, asleep: true),
        def("cat-tree", "Climbing", "paw", "is climbing the", .celebrating, "both-down", "happy",
            arrival: .init(gesture: "both-up", state: .celebrating, seconds: 3),
            (8, 15), [.fun: 60, .energy: -10], lounge: true),
        def("window-seat", "Reading", "book", "is reading at the", .resting, "both-down", "default",
            (14, 26), [.fun: 35, .energy: 25], lounge: true),
        def("bookshelf", "Browsing books", "library", "is browsing the", .idle, "right-up", "default",
            (5, 10), [.fun: 25], lounge: true),
        def("snacks", "Snacking", "cookie", "found treats at the", .idle, "both-down", "happy",
            arrival: .init(gesture: "both-up", state: .celebrating, seconds: 2),
            (6, 12), [.hunger: 70, .social: 10], lounge: true),
        def("rug", "Stretching", "stretch", "is stretching on the", .idle, "both-up", "happy",
            (6, 12), [.energy: 15, .fun: 25, .social: 15], lounge: true),
    ]

    /// Every kind, in ACTIVITIES' order.
    public static let kinds: [String] = table.map(\.kind)

    /// activities.ts ACTIVITIES.
    public static let all: [String: SimActivity] = Dictionary(uniqueKeysWithValues: table.map { ($0.kind, $0) })

    /// activities.ts activityFor 111-142: the activity at a spot of `kind` with `pose` (absent: 'stand'). Sleeping
    /// anywhere is a nap; sitting on a rug is relaxing. nil for a kind with no activity (the elevator).
    public static func activity(kind: String, pose: String?) -> SimActivity? {
        guard let base = all[kind] else { return nil }
        let pose = pose ?? "stand"
        if pose == "sleep" && !base.asleep {
            var a = base
            a.label = "Napping"
            a.icon = "moon"
            a.verb = "is napping on the"
            a.state = .resting
            a.gesture = "both-down"
            a.expression = "happy"
            a.arrival = nil
            a.duration = (18, 35)
            a.gains[.energy] = max(base.gains[.energy] ?? 0, 60)
            a.asleep = true
            return a
        }
        if pose == "sit" && kind == "rug" {
            var a = base
            a.label = "Relaxing"
            a.icon = "smile"
            a.verb = "is relaxing on the"
            a.state = .resting
            a.gesture = "both-down"
            a.arrival = nil
            a.gains[.energy] = max(base.gains[.energy] ?? 0, 25)
            return a
        }
        return base
    }

    /// activityFor for a room spot.
    public static func activity(for spot: RoomSpot) -> SimActivity? {
        activity(kind: spot.kind, pose: spot.pose)
    }
}

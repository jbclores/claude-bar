import Foundation

/// agent.types.ts NeedKey, in NEED_KEYS order.
public enum SimNeedKey: String, CaseIterable, Sendable {
    case energy, thirst, hunger, social, fun
}

/// agent.types.ts CatState.
public enum SimCatState: String, Sendable {
    case idle, walking, working, talking, blocked, celebrating, resting
    case ridingElevator = "riding-elevator"
}

/// agent.types.ts Needs: 0 = desperate, 100 = fully satisfied.
public struct SimNeeds: Equatable, Sendable {
    public var energy: Double
    public var thirst: Double
    public var hunger: Double
    public var social: Double
    public var fun: Double

    public init(energy: Double, thirst: Double, hunger: Double, social: Double, fun: Double) {
        self.energy = energy; self.thirst = thirst; self.hunger = hunger; self.social = social; self.fun = fun
    }

    public subscript(key: SimNeedKey) -> Double {
        get {
            switch key {
            case .energy: energy
            case .thirst: thirst
            case .hunger: hunger
            case .social: social
            case .fun: fun
            }
        }
        set {
            switch key {
            case .energy: energy = newValue
            case .thirst: thirst = newValue
            case .hunger: hunger = newValue
            case .social: social = newValue
            case .fun: fun = newValue
            }
        }
    }

    /// The lowest need.
    public var lowest: Double { SimNeedKey.allCases.map { self[$0] }.min()! }

    /// simulation-engine.ts DECAY: loss per sim minute.
    public static let decay: [SimNeedKey: Double] = [.energy: 0.14, .thirst: 0.2, .hunger: 0.12, .social: 0.15, .fun: 0.15]

    /// simulation-engine.ts STEP: the engine steps 1/30 sim minute at a time.
    public static let step = 1.0 / 30

    /// simulation-engine.ts clampNeed.
    static func clampNeed(_ x: Double) -> Double { min(100, max(0, x)) }

    /// simulation-engine.ts createRuntime 979: each need `rng.range(55, 95)`, one draw per key in NEED_KEYS order.
    public static func starting(rng: inout SimRng) -> SimNeeds {
        var n = SimNeeds(energy: 0, thirst: 0, hunger: 0, social: 0, fun: 0)
        for key in SimNeedKey.allCases { n[key] = rng.range(55, 95) }
        return n
    }

    /// simulation-engine.ts decayNeeds 1100-1108 for one step of `dt` sim minutes, the cat being in `state`.
    public mutating func decay(state: SimCatState, dt: Double) {
        for key in SimNeedKey.allCases {
            var rate = Self.decay[key]!
            if state == .working && (key == .energy || key == .fun) { rate *= 1.3 }
            if state == .resting && key == .energy { rate = 0 }
            if state == .talking && key == .social { rate = 0 }
            self[key] = Self.clampNeed(self[key] - rate * dt)
        }
    }

    /// `needs` after `minutes` of decay in `state`, stepped as the engine steps: round(minutes × 30) steps of STEP.
    public static func decayed(_ needs: SimNeeds, state: SimCatState, minutes: Double) -> SimNeeds {
        var n = needs
        let steps = Int((minutes * 30 + 0.5).rounded(.down)) // JS Math.round
        for _ in 0..<max(0, steps) { n.decay(state: state, dt: step) }
        return n
    }

    /// simulation-engine.ts use() 1495-1498: one step of `dt` while using a spot for `total` minutes adds
    /// `gain / total × dt` of every non-zero gain (negatives too), clamped.
    public func gained(_ activity: SimActivity, total: Double, dt: Double) -> SimNeeds {
        var n = self
        for key in SimNeedKey.allCases {
            let gain = activity.gains[key] ?? 0
            if gain != 0 { n[key] = Self.clampNeed(n[key] + (gain / total) * dt) }
        }
        return n
    }
}

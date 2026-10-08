import Foundation

/// rng.ts Rng: a small seeded PRNG (mulberry32) so simulation runs are reproducible. JS's `>>> 0`, `Math.imul` and
/// `^=` all keep the low 32 bits, so wrapping UInt32 arithmetic gives the same numbers.
public struct SimRng: Sendable {
    private var state: UInt32

    public init(seed: UInt32) {
        state = seed
    }

    /// rng.ts next.
    public mutating func next() -> Double {
        state = state &+ 0x6d2b79f5
        var t = state
        t = (t ^ (t >> 15)) &* (t | 1)
        t ^= t &+ ((t ^ (t >> 7)) &* (t | 61))
        return Double(t ^ (t >> 14)) / 4294967296
    }

    /// rng.ts range.
    public mutating func range(_ min: Double, _ max: Double) -> Double {
        min + (max - min) * next()
    }

    /// rng.ts int: floor of range(min, maxExclusive).
    public mutating func int(_ min: Int, _ maxExclusive: Int) -> Int {
        Int(range(Double(min), Double(maxExclusive)).rounded(.down))
    }

    /// rng.ts pick.
    public mutating func pick<T>(_ items: [T]) -> T {
        items[int(0, items.count)]
    }

    /// rng.ts chance.
    public mutating func chance(_ p: Double) -> Bool {
        next() < p
    }

    /// rng.ts shuffle: a shuffled copy (Fisher-Yates from the end).
    public mutating func shuffle<T>(_ items: [T]) -> [T] {
        var out = items
        var i = out.count - 1
        while i > 0 {
            let j = int(0, i + 1)
            out.swapAt(i, j)
            i -= 1
        }
        return out
    }
}

// Sources/ClaudeBarCore/FloorChoice.swift
/// Which floor the Office tab shows: Follow (the default) shows FloorPlan.followTarget; picking a floor (menu or
/// strip) shows that one until Follow is pressed. A picked floor that no longer exists shows the target.
public struct FloorChoice: Equatable, Sendable {
    public var follow = true
    public var manual: Int?

    public init() {}

    public func shown(target: Int, floors: [Int]) -> Int {
        guard !follow, let manual, floors.contains(manual) else { return target }
        return manual
    }

    public mutating func pick(_ id: Int) {
        manual = id
        follow = false
    }

    public mutating func step(_ delta: Int, from shown: Int, floors: [Int]) {
        let sorted = floors.sorted()
        guard let i = sorted.firstIndex(of: shown) else { return }
        pick(sorted[min(sorted.count - 1, max(0, i + delta))])
    }

    public mutating func resumeFollow() {
        follow = true
        manual = nil
    }

    /// The picked floor was deleted from Cat Office's building: show Follow's floor again, with Follow on.
    public mutating func reconcile(floors: [Int]) {
        if let manual, !floors.contains(manual) { resumeFollow() }
    }
}

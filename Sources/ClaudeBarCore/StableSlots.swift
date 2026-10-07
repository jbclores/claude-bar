/// Spots that stay put: each id keeps the slot it had, newcomers take the first free slots (in the given order),
/// ids beyond `count` are left out. So one cat arriving doesn't shuffle every other cat (Cat Office's home desks).
public enum StableSlots {
    public static func assign(_ ids: [String], previous: [String?], count: Int) -> [String?] {
        var slots = [String?](repeating: nil, count: count)
        let wanted = Set(ids)
        for (i, id) in previous.prefix(count).enumerated() where id.map(wanted.contains) == true { slots[i] = id }
        let placed = Set(slots.compactMap { $0 })
        var free = slots.indices.filter { slots[$0] == nil }[...]
        for id in ids where !placed.contains(id) {
            guard let i = free.popFirst() else { break }
            slots[i] = id
        }
        return slots
    }
}

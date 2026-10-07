import Foundation

/// The pictures a room's picture is drawn from, and whether a picture drawn with some of them can be kept.
public enum RoomArt {
    /// Every picture the room draws, each once: its path, and whether it's needed at its own pixel size (sliced
    /// and repeated art). At night also the lit copies' art and masks (RoomGlow.lit).
    public static func paths(_ room: BuiltRoom, night: Bool) -> [(path: String, natural: Bool)] {
        var order: [String] = []
        var natural: [String: Bool] = [:]
        func add(_ p: String?, _ whole: Bool = false) {
            guard let p, !p.isEmpty else { return }
            if natural[p] == nil { order.append(p) }
            natural[p] = (natural[p] ?? false) || whole
        }
        func add(_ glow: RoomGlow?) {
            guard let glow, glow.lit(night: night) else { return }
            add(glow.image)
            add(glow.mask)
        }
        add(room.floorTexture?.image)
        add(room.wallTexture?.image, true)
        room.rugs.forEach { add($0.image) }
        for item in room.wallItems {
            add(item.image)
            for piece in item.pieces {
                switch piece {
                case .nineSlice(let image, _, _), .repeatX(let image, _): add(image, true)
                case .stretch(let image, _), .decor(let image, _): add(image)
                case .fill: break
                }
            }
            item.glows.forEach { add($0.glow) }
        }
        for d in room.desks { add(d.image) }
        for p in room.props { add(p.image); add(p.glow) }
        for f in room.fixtures { add(f.image); add(f.glow) }
        return order.map { (path: $0, natural: natural[$0] ?? false) }
    }

    /// The needed pictures not loaded, in order.
    public static func missing(_ needed: [String], loaded: Set<String>) -> [String] {
        needed.filter { !loaded.contains($0) }
    }

    /// A room's picture is kept for the session only when every picture it needs was loaded; one drawn without some
    /// (a timeout, a missing file) is shown but drawn again on the next try.
    public static func complete(_ needed: [String], loaded: Set<String>) -> Bool {
        missing(needed, loaded: loaded).isEmpty
    }
}

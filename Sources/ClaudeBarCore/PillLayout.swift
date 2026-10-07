import CoreGraphics
import Foundation

/// Which cats' name pills to show: none may overlap another shown one. Rects are in view points after zoom, so at
/// 2× (cats further apart, pills the same size) more fit.
public enum PillLayout {
    /// Greedy in a stable order: `priority` (cats that need you) first, then by key. A pill is shown only if it
    /// overlaps no pill already shown.
    public static func visible(_ pills: [String: CGRect], priority: Set<String>) -> Set<String> {
        let order = pills.keys.sorted { a, b in
            let pa = priority.contains(a), pb = priority.contains(b)
            return pa != pb ? pa : a < b
        }
        var shown: [CGRect] = []
        var out: Set<String> = []
        for key in order {
            guard let r = pills[key], !shown.contains(where: { $0.intersects(r) }) else { continue }
            shown.append(r)
            out.insert(key)
        }
        return out
    }
}

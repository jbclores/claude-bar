import Foundation

/// A label that fits a width by shortening only its middle part ("10 pnp-ufd… · 3 cats").
public enum FitText {
    public static func label(prefix: String, name: String, suffix: String, width: Double, measure: (String) -> Double) -> String {
        let full = prefix + name + suffix
        guard measure(full) > width else { return full }
        var kept = name
        while !kept.isEmpty {
            kept.removeLast()
            let candidate = prefix + kept.trimmingCharacters(in: .whitespaces) + "…" + suffix
            if measure(candidate) <= width { return candidate }
        }
        return prefix + "…" + suffix
    }
}

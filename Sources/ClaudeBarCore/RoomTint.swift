import Foundation

/// Ports Cat Office's room-tint.ts: paint for a room's walls and floor (FloorRoom.wallTint / floorTint), a
/// '#rrggbb' colour laid over the material's texture. Each pixel's lightness relative to the texture's own (its body,
/// without the dark ink strokes) scales the paint colour; the dark strokes keep their own ink (RoomShell.tsx
/// TintFilter). Unset: the material as drawn.
public enum RoomTint {
    /// Rec. 709 luma weights.
    public static let lumaWeights = (0.2126, 0.7152, 0.0722)
    /// Pixels darker than this (luma) are ink strokes: kept as drawn, and left out of the texture's own lightness.
    public static let inkLuma = 0.2
    /// Luma above which nothing is ink; between inkLuma and this the ink fades out.
    public static let inkFade = 0.33

    /// normalTint: a stored tint ('#rrggbb', lower case), or nil when it isn't one.
    public static func normal(_ x: String?) -> String? {
        guard let x, x.count == 7, x.first == "#", x.dropFirst().allSatisfy(\.isHexDigit) else { return nil }
        return x.lowercased()
    }

    /// hexRgb: '#rrggbb' as 0...1 channels.
    public static func rgb(_ hex: String) -> (Double, Double, Double) {
        let n = Int(hex.dropFirst(), radix: 16) ?? 0
        return (Double((n >> 16) & 255) / 255, Double((n >> 8) & 255) / 255, Double(n & 255) / 255)
    }

    /// A colour's luma, 0...1.
    public static func luma(_ hex: String) -> Double {
        let c = rgb(hex)
        return c.0 * lumaWeights.0 + c.1 * lumaWeights.1 + c.2 * lumaWeights.2
    }

    /// tintMatrix: the paint as an feColorMatrix (20 values, row by row): each pixel's luma over the texture's own
    /// `base` luma, times the tint.
    public static func tintMatrix(_ tint: String, base: Double) -> [Double] {
        let (r, g, b) = rgb(tint)
        let k = 1 / max(0.05, base)
        func row(_ c: Double) -> [Double] { [c * k * lumaWeights.0, c * k * lumaWeights.1, c * k * lumaWeights.2, 0, 0] }
        return row(r) + row(g) + row(b) + [0, 0, 0, 1, 0]
    }

    /// inkMatrix: colour as drawn, alpha 1 for strokes darker than inkLuma, 0 above inkFade.
    public static func inkMatrix() -> [Double] {
        let k = 1 / (inkFade - inkLuma)
        return [1, 0, 0, 0, 0, 0, 1, 0, 0, 0, 0, 0, 1, 0, 0,
                -k * lumaWeights.0, -k * lumaWeights.1, -k * lumaWeights.2, 0, k * inkFade]
    }

    /// textureLuma: the mean luma of a texture's pixels that aren't ink or clear, from RGBA bytes (not
    /// premultiplied). nil for a texture with no such pixels.
    public static func textureLuma(_ data: [UInt8]) -> Double? {
        var sum = 0.0, n = 0
        var i = 0
        while i + 3 < data.count {
            defer { i += 4 }
            if data[i + 3] < 128 { continue }
            let l = (Double(data[i]) * lumaWeights.0 + Double(data[i + 1]) * lumaWeights.1 + Double(data[i + 2]) * lumaWeights.2) / 255
            if l < inkFade { continue }
            sum += l
            n += 1
        }
        return n > 0 ? sum / Double(n) : nil
    }

    /// An feColorMatrix on one pixel (0...1, not premultiplied), clamped like SVG's.
    static func apply(_ m: [Double], _ p: (Double, Double, Double, Double)) -> (Double, Double, Double, Double) {
        func row(_ i: Int) -> Double {
            let o = i * 5
            return min(1, max(0, m[o] * p.0 + m[o + 1] * p.1 + m[o + 2] * p.2 + m[o + 3] * p.3 + m[o + 4]))
        }
        return (row(0), row(1), row(2), row(3))
    }

    /// RoomShell.tsx TintFilter on one pixel (0...1, not premultiplied): the paint (`matrix`, a tintMatrix), with
    /// the pixel's ink (inkMatrix's alpha, `in` the pixel's alpha) merged over it.
    public static func paint(_ p: (Double, Double, Double, Double), matrix: [Double]) -> (Double, Double, Double, Double) {
        let paint = apply(matrix, p)
        let inkAlpha = apply(inkMatrix(), p).3 * p.3
        let a = inkAlpha + paint.3 * (1 - inkAlpha)
        guard a > 0 else { return (0, 0, 0, 0) }
        func mix(_ src: Double, _ painted: Double) -> Double { (src * inkAlpha + painted * paint.3 * (1 - inkAlpha)) / a }
        return (mix(p.0, paint.0), mix(p.1, paint.1), mix(p.2, paint.2), a)
    }
}

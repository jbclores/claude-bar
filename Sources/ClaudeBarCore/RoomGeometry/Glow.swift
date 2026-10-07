import CoreGraphics
import Foundation

/// A lit copy Cat Office draws over a lamp, wall light, window decoration or screen: `image` (the switched-on art,
/// or the piece's own) shown inside the alpha `mask`, unshaded by the night, in its lighting modes
/// (RoomProps.tsx glow, RoomShell.tsx wall-glow and DecorArt lit, src/lighting/glow.ts).
public struct RoomGlow: Equatable, Sendable {
    public var image: String
    public var mask: String
    /// Lighting modes it's lit in; nil: whenever the lamps are on (`.emissive--lamp`).
    public var modes: [String]?

    public init(image: String, mask: String, modes: [String]?) {
        self.image = image; self.mask = mask; self.modes = modes
    }

    /// ClaudeBar's night is Cat Office's 'night' lighting, which has its lamps on (looks.ts); its day lights nothing.
    public func lit(night: Bool) -> Bool {
        night && (modes.map { $0.contains("night") } ?? true)
    }

    static func make(image: String?, mask: String?, modes: [String]?) -> RoomGlow? {
        guard let image, !image.isEmpty, let mask, !mask.isEmpty else { return nil }
        return RoomGlow(image: image, mask: mask, modes: modes)
    }
}

/// A glow on a wall item, in the item box's own px (as WindowPiece).
public struct GlowPiece: Equatable, Sendable {
    public var glow: RoomGlow
    public var rect: CGRect

    public init(glow: RoomGlow, rect: CGRect) { self.glow = glow; self.rect = rect }
}

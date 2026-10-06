import CoreGraphics

/// Zoom and pan of the office drawing, in the room's own points: shown = content × scale + offset. The scale stays
/// within 1×–3× and the room always covers the view (no panning past its edges).
public struct ZoomPan: Equatable, Sendable {
    public static let range: ClosedRange<CGFloat> = 1...3

    public private(set) var scale: CGFloat = 1
    public private(set) var offset: CGPoint = .zero

    public init() {}

    public var isZoomed: Bool { scale > 1.001 }

    /// Zooms by `factor`, keeping the room point under `point` (shown coordinates) where it is.
    public mutating func zoom(by factor: CGFloat, at point: CGPoint, in size: CGSize) {
        let next = min(Self.range.upperBound, max(Self.range.lowerBound, scale * factor))
        let content = unzoom(point)
        scale = next
        offset = CGPoint(x: point.x - content.x * next, y: point.y - content.y * next)
        clamp(size)
    }

    public mutating func pan(by delta: CGSize, in size: CGSize) {
        offset = CGPoint(x: offset.x + delta.width, y: offset.y + delta.height)
        clamp(size)
    }

    /// Double-click: 2× at `point`, or back to the whole room when zoomed.
    public mutating func toggle(at point: CGPoint, in size: CGSize) {
        if isZoomed { reset() } else { zoom(by: 2 / scale, at: point, in: size) }
    }

    public mutating func reset() {
        scale = 1
        offset = .zero
    }

    /// The room point shown at `point`.
    public func unzoom(_ point: CGPoint) -> CGPoint {
        CGPoint(x: (point.x - offset.x) / scale, y: (point.y - offset.y) / scale)
    }

    private mutating func clamp(_ size: CGSize) {
        let minX = size.width - size.width * scale, minY = size.height - size.height * scale
        offset = CGPoint(x: min(0, max(minX, offset.x)), y: min(0, max(minY, offset.y)))
        if !isZoomed { reset() }
    }
}

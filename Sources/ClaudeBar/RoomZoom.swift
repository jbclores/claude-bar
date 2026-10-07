import AppKit
import ClaudeBarCore
import SwiftUI

/// Zoom and pan of one office drawing (the dropdown's, or the peek's). AppKit views feed it pinch, scroll, drag
/// and double-click (SwiftUI gestures don't reliably arrive in a popover that isn't the active window);
/// OfficeRoomView draws with it and reports where the room is.
@MainActor
final class RoomZoom: ObservableObject {
    @Published private(set) var view = ZoomPan()
    /// The room, in the "office" coordinate space (top-left origin, same as the hosting view's).
    var roomRect: CGRect = .zero
    private var dragFrom: CGPoint?

    /// The "1×" pill shown while zoomed: clicking it shows the whole room again.
    static let pillSize = CGSize(width: 34, height: 18)
    var pillRect: CGRect {
        CGRect(x: roomRect.maxX - Self.pillSize.width - 8, y: roomRect.minY + 8, width: Self.pillSize.width, height: Self.pillSize.height)
    }

    func reset() { view.reset() }

    /// For --render-peek with CLAUDEBAR_RENDER_ZOOM: zoom to `factor` at a room point.
    func renderZoom(_ factor: CGFloat, at point: CGPoint) { view.zoom(by: factor, at: point, in: roomRect.size) }

    func contains(_ point: CGPoint) -> Bool { roomRect.contains(point) }

    /// Handles a mouse, scroll or magnify event at `point` (office space). False: not for the room, pass it on.
    func handle(_ event: NSEvent, at point: CGPoint) -> Bool {
        let local = CGPoint(x: point.x - roomRect.minX, y: point.y - roomRect.minY)
        let size = roomRect.size
        switch event.type {
        case .magnify:
            guard contains(point) else { return false }
            view.zoom(by: 1 + event.magnification, at: local, in: size)
            return true
        case .scrollWheel:
            guard contains(point) else { return false }
            if event.modifierFlags.contains(.command) {
                let delta = event.hasPreciseScrollingDeltas ? event.scrollingDeltaY : event.scrollingDeltaY * 8
                view.zoom(by: exp(delta * 0.01), at: local, in: size)
                return true
            }
            guard view.isZoomed else { return false }
            let k: CGFloat = event.hasPreciseScrollingDeltas ? 1 : 8
            view.pan(by: CGSize(width: event.scrollingDeltaX * k, height: event.scrollingDeltaY * k), in: size)
            return true
        case .leftMouseDown:
            guard contains(point) else { return false }
            if view.isZoomed && pillRect.contains(point) {
                view.reset()
                return true
            }
            if event.clickCount == 2 {
                view.toggle(at: local, in: size)
                return true
            }
            guard view.isZoomed else { return false }
            dragFrom = point
            return true
        case .leftMouseDragged:
            guard let from = dragFrom else { return false }
            view.pan(by: CGSize(width: point.x - from.x, height: point.y - from.y), in: size)
            dragFrom = point
            return true
        case .leftMouseUp:
            guard dragFrom != nil else { return false }
            dragFrom = nil
            return true
        default:
            return false
        }
    }
}

/// Wraps a hosting view: zoom and pan events over the office room go to `zoom`, everything else to the host.
/// Only takes clicks inside its own frame (a hosting view claims clicks past its edges).
final class ZoomingContainer: NSView {
    private let host: NSView
    private let zoom: RoomZoom
    private let cursor: RoomCursor?

    init(_ host: NSView, zoom: RoomZoom, cursor: RoomCursor? = nil) {
        self.host = host
        self.zoom = zoom
        self.cursor = cursor
        super.init(frame: .zero)
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseMoved, .mouseEnteredAndExited, .cursorUpdate, .activeAlways, .inVisibleRect],
                                       owner: self, userInfo: nil))
        translatesAutoresizingMaskIntoConstraints = false
        host.translatesAutoresizingMaskIntoConstraints = false
        addSubview(host)
        clipsToBounds = true
        NSLayoutConstraint.activate([
            host.leadingAnchor.constraint(equalTo: leadingAnchor),
            host.trailingAnchor.constraint(equalTo: trailingAnchor),
            host.topAnchor.constraint(equalTo: topAnchor),
            host.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
        setContentHuggingPriority(.required, for: .vertical)
        setContentCompressionResistancePriority(.required, for: .vertical)
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    /// The room is ours (so its events reach this view); the rest is the host's.
    override func hitTest(_ point: NSPoint) -> NSView? {
        guard frame.contains(point) else { return nil }
        let inHost = host.convert(point, from: superview)
        return zoom.contains(inHost) ? self : super.hitTest(point)
    }

    // Unused events go up the responder chain (super), never down to the host: its default passes them
    // back up to this view, which looped until the stack overflowed.
    private func officePoint(_ event: NSEvent) -> CGPoint {
        // Events without a window (e.g. built from a CGEvent) carry screen coordinates.
        let inWindow = event.window == nil ? (window?.convertPoint(fromScreen: event.locationInWindow) ?? event.locationInWindow) : event.locationInWindow
        return host.convert(inWindow, from: nil)
    }

    override func magnify(with event: NSEvent) { if !zoom.handle(event, at: officePoint(event)) { super.magnify(with: event) } }
    override func scrollWheel(with event: NSEvent) { if !zoom.handle(event, at: officePoint(event)) { super.scrollWheel(with: event) } }
    override func mouseDown(with event: NSEvent) {
        cursor?.pressed()
        if !zoom.handle(event, at: officePoint(event)) { super.mouseDown(with: event) }
    }
    override func mouseDragged(with event: NSEvent) { if !zoom.handle(event, at: officePoint(event)) { super.mouseDragged(with: event) } }
    override func mouseUp(with event: NSEvent) {
        cursor?.released()
        if !zoom.handle(event, at: officePoint(event)) { super.mouseUp(with: event) }
    }

    // Bongo Cat over the room (Cat Office's cursor); the host's own cursors everywhere else.
    override func mouseMoved(with event: NSEvent) { cursor?.moved(inRoom: zoom.contains(officePoint(event))); super.mouseMoved(with: event) }
    override func mouseEntered(with event: NSEvent) { cursor?.moved(inRoom: zoom.contains(officePoint(event))) }
    override func mouseExited(with event: NSEvent) { cursor?.moved(inRoom: false) }
    override func cursorUpdate(with event: NSEvent) {
        if cursor?.inRoom == true { cursor?.moved(inRoom: true) } else { super.cursorUpdate(with: event) }
    }
}

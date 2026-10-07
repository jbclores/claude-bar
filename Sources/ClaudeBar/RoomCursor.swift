import AppKit
import ClaudeBarCore

/// Cat Office's Bongo Cat cursor over the office room (BongoCursor): paws down while the pointer is over the room,
/// slapping while the mouse button is held. The art comes from Cat Office (cached); without it the arrow stays.
@MainActor
final class RoomCursor {
    private var cursors: [BongoCursor.Frame: NSCursor] = [:]
    private(set) var inRoom = false
    private var heldSince: Date?
    private var timer: Timer?

    init(art: ArtCache) {
        Task { @MainActor [weak self] in
            for frame in BongoCursor.Frame.allCases {
                guard let data = await art.image(path: BongoCursor.path(frame), maxPixelSize: 64),
                      let image = NSImage(data: data) else { continue }
                image.size = NSSize(width: 32, height: 32)
                // Hotspot at the arrow's tip (top left), as in Cat Office.
                self?.cursors[frame] = NSCursor(image: image, hotSpot: .zero)
            }
            self?.apply()
        }
    }

    /// The pointer moved, over the room or not. Leaving the room hands the arrow back once.
    func moved(inRoom now: Bool) {
        if now {
            inRoom = true
            apply()
        } else if inRoom {
            inRoom = false
            stopHolding()
            NSCursor.arrow.set()
        }
    }

    /// The mouse button went down over the room: the cat slaps until it's released.
    func pressed() {
        guard inRoom else { return }
        heldSince = Date()
        apply()
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: BongoCursor.slap / 2, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.apply() }
        }
    }

    func released() {
        stopHolding()
        apply()
    }

    /// The cursor showing now, for the zoom test.
    var frame: BongoCursor.Frame? {
        guard inRoom, !cursors.isEmpty else { return nil }
        return BongoCursor.frame(heldFor: heldSince.map { Date().timeIntervalSince($0) },
                                 reduceMotion: NSWorkspace.shared.accessibilityDisplayShouldReduceMotion)
    }

    private func stopHolding() {
        timer?.invalidate()
        timer = nil
        heldSince = nil
    }

    private func apply() {
        guard let frame, let cursor = cursors[frame] ?? cursors[.rest] else { return }
        cursor.set()
    }
}

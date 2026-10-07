import Foundation

/// The office's lofi loop (Resources/office-lofi.wav, made by scripts/make-music.py): on while the office is on
/// screen — the dropdown's Office tab, or the hover popup once it has been open a moment (so passing the pointer
/// over the menu bar icon stays quiet) — and the 🎵 button is on.
public enum OfficeMusic {
    public static let popupDelay: TimeInterval = 1.0
    public static let fadeIn: TimeInterval = 1.5
    public static let fadeOut: TimeInterval = 1.0

    public static func shouldPlay(on: Bool, officeTab: Bool, peekShownSince: Date?, now: Date) -> Bool {
        guard on else { return false }
        if officeTab { return true }
        if let since = peekShownSince { return now.timeIntervalSince(since) >= popupDelay }
        return false
    }

    /// Background level: half the cat sounds' volume.
    public static func volume(sounds: Double) -> Double { sounds * 0.5 }
}

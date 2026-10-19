import AppKit
import ClaudeBarCore

/// Plays the cat sounds shipped in the app (Resources/*.wav, made by scripts/make-sounds.py).
@MainActor
final class CatSoundPlayer {
    private var sounds: [CatSound: NSSound] = [:]

    init() {
        for sound in CatSound.allCases {
            if let url = Bundle.main.url(forResource: sound.rawValue, withExtension: "wav") {
                sounds[sound] = NSSound(contentsOf: url, byReference: true)
            }
        }
    }

    /// Plays `sound`; returns how long it lasts (0 when the sound is missing).
    @discardableResult func play(_ sound: CatSound, volume: Double) -> TimeInterval {
        // A copy each time, so a sound still playing doesn't block the next.
        guard let s = sounds[sound]?.copy() as? NSSound else { return 0 }
        s.volume = Float(min(1, max(0, volume)))
        s.play()
        return s.duration
    }

    /// How long `sound` lasts (0 when missing).
    func duration(_ sound: CatSound) -> TimeInterval { sounds[sound]?.duration ?? 0 }
}

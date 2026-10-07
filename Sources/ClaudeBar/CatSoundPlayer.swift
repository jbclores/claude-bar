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

    func play(_ sound: CatSound, volume: Double) {
        // A copy each time, so a sound still playing doesn't block the next.
        guard let s = sounds[sound]?.copy() as? NSSound else { return }
        s.volume = Float(min(1, max(0, volume)))
        s.play()
    }
}

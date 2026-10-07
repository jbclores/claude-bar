import AVFoundation
import ClaudeBarCore

/// The office's lofi loop (Resources/office-lofi.wav): fades in when asked to play, fades out and pauses (keeping
/// its place) when not, so it picks up where it left off.
@MainActor
final class LofiPlayer {
    private let player: AVAudioPlayer?
    private var playing = false
    private var pause: DispatchWorkItem?

    init() {
        player = Bundle.main.url(forResource: "office-lofi", withExtension: "wav").flatMap { try? AVAudioPlayer(contentsOf: $0) }
        player?.numberOfLoops = -1
        player?.volume = 0
        player?.prepareToPlay()
    }

    func set(playing want: Bool, volume: Double) {
        guard let player else { return }
        if want {
            pause?.cancel()
            if !player.isPlaying { player.volume = 0; player.play() }
            // Starting fades in; already playing (a volume change) follows quickly.
            player.setVolume(Float(volume), fadeDuration: playing ? 0.2 : OfficeMusic.fadeIn)
        } else if playing {
            player.setVolume(0, fadeDuration: OfficeMusic.fadeOut)
            let work = DispatchWorkItem { [weak self] in
                guard let self, !self.playing else { return }
                player.pause()
            }
            pause = work
            DispatchQueue.main.asyncAfter(deadline: .now() + OfficeMusic.fadeOut, execute: work)
        }
        playing = want
    }
}

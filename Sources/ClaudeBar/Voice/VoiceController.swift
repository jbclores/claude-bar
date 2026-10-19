import ClaudeBarCore
import Foundation

/// ClaudeBar's voice: spoken alerts, one sentence at a time (the listening half comes with push-to-talk).
@MainActor final class VoiceController: ObservableObject {
    private unowned let state: AppState
    private let speaker: SpeechOutput
    /// Alerts that arrived but are not yet in the speaking queue (so a burst can be capped together).
    private var arriving: [String] = []
    private var queue: [String] = []
    private var speaking = false
    private var flushScheduled = false
    private var lastSpoken: [String: Date] = [:]
    /// The key is held or a conversation reply is speaking: alerts wait in the queue.
    var holding = false {
        didSet { if !holding { flush() } }
    }

    init(state: AppState, speaker: SpeechOutput) {
        self.state = state
        self.speaker = speaker
    }

    /// Queues `sentence`; `key` ("needsYou|<key>" / "finished|<key>") stops the same alert repeating within 60 s.
    /// `afterSound` waits 1.2 s so the meow or purr comes first.
    func alert(_ sentence: String, key: String? = nil, afterSound: Bool) {
        guard state.sideEffects else { return }
        let now = Date()
        if let key {
            guard SpokenAlert.shouldSpeak(key: key, last: lastSpoken, now: now) else { return }
            lastSpoken[key] = now
        }
        arriving.append(sentence)
        guard !flushScheduled else { return }
        flushScheduled = true
        Task { @MainActor in
            if afterSound { try? await Task.sleep(nanoseconds: 1_200_000_000) } else { await Task.yield() }
            self.flushScheduled = false
            self.flush()
        }
    }

    private func flush() {
        guard !holding else { return }
        if !arriving.isEmpty {
            queue += SpokenAlert.capped(arriving)
            arriving = []
        }
        speakNext()
    }

    private func speakNext() {
        guard !speaking, !holding, !queue.isEmpty else { return }
        speaking = true
        speaker.speak(queue.removeFirst()) { [weak self] in
            guard let self else { return }
            self.speaking = false
            self.speakNext()
        }
    }
}

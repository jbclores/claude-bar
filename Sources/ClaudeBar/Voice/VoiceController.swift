import AppKit
import ClaudeBarCore
import Foundation

/// ClaudeBar's voice: spoken alerts, one sentence at a time, and push-to-talk (hold the talk shortcut, speak, let go).
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

    private let listener: SpeechInput
    /// When the talk key went down (nil: not held).
    private var pressedAt: Date?
    private var listenTimeout: Timer?
    /// Longest listen; then it ends as if the key were let go.
    static let maxListen: TimeInterval = 15
    /// A shorter press is a slip: nothing is heard or said.
    static let minListen: TimeInterval = 0.3

    init(state: AppState, speaker: SpeechOutput, listener: SpeechInput) {
        self.state = state
        self.speaker = speaker
        self.listener = listener
    }

    // MARK: Push-to-talk

    /// The talk key went down: a tick, alerts wait, and the listener starts.
    func keyDown() {
        guard state.sideEffects, state.settings.voice.talk, pressedAt == nil else { return }
        pressedAt = Date()
        NSSound(named: "Tink")?.play()
        holding = true
        state.voiceListening = true
        do {
            try listener.start(hints: hints)
            state.voiceProblem = nil
        } catch {
            pressedAt = nil
            state.voiceListening = false
            problem(error as? ListenProblem ?? .microphoneDenied)
            return
        }
        listenTimeout = Timer.scheduledTimer(withTimeInterval: Self.maxListen, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated { self?.keyUp() }
        }
    }

    /// The talk key was let go (or 15 s passed): a slip is dropped, else what was heard is handled.
    func keyUp() {
        guard let pressedAt else { return }
        self.pressedAt = nil
        listenTimeout?.invalidate()
        listenTimeout = nil
        if Date().timeIntervalSince(pressedAt) < Self.minListen {
            listener.cancel()
            state.voiceListening = false
            holding = false
            return
        }
        listener.finish { [weak self] transcript in
            guard let self else { return }
            self.state.voiceListening = false
            self.heard(transcript ?? "")
        }
    }

    /// What was said while the key was held. Task 8 turns it into a command; for now nothing is understood.
    func heard(_ transcript: String) {
        reply("Sorry, I didn't catch that.")
    }

    /// Says `sentence` now (alerts keep waiting until it is said).
    private func reply(_ sentence: String) {
        holding = true
        speaker.speak(sentence) { [weak self] in self?.holding = false }
    }

    /// Can't listen: says why, shows it in Settings, and opens the Privacy pane for a denied permission.
    private func problem(_ problem: ListenProblem) {
        state.voiceProblem = problem.sentence
        if let url = problem.settingsURL { NSWorkspace.shared.open(url) }
        reply(problem.sentence)
    }

    /// Words likely to be said: the waiting sessions' names and their question's option labels.
    private var hints: [String] {
        var words: [String] = []
        for agent in state.office?.agents ?? [] {
            guard let prompt = agent.pendingPrompt else { continue }
            words.append(agent.label)
            if case .question(let questions) = prompt { words += questions.flatMap { $0.options.map(\.label) } }
        }
        return words
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

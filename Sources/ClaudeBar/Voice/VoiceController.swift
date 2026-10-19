import AppKit
import ClaudeBarCore
import Combine
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
    /// The talk key is held, its transcript is on the way, or a reply is speaking: alerts wait in the queue.
    /// Worked out from those, so one ending can't let alerts through while another still holds them.
    var holding: Bool { pressedAt != nil || awaitingTranscript || replying > 0 }

    private let listener: SpeechInput
    /// When the talk key went down (nil: not held).
    private var pressedAt: Date?
    /// The key was let go and the listener is turning what was said into text.
    private var awaitingTranscript = false
    /// Replies still speaking.
    private var replying = 0
    private var listenTimeout: Timer?
    /// The spoken back-and-forth ("which one?", "say yes"); it forgets what it asked after 20 s.
    private var conversation = VoiceConversation()
    /// Sent answers still waiting for Cat Office's word, by a number of their own.
    private var watching: [Int: AnyCancellable] = [:]
    private var nextWatch = 0
    /// How long to wait for Cat Office to take a spoken answer.
    static let answerTimeout: TimeInterval = 15
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
        // Starting drops a transcript still on its way from the last press.
        awaitingTranscript = false
        NSSound(named: "Tink")?.play()
        state.voiceListening = true
        do {
            try listener.start(hints: hints)
            state.voiceProblem = nil
        } catch {
            pressedAt = nil
            state.voiceListening = false
            problem(error as? ListenProblem ?? .microphoneDenied)
            released()
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
            released()
            return
        }
        awaitingTranscript = true
        listener.finish { [weak self] transcript in
            guard let self, self.awaitingTranscript else { return }
            self.awaitingTranscript = false
            self.state.voiceListening = false
            self.heard(transcript ?? "")
            self.released()
        }
    }

    /// Stops any listen at once and drops what was heard ("Talk to ClaudeBar" turned off mid-press).
    func cancelListening() {
        guard pressedAt != nil || awaitingTranscript else { return }
        pressedAt = nil
        awaitingTranscript = false
        listenTimeout?.invalidate()
        listenTimeout = nil
        listener.cancel()
        state.voiceListening = false
        released()
    }

    /// One of the things that hold alerts ended: let them through if nothing else holds them.
    private func released() {
        if !holding { flush() }
    }

    /// What was said while the key was held: answers a waiting session, or tells how things stand.
    func heard(_ transcript: String) {
        let agents = (state.office?.agents ?? []).filter { !$0.isSpare && !$0.isSubagent }
        let waiting = agents.compactMap { a -> VoiceWaiting? in
            guard a.canBeAnswered, a.status == .waiting, let prompt = a.pendingPrompt else { return nil }
            return VoiceWaiting(id: a.id, name: a.label, prompt: prompt)
        }
        let targets = waiting.map { w -> VoiceTarget in
            var options: [String] = []
            if case .question = w.prompt { options = AnswerChoices.of(w.prompt).buttons.map(\.title) }
            return VoiceTarget(id: w.id, name: w.name, options: options)
        }
        let command = VoiceCommand.parse(transcript, targets: targets)
        switch conversation.handle(command, waiting: waiting, now: Date()) {
        case .say(let sentence):
            reply(sentence)
        case let .send(agentId, prompt, button, then):
            send(agentId, prompt: prompt, button: button, then: then)
        case .status:
            let live = agents.filter { $0.status != .ended }
            let needYou = live.filter { $0.status == .waiting || state.attention.contains($0.key) }
            let rest = live.filter { a in !needYou.contains { $0.id == a.id } }
            reply(VoiceStatus.status(running: rest.filter { $0.status == .working }.map(\.label),
                                     needYou: needYou.map(\.label),
                                     idle: rest.filter { $0.status == .idle }.map(\.label)))
        case .usage:
            reply(VoiceStatus.usage(state.output.usage, forecast: state.usageForecast, time: AppState.usageTime))
        case .recap:
            reply(VoiceStatus.recap(state.todayRecap))
        }
    }

    /// Sends the answer, then says `then` once Cat Office takes it, or why it didn't (AnswerState's words). Alerts
    /// keep waiting until that is said.
    private func send(_ agentId: String, prompt: PendingPrompt, button: Int, then: String) {
        let buttons = AnswerChoices.of(prompt).buttons
        guard let agent = state.office?.agents.first(where: { $0.id == agentId }), buttons.indices.contains(button) else {
            reply("That one isn't waiting anymore.")
            return
        }
        replying += 1
        let key = nextWatch
        nextWatch += 1
        var finished = false
        /// The outcome, said once; nil while the answer is still on its way.
        func outcome(_ answer: AnswerState?) -> String? {
            switch answer {
            case .sent: return then
            case .failed(let message): return VoiceStatus.failure(message)
            // Cleared: the session stopped waiting on that prompt (the answer closed it).
            case nil: return then
            case .sending: return nil
            }
        }
        let finish = { [weak self] (sentence: String) in
            guard let self, !finished else { return }
            finished = true
            self.watching[key] = nil
            self.replying -= 1
            self.reply(sentence)
        }
        state.answer(agent, buttons[button], prompt: prompt)
        if let sentence = outcome(state.answerState[agentId]) { finish(sentence); return }
        // `answerState` publishes before it changes: the new dictionary is the one handed in.
        watching[key] = state.$answerState.dropFirst().sink { answers in
            MainActor.assumeIsolated {
                if let sentence = outcome(answers[agentId]) { finish(sentence) }
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.answerTimeout) {
            MainActor.assumeIsolated { finish(VoiceStatus.failure("Couldn't reach Cat Office")) }
        }
    }

    /// Says `sentence` now (alerts keep waiting until it is said).
    private func reply(_ sentence: String) {
        replying += 1
        speaker.speak(sentence) { [weak self] in
            guard let self else { return }
            self.replying -= 1
            self.released()
        }
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

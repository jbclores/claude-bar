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
    /// The alert being said (nil: none, or a reply is speaking).
    private var speaking: String?
    /// Counts alerts handed to the speaker, so a cut-off alert's late "done" is ignored.
    private var utterance = 0
    /// When the arriving alerts are let into the queue (nil: not scheduled).
    private var flushDue: Date?
    private var flushWork: DispatchWorkItem?
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
    /// How long to wait for Cat Office to take a spoken answer (longer than CatOfficeActions' 15 s request timeout).
    static let answerTimeout: TimeInterval = 20
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

    /// The talk key went down: speech stops, a tick, alerts wait, and the listener starts.
    func keyDown() {
        guard state.sideEffects, state.settings.voice.talk, pressedAt == nil else { return }
        pressedAt = Date()
        // Starting drops a transcript still on its way from the last press.
        awaitingTranscript = false
        // Nothing speaks into the open microphone: an alert cut off is said again later; a reply cut off is dropped.
        if let cut = speaking {
            queue.insert(cut, at: 0)
            speaking = nil
            utterance += 1
        }
        speaker.stop()
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
        // Terminal, iTerm and VS Code sessions too, so "allow" can say to answer them in their terminal.
        let waiting = agents.compactMap { a -> VoiceWaiting? in
            guard a.status == .waiting, let prompt = a.pendingPrompt else { return nil }
            return VoiceWaiting(id: a.id, name: a.label, prompt: prompt, answerable: a.canBeAnswered)
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

    /// Sends the answer, then says `then` once Cat Office takes it, or why it wasn't sent (the answer's own result,
    /// never the row's state). Alerts keep waiting until that is said.
    private func send(_ agentId: String, prompt: PendingPrompt, button: Int, then: String) {
        let buttons = AnswerChoices.of(prompt).buttons
        guard let agent = state.office?.agents.first(where: { $0.id == agentId }), buttons.indices.contains(button) else {
            reply("That one isn't waiting anymore.")
            return
        }
        replying += 1
        var finished = false
        let finish = { [weak self] (sentence: String) in
            guard let self, !finished else { return }
            finished = true
            self.replying -= 1
            self.reply(sentence)
        }
        state.answer(agent, buttons[button], prompt: prompt) { refusal in
            MainActor.assumeIsolated { finish(refusal.map(VoiceStatus.failure) ?? then) }
        }
        // A fallback: Cat Office never answered.
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
    /// `delay` lets the meow or purr finish first (its length + 0.2 s; 0 with no sound); a burst waits for its longest.
    func alert(_ sentence: String, key: String? = nil, delay: TimeInterval) {
        guard state.sideEffects else { return }
        let now = Date()
        if let key {
            guard SpokenAlert.shouldSpeak(key: key, last: lastSpoken, now: now) else { return }
            lastSpoken[key] = now
        }
        arriving.append(sentence)
        let due = now.addingTimeInterval(max(0, delay))
        if let flushDue, flushDue >= due { return }
        flushDue = due
        flushWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.flushDue = nil
                self.flushWork = nil
                self.flush()
            }
        }
        flushWork = work
        // Even with no sound, the next turn of the run loop: alerts arriving together are capped together.
        DispatchQueue.main.asyncAfter(deadline: .now() + max(0, delay), execute: work)
    }

    private func flush() {
        guard !holding else { return }
        // Arriving alerts wait for their sound; ones already queued can go.
        if flushDue == nil, !arriving.isEmpty {
            queue += SpokenAlert.capped(arriving)
            arriving = []
        }
        speakNext()
    }

    private func speakNext() {
        guard speaking == nil, !holding, !queue.isEmpty else { return }
        let sentence = queue.removeFirst()
        speaking = sentence
        utterance += 1
        let mine = utterance
        speaker.speak(sentence) { [weak self] in
            guard let self, self.utterance == mine else { return }
            self.speaking = nil
            self.speakNext()
        }
    }
}

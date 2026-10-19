import AppKit
import AVFoundation
import Speech

/// Why ClaudeBar can't listen: said out loud and shown under "Talk to ClaudeBar" in Settings.
enum ListenProblem: Error {
    case microphoneDenied, speechDenied, notOnDevice, noMicrophone

    /// The sentence ClaudeBar says (and Settings shows).
    var sentence: String {
        switch self {
        case .microphoneDenied: "I need microphone access; I've opened Settings."
        case .speechDenied: "I need speech recognition access; I've opened Settings."
        case .notOnDevice: "Turn on dictation in System Settings to talk to ClaudeBar."
        case .noMicrophone: "I can't find a microphone."
        }
    }

    /// The Privacy pane to open for a denied permission (nil: nothing to open).
    var settingsURL: URL? {
        switch self {
        case .microphoneDenied: URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone")
        case .speechDenied: URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_SpeechRecognition")
        case .notOnDevice, .noMicrophone: nil
        }
    }
}

/// Something that turns what is said while the talk key is held into text.
@MainActor protocol SpeechInput: AnyObject {
    /// Starts listening; `hints` are words likely to be said (session names, option labels).
    func start(hints: [String]) throws
    /// Stops listening and calls `done` once with what was heard (nil: nothing).
    func finish(_ done: @escaping (String?) -> Void)
    /// Stops listening and drops what was heard.
    func cancel()
}

/// The Mac's microphone and on-device speech recognition (nothing leaves the Mac).
@MainActor final class SystemListener: SpeechInput {
    private let engine = AVAudioEngine()
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private var done: ((String?) -> Void)?
    private var heard: String?
    /// One per start: a late callback from an earlier listen is ignored.
    private var session = 0
    /// Our tap is on the input node (removed even when the engine stopped by itself).
    private var tapped = false
    /// Recognition already gave its last result (the audio ended early, e.g. the input device changed).
    private var ended = false
    /// The device-change observer, removed with the listener.
    nonisolated(unsafe) private var observer: (any NSObjectProtocol)?

    init() {
        // A new input device (AirPods connecting, say) stops the engine: end this listen with what was heard so far;
        // the transcript is handed over when the key is let go.
        observer = NotificationCenter.default.addObserver(forName: .AVAudioEngineConfigurationChange, object: engine, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.audioEnded() }
        }
    }

    deinit {
        if let observer { NotificationCenter.default.removeObserver(observer) }
    }

    /// Asks for microphone and speech recognition permission where not yet asked; `done` gets the first problem, if any.
    static func requestPermissions(_ done: @escaping @MainActor (ListenProblem?) -> Void) {
        AVCaptureDevice.requestAccess(for: .audio) { micOK in
            SFSpeechRecognizer.requestAuthorization { speech in
                Task { @MainActor in
                    if !micOK { done(.microphoneDenied) } else if speech != .authorized { done(.speechDenied) } else { done(onDevice ? nil : .notOnDevice) }
                }
            }
        }
    }

    /// The Mac can recognise speech without sending it anywhere.
    private static var onDevice: Bool { SFSpeechRecognizer()?.supportsOnDeviceRecognition == true }

    func start(hints: [String]) throws {
        cancel()
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized: break
        case .notDetermined:
            // Asked now; this press hears nothing, the next one works.
            AVCaptureDevice.requestAccess(for: .audio) { _ in }
            return
        default: throw ListenProblem.microphoneDenied
        }
        switch SFSpeechRecognizer.authorizationStatus() {
        case .authorized: break
        case .notDetermined:
            SFSpeechRecognizer.requestAuthorization { _ in }
            return
        default: throw ListenProblem.speechDenied
        }
        guard let recognizer = SFSpeechRecognizer(), recognizer.supportsOnDeviceRecognition else { throw ListenProblem.notOnDevice }

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.requiresOnDeviceRecognition = true
        request.contextualStrings = hints
        request.shouldReportPartialResults = false
        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        // No input device: a tap on a 0-channel, 0 Hz format would crash.
        guard format.channelCount > 0, format.sampleRate > 0 else { throw ListenProblem.noMicrophone }
        input.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in
            request.append(buffer)
        }
        tapped = true
        engine.prepare()
        do {
            try engine.start()
        } catch {
            stopAudio()
            throw ListenProblem.noMicrophone
        }
        self.request = request
        session += 1
        let session = session
        task = recognizer.recognitionTask(with: request) { [weak self] result, error in
            let text = result?.bestTranscription.formattedString
            let final = result?.isFinal == true
            Task { @MainActor in
                guard let self, self.session == session else { return }
                if let text { self.heard = text }
                if final || error != nil {
                    // Recognition is over (even with the key still held): the microphone goes off now.
                    self.ended = true
                    self.stopAudio()
                    self.deliver()
                }
            }
        }
    }

    func finish(_ done: @escaping (String?) -> Void) {
        guard request != nil else { done(nil); return }
        self.done = done
        if ended { deliver(); return }
        stopAudio()
        request?.endAudio()
        // Recognition that never ends (no speech at all): give up after 5 s with what was heard.
        let session = session
        Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 5_000_000_000)
            guard let self, self.session == session else { return }
            self.deliver()
        }
    }

    func cancel() {
        done = nil
        stopAudio()
        task?.cancel()
        reset()
    }

    private func deliver() {
        stopAudio()
        guard let done else { return }
        self.done = nil
        let text = heard
        task?.cancel()
        reset()
        done(text)
    }

    /// The input device changed mid-listen: stop the audio and let recognition finish with what it has.
    private func audioEnded() {
        guard request != nil else { return }
        stopAudio()
        request?.endAudio()
    }

    /// Microphone off: safe to call any number of times.
    private func stopAudio() {
        if engine.isRunning { engine.stop() }
        if tapped {
            engine.inputNode.removeTap(onBus: 0)
            tapped = false
        }
    }

    private func reset() {
        task = nil
        request = nil
        heard = nil
        ended = false
    }
}

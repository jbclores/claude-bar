import AVFoundation

/// Something that can say a sentence out loud.
@MainActor protocol SpeechOutput: AnyObject {
    /// Speaks `text`; calls `done` when it has finished or was stopped.
    func speak(_ text: String, done: @escaping () -> Void)
    func stop()
}

/// The Mac's own speech voice, at its default voice and rate.
@MainActor final class SystemSpeaker: NSObject, SpeechOutput, AVSpeechSynthesizerDelegate {
    private let synthesizer = AVSpeechSynthesizer()
    private var pending: [ObjectIdentifier: () -> Void] = [:]

    override init() {
        super.init()
        synthesizer.delegate = self
    }

    func speak(_ text: String, done: @escaping () -> Void) {
        let utterance = AVSpeechUtterance(string: text)
        pending[ObjectIdentifier(utterance)] = done
        synthesizer.speak(utterance)
    }

    /// Stops at once; every sentence not yet finished gets its `done` now (exactly once, even if never started).
    func stop() {
        let cut = pending.values
        pending = [:]
        synthesizer.stopSpeaking(at: .immediate)
        cut.forEach { $0() }
    }

    private func finish(_ utterance: AVSpeechUtterance) {
        pending.removeValue(forKey: ObjectIdentifier(utterance))?()
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        Task { @MainActor in self.finish(utterance) }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        Task { @MainActor in self.finish(utterance) }
    }
}

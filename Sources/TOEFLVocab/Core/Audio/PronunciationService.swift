import AVFoundation
import Foundation

/// Speaks words with `AVSpeechSynthesizer`.
///
/// No audio files are bundled and nothing is ever downloaded: US, UK and AU
/// accents are three different system voices that already ship with iOS. That
/// keeps the app fully offline, keeps the `.ipa` small, and means a new word
/// added to `vocabs.json` is instantly pronounceable with no extra work.
@MainActor
final class PronunciationService: NSObject, ObservableObject {

    @Published private(set) var isSpeaking = false
    /// The word currently being spoken, so a list can highlight the right row.
    @Published private(set) var speakingText: String?

    private let synthesizer = AVSpeechSynthesizer()
    private var hasConfiguredSession = false
    private var currentUtterance: AVSpeechUtterance?

    override init() {
        super.init()
        synthesizer.delegate = self
    }

    /// Speaks `text`. A second tap while speaking restarts it rather than
    /// queueing — repeated taps on a pronunciation button mean "say it again".
    func speak(_ text: String, accent: SpeechAccent, rate: Double) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        if synthesizer.isSpeaking {
            synthesizer.stopSpeaking(at: .immediate)
        }

        configureSessionIfNeeded()

        let utterance = AVSpeechUtterance(string: trimmed)
        utterance.voice = Self.voice(for: accent)
        utterance.rate = Float(rate.clamped(to: AppSettings.minimumSpeechRate...AppSettings.maximumSpeechRate))
        utterance.pitchMultiplier = 1.0
        utterance.postUtteranceDelay = 0

        speakingText = trimmed
        currentUtterance = utterance
        synthesizer.speak(utterance)
    }

    func stop() {
        synthesizer.stopSpeaking(at: .immediate)
        currentUtterance = nil
        isSpeaking = false
        speakingText = nil
        deactivateSession()
    }

    // MARK: Voice selection

    private static func voice(for accent: SpeechAccent) -> AVSpeechSynthesisVoice? {
        let matching = AVSpeechSynthesisVoice.speechVoices()
            .filter { $0.language == accent.localeIdentifier }

        // Enhanced voices sound markedly better, but they are an optional
        // download the user may not have, so fall back through the tiers.
        if let enhanced = matching.first(where: { $0.quality == .enhanced }) {
            return enhanced
        }
        if let any = matching.first {
            return any
        }
        return AVSpeechSynthesisVoice(language: accent.localeIdentifier)
            ?? AVSpeechSynthesisVoice(language: "en-US")
    }

    // MARK: Audio session

    private func configureSessionIfNeeded() {
        guard !hasConfiguredSession else { return }
        do {
            let session = AVAudioSession.sharedInstance()
            // `.playback` so pronunciation still works with the ring/silent
            // switch flipped to silent — a muted vocabulary app is a bug report.
            // `.duckOthers` lowers the user's music instead of stopping it.
            try session.setCategory(.playback, mode: .spokenAudio, options: [.duckOthers])
            try session.setActive(true)
            hasConfiguredSession = true
        } catch {
            #if DEBUG
            print("[Speech] Audio session setup failed: \(error)")
            #endif
        }
    }

    private func deactivateSession() {
        guard hasConfiguredSession else { return }
        do {
            try AVAudioSession.sharedInstance().setActive(false, options: [.notifyOthersOnDeactivation])
            hasConfiguredSession = false
        } catch {
            #if DEBUG
            print("[Speech] Audio session deactivation failed: \(error)")
            #endif
        }
    }

    private func finish(_ utterance: AVSpeechUtterance) {
        // A cancelled older utterance can report completion after its
        // replacement starts. Only the current one owns the audio session.
        guard currentUtterance === utterance else { return }
        currentUtterance = nil
        isSpeaking = false
        speakingText = nil
        deactivateSession()
    }
}

// MARK: - AVSpeechSynthesizerDelegate

extension PronunciationService: AVSpeechSynthesizerDelegate {

    nonisolated func speechSynthesizer(
        _ synthesizer: AVSpeechSynthesizer,
        didStart utterance: AVSpeechUtterance
    ) {
        Task { @MainActor [weak self] in
            guard let self, self.currentUtterance === utterance else { return }
            self.isSpeaking = true
        }
    }

    nonisolated func speechSynthesizer(
        _ synthesizer: AVSpeechSynthesizer,
        didFinish utterance: AVSpeechUtterance
    ) {
        Task { @MainActor [weak self] in
            self?.finish(utterance)
        }
    }

    nonisolated func speechSynthesizer(
        _ synthesizer: AVSpeechSynthesizer,
        didCancel utterance: AVSpeechUtterance
    ) {
        Task { @MainActor [weak self] in
            self?.finish(utterance)
        }
    }
}

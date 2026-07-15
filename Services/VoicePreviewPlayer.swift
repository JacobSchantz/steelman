import Foundation
import AVFoundation
import Combine

/// Auditions a single Kokoro voice from the Settings sheet: renders one short, fixed sample
/// sentence in the chosen speaker and plays it, so a listener can hear a voice before
/// committing to it.
///
/// Deliberately tiny next to `ClipPreviewPlayer` — no scrubber, no completion rules, no feed
/// coupling. Its whole job is "play this one sentence in this voice, and tell the UI which
/// voice is currently sounding" so the settings list can flag the playing row. Like the feed
/// player it prefers Kokoro (the only path on which the eleven speakers actually sound
/// different) and falls back to `AVSpeechSynthesizer` when the weights aren't downloaded yet.
@MainActor
final class VoicePreviewPlayer: ObservableObject {
    /// The speaker id currently sounding — drives the row's animated speaker icon. Nil when
    /// nothing is playing.
    @Published private(set) var playingVoiceID: Int32?
    /// The speaker id whose sample is still rendering. Kokoro's first synth of a phrase can
    /// take a beat, so the row shows a spinner until audio starts.
    @Published private(set) var preparingVoiceID: Int32?

    private var player: AVPlayer?
    private var endObserver: NSObjectProtocol?
    private var renderTask: Task<Void, Never>?
    private let synthesizer = AVSpeechSynthesizer()
    private var synthDelegate: PreviewSynthDelegate?
    private var sessionConfigured = false

    /// The one sentence every voice reads. Naming the speaker makes the audition
    /// self-identifying — you hear *who* it is as well as how they sound, and it's short
    /// enough to render almost instantly.
    static func sample(for voice: KokoroVoice) -> String {
        "Hi, I'm \(voice.name). Here's how I'll sound reading your feed."
    }

    /// Whether an audible, voice-distinct preview is possible right now. When false, samples
    /// fall back to the system voice and every speaker sounds the same — the settings footer
    /// says so, so the listener isn't misled.
    static var canPreviewDistinctVoices: Bool { SpeechRenderer.isAvailable }

    /// Audition `voice`. Tapping the voice already playing stops it (a toggle); tapping a
    /// different one switches to it.
    func preview(_ voice: KokoroVoice) {
        if playingVoiceID == voice.id || preparingVoiceID == voice.id {
            stop()
            return
        }
        stop()
        configureSession()

        let text = Self.sample(for: voice)
        let speaker = voice.id

        // Kokoro when it can actually render — that's the only path on which the speakers
        // differ. A previously-rendered sample is an ordinary WAV, so replays are instant.
        if SpeechRenderer.isAvailable {
            if let url = SpeechRenderer.cachedURL(for: text, speaker: speaker) {
                playingVoiceID = voice.id
                playAudio(url: url)
                return
            }

            preparingVoiceID = voice.id
            renderTask = Task { [weak self] in
                let url = await SpeechRenderer.shared.render(text, speaker: speaker)
                guard let self, !Task.isCancelled, self.preparingVoiceID == voice.id else { return }
                self.preparingVoiceID = nil
                if let url {
                    self.playingVoiceID = voice.id
                    self.playAudio(url: url)
                } else {
                    // Synthesis failed — speak it rather than leave a dead button.
                    self.speakFallback(text, voiceID: voice.id)
                }
            }
            return
        }

        // Weights aren't installed yet: the system voice can't distinguish speakers, but a
        // sample still confirms volume and pace, which beats a silent tap.
        speakFallback(text, voiceID: voice.id)
    }

    func stop() {
        renderTask?.cancel()
        renderTask = nil
        preparingVoiceID = nil
        playingVoiceID = nil
        synthesizer.delegate = nil
        synthDelegate = nil
        synthesizer.stopSpeaking(at: .immediate)
        removePlayer()
    }

    // MARK: - Playback

    private func playAudio(url: URL) {
        removePlayer()
        let item = AVPlayerItem(url: url)
        let newPlayer = AVPlayer(playerItem: item)
        newPlayer.defaultRate = Float(SpeechSettings.shared.speed)
        player = newPlayer
        observeEnd(item)
        newPlayer.play()
    }

    private func speakFallback(_ text: String, voiceID: Int32) {
        playingVoiceID = voiceID
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = AVSpeechSynthesisVoice(language: "en-US")
        let rate = Float(SpeechSettings.shared.speed)
        utterance.rate = min(
            AVSpeechUtteranceMaximumSpeechRate,
            max(AVSpeechUtteranceMinimumSpeechRate, AVSpeechUtteranceDefaultSpeechRate * rate)
        )
        let delegate = PreviewSynthDelegate { [weak self] in
            Task { @MainActor in
                guard let self, self.playingVoiceID == voiceID else { return }
                self.playingVoiceID = nil
            }
        }
        synthDelegate = delegate
        synthesizer.delegate = delegate
        synthesizer.speak(utterance)
    }

    private func observeEnd(_ item: AVPlayerItem) {
        removeEndObserver()
        endObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: item,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                self.playingVoiceID = nil
                self.removePlayer()
            }
        }
    }

    private func removePlayer() {
        player?.pause()
        removeEndObserver()
        player = nil
    }

    private func removeEndObserver() {
        if let endObserver {
            NotificationCenter.default.removeObserver(endObserver)
            self.endObserver = nil
        }
    }

    private func configureSession() {
        guard !sessionConfigured else { return }
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .spokenAudio)
            try session.setActive(true, options: [])
            sessionConfigured = true
        } catch {
            print("[VoicePreviewPlayer] session error: \(error)")
        }
    }

    deinit {
        if let endObserver {
            NotificationCenter.default.removeObserver(endObserver)
        }
    }
}

/// Minimal delegate that reports only when a fallback utterance stops sounding (finished or
/// cancelled), so the settings row can clear its speaker icon.
private final class PreviewSynthDelegate: NSObject, AVSpeechSynthesizerDelegate {
    private let onStop: () -> Void

    init(onStop: @escaping () -> Void) {
        self.onStop = onStop
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        onStop()
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        onStop()
    }
}

import Foundation
import AVFoundation
import Combine

/// One thing the player can play: a page of the Discover feed. That's either a clip
/// (recorded audio, or the answer text spoken aloud) or the question card that opens a
/// question (the prompt spoken aloud). Both go down the same path — audio when there's
/// a URL, speech when there isn't.
struct PlayerItem: Equatable {
    /// The page this item belongs to — what `finishedItemID` reports back to the feed.
    let id: UUID
    /// Identifies the *sound*, so re-entering the same page doesn't restart it.
    let dedupeKey: String
    /// Spoken via TTS when `audioURL` is nil.
    let text: String
    let audioURL: URL?
    let duration: TimeInterval
    let startTime: TimeInterval

    static func clip(_ clip: ArgumentClip, url: URL? = nil) -> PlayerItem {
        let audioURL = url ?? clip.audioURL
        return PlayerItem(
            id: clip.id,
            dedupeKey: audioURL?.absoluteString ?? "tts:answer:\(clip.answerId)",
            text: clip.answerText,
            audioURL: audioURL,
            duration: max(clip.duration, 1),
            startTime: clip.startTime
        )
    }

    /// The question read out loud — every question opens with this before any argument.
    static func question(_ question: Question) -> PlayerItem {
        let words = question.prompt.split { $0.isWhitespace || $0.isNewline }.count
        return PlayerItem(
            id: question.id,
            dedupeKey: "tts:question:\(question.id)",
            text: question.prompt,
            audioURL: nil,
            duration: max(4, Double(words) / 2.3),
            startTime: 0
        )
    }
}

/// Audition player for Discover pages — ported from keepMovin's ClipPreviewPlayer.
///
/// Text answers are spoken by **Kokoro-82M on-device** (`SpeechRenderer`), which renders
/// them to a WAV first. That's why there's no separate "TTS transport" here anymore:
/// synthesized speech is just an audio file, so it flows through the same `AVPlayer` path
/// as a recorded answer and gets a real duration, a real scrubber, and a real
/// end-of-playback signal. AVSpeechSynthesizer survives only as the fallback for when
/// Kokoro can't speak — the weights are still downloading, or the native backend isn't
/// linked. In that mode progress is the character-count estimate it always was.
///
/// Two product rules are enforced here rather than in the UI, so they can't be bypassed:
/// - **No forward seeking.** `seek(to:)` clamps to the current position, so the only way
///   forward is to listen. Skipping backward and re-listening is allowed.
/// - **Published state mirrors the engine.** `isPlaying` is read from AVPlayer's
///   `timeControlStatus` / AVSpeechSynthesizer's `isSpeaking`+`isPaused`, and `progress`
///   comes from the periodic time observer (audio) or the spoken character range (TTS).
///   Nothing here reports a state the engine isn't actually in.
@MainActor
final class ClipPreviewPlayer: ObservableObject {
    @Published private(set) var isPlaying = false
    @Published private(set) var progress: TimeInterval = 0
    @Published private(set) var duration: TimeInterval = 0
    @Published private(set) var bufferedProgress: TimeInterval = 0
    @Published private(set) var errorMessage: String?
    /// Kokoro is synthesizing this card and nothing is audible yet. The only state in which
    /// the transport is neither playing nor pausable — the UI shows a spinner.
    @Published private(set) var isPreparing = false
    /// True once the active item has been heard all the way through at least once.
    @Published private(set) var hasFullyHeardCurrent = false
    /// Id of the page that most recently played to its natural end. The feed keys its
    /// unlock off this rather than off `hasFullyHeardCurrent` + "whatever is on screen",
    /// so a page change mid-completion can't credit the wrong card.
    @Published private(set) var finishedItemID: UUID?

    private var player: AVPlayer?
    private var timeObserver: Any?
    private var itemStatusObserver: NSKeyValueObservation?
    private var timeControlObserver: NSKeyValueObservation?
    private var endObserver: NSObjectProtocol?
    private var current: PlayerItem?
    private var sessionConfigured = false
    private var didAttemptRecovery = false
    /// Intent, not display state: the user pressed pause, so re-entering the same card
    /// must not silently resume. Never used to decide what the controls show.
    private var pausedByUser = false

    // Fallback speech path (AVSpeechSynthesizer), used only when Kokoro can't speak.
    private let synthesizer = AVSpeechSynthesizer()
    private var ttsDelegate: TTSDelegate?
    private var isTTS = false
    /// The in-flight Kokoro render for the active card, cancelled when we move off it.
    private var renderTask: Task<Void, Never>?
    /// The full text being spoken. Progress is (characters spoken / characters total).
    private var ttsFullText = ""
    /// Where in `ttsFullText` the live utterance starts (non-zero after a backward seek).
    private var ttsUtteranceOffset = 0

    private var activeKey: String?
    private var preloaded: [String: AVPlayer] = [:]
    private var preloadOrder: [String] = []
    private let maxPreloaded = 3
    private let fullEpisodeForwardBuffer: TimeInterval = 60
    /// Treat within this many seconds of duration as "fully heard".
    private let completionSlop: TimeInterval = 0.6

    func play(_ item: PlayerItem) {
        if item.dedupeKey == activeKey, (player != nil || isTTS || isPreparing), errorMessage == nil {
            // Same card re-entered. Don't fight an explicit pause, and don't restart
            // something that already ran to the end — the user has to press play for that.
            guard !pausedByUser, !hasFullyHeardCurrent else { return }
            resumeCurrent()
            return
        }

        configureSession()
        stopPlayersOnly()

        self.current = item
        self.activeKey = item.dedupeKey
        self.errorMessage = nil
        self.didAttemptRecovery = false
        self.pausedByUser = false
        self.progress = item.startTime
        self.bufferedProgress = item.startTime
        self.hasFullyHeardCurrent = false
        self.finishedItemID = nil

        // Prefer real audio (segment file or original URL).
        if let audioURL = item.audioURL {
            isTTS = false
            ttsFullText = ""
            duration = item.duration
            startAudio(url: audioURL, start: item.startTime, key: item.dedupeKey)
            return
        }

        // Nothing recorded → speak the text. If Kokoro already rendered this answer, it's an
        // ordinary audio file and takes the path above, scrubber and all.
        if let spoken = SpeechRenderer.cachedURL(for: item.text) {
            startRenderedSpeech(at: spoken, key: item.dedupeKey, estimated: item.duration)
            return
        }

        // Kokoro can't speak yet (weights still downloading, or the backend isn't linked):
        // fall back rather than leave the feed silent.
        guard SpeechRenderer.isAvailable else {
            isTTS = true
            startTTS(fullText: item.text, from: 0, estimatedTotal: max(item.duration, 8))
            return
        }

        // Synthesize it, then play it as audio. `DiscoverView` renders the next few cards
        // ahead of time, so in a moving feed this branch is mostly the very first card.
        isTTS = false
        ttsFullText = ""
        duration = max(item.duration, 1)
        isPreparing = true
        syncPlaybackStateFromEngine()

        let key = item.dedupeKey
        let text = item.text
        let estimated = item.duration
        renderTask = Task { [weak self] in
            let rendered = await SpeechRenderer.shared.render(text)
            guard let self, !Task.isCancelled, self.activeKey == key else { return }
            self.isPreparing = false
            if let rendered {
                self.startRenderedSpeech(at: rendered, key: key, estimated: estimated)
            } else {
                // Synthesis failed — speak it rather than drop the card.
                self.isTTS = true
                self.startTTS(fullText: text, from: 0, estimatedTotal: max(estimated, 8))
            }
        }
    }

    /// Play a Kokoro-rendered WAV. `startTime` is deliberately 0: the render is the whole
    /// answer read from the top, not a segment of a longer recording.
    private func startRenderedSpeech(at url: URL, key: String, estimated: TimeInterval) {
        isTTS = false
        ttsFullText = ""
        isPreparing = false
        // A placeholder until AVPlayer reports the real length, which it does almost
        // immediately for a local file — after which the scrubber spans actual audio.
        duration = max(estimated, 1)
        startAudio(url: url, start: 0, key: key)
    }

    func preload(clip: ArgumentClip) {
        let item = PlayerItem.clip(clip)
        guard let audioURL = item.audioURL else { return }
        let k = item.dedupeKey
        guard k != activeKey, preloaded[k] == nil else { return }
        configureSession()
        let warm = AVPlayer(url: audioURL)
        warm.currentItem?.preferredForwardBufferDuration = fullEpisodeForwardBuffer
        warm.seek(to: CMTime(seconds: item.startTime, preferredTimescale: 600))
        preloaded[k] = warm
        preloadOrder.append(k)
        while preloadOrder.count > maxPreloaded {
            let oldest = preloadOrder.removeFirst()
            preloaded[oldest]?.pause()
            preloaded.removeValue(forKey: oldest)
        }
    }

    func togglePlayPause() {
        if errorMessage != nil, let current {
            errorMessage = nil
            didAttemptRecovery = false
            // Start over rather than resume: a player that failed has nothing to resume.
            activeKey = nil
            play(current)
            return
        }

        if isTTS {
            togglePlayPauseTTS()
            return
        }

        guard let player else { return }
        if player.timeControlStatus == .paused {
            pausedByUser = false
            if hasFullyHeardCurrent, duration > 0, progress >= duration - completionSlop {
                // Finished clip: restart from the top so play is meaningful again.
                player.seek(to: .zero) { [weak self, weak player] _ in
                    Task { @MainActor in
                        player?.play()
                        self?.progress = 0
                        self?.syncPlaybackStateFromEngine()
                    }
                }
            } else {
                player.play()
            }
        } else {
            pausedByUser = true
            player.pause()
        }
        syncPlaybackStateFromEngine()
    }

    private func togglePlayPauseTTS() {
        if synthesizer.isSpeaking, !synthesizer.isPaused {
            pausedByUser = true
            synthesizer.pauseSpeaking(at: .word)
            return
        }
        if synthesizer.isPaused {
            pausedByUser = false
            synthesizer.continueSpeaking()
            return
        }
        // Not speaking: either finished or never started.
        guard let current else { return }
        pausedByUser = false
        let restart = hasFullyHeardCurrent || progress >= duration - completionSlop
        let offset = restart ? 0 : ttsOffset(forSeconds: progress)
        startTTS(fullText: current.text, from: offset, estimatedTotal: max(duration, 8))
    }

    /// Seek — **backward only**. The clamp to `progress` is what makes forward skipping
    /// impossible: the scrubber is a read-only indicator and this is the only seek path.
    func seek(to seconds: TimeInterval) {
        let clamped = min(max(0, seconds), progress)

        if isTTS {
            guard !ttsFullText.isEmpty else { return }
            // TTS can't be scrubbed, so re-speak from the word boundary at that point.
            // That necessarily resumes playback; `isPlaying` will say so truthfully.
            pausedByUser = false
            startTTS(fullText: ttsFullText, from: ttsOffset(forSeconds: clamped), estimatedTotal: duration)
            return
        }

        progress = clamped
        player?.seek(to: CMTime(seconds: clamped, preferredTimescale: 600))
    }

    func skipBackward(_ seconds: TimeInterval = 15) { seek(to: progress - seconds) }

    func stop() {
        stopPlayersOnly()
        current = nil
        activeKey = nil
        progress = 0
        bufferedProgress = 0
        duration = 0
        errorMessage = nil
        isPlaying = false
        pausedByUser = false
        isTTS = false
        isPreparing = false
        ttsFullText = ""
        ttsUtteranceOffset = 0
        hasFullyHeardCurrent = false
        finishedItemID = nil
    }

    func teardownAll() {
        stop()
        for k in preloadOrder { preloaded[k]?.pause() }
        preloaded.removeAll()
        preloadOrder.removeAll()
    }

    // MARK: - Audio

    private func startAudio(url: URL, start: TimeInterval, key k: String) {
        if let warm = preloaded.removeValue(forKey: k) {
            preloadOrder.removeAll { $0 == k }
            if warm.currentItem?.status != .failed {
                player = warm
                observeItem(warm.currentItem)
                observeTimeControl(warm)
                observePlaybackEnd(warm.currentItem)
                warm.play()
                addObserver()
                syncPlaybackStateFromEngine()
                return
            }
        }

        let item = AVPlayerItem(url: url)
        item.preferredForwardBufferDuration = fullEpisodeForwardBuffer
        let newPlayer = AVPlayer(playerItem: item)
        newPlayer.automaticallyWaitsToMinimizeStalling = true
        player = newPlayer
        observeItem(item)
        observeTimeControl(newPlayer)
        observePlaybackEnd(item)
        newPlayer.seek(to: CMTime(seconds: start, preferredTimescale: 600)) { [weak self, weak newPlayer] _ in
            Task { @MainActor in
                newPlayer?.play()
                self?.syncPlaybackStateFromEngine()
            }
        }
        addObserver()
        syncPlaybackStateFromEngine()
    }

    private func resumeCurrent() {
        // Synthesis is still running for this card; it will start playback when it lands.
        if isPreparing { return }
        if isTTS {
            if synthesizer.isPaused {
                synthesizer.continueSpeaking()
            } else if !synthesizer.isSpeaking, let current {
                startTTS(fullText: current.text, from: ttsUtteranceOffset, estimatedTotal: max(duration, 8))
            }
            return
        }
        player?.play()
        syncPlaybackStateFromEngine()
    }

    private func stopPlayersOnly() {
        // Abandon any synthesis for the outgoing card. The render itself is cached by
        // SpeechRenderer if it completes anyway, so nothing is wasted — this just stops it
        // from calling back and playing over whatever is now on screen.
        renderTask?.cancel()
        renderTask = nil
        isPreparing = false

        player?.pause()
        teardownObserver()
        teardownItemObserver()
        teardownTimeControlObserver()
        teardownEndObserver()
        player = nil
        // Drop the delegate first: stopSpeaking fires didCancel, and we don't want the
        // outgoing clip's callbacks writing state for the incoming one.
        synthesizer.delegate = nil
        ttsDelegate = nil
        synthesizer.stopSpeaking(at: .immediate)
        isPlaying = false
    }

    private func addObserver() {
        let interval = CMTime(seconds: 0.25, preferredTimescale: 600)
        timeObserver = player?.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] time in
            Task { @MainActor in
                guard let self else { return }
                let seconds = time.seconds
                if let itemDuration = self.player?.currentItem?.duration.seconds,
                   itemDuration.isFinite, itemDuration > 0 {
                    self.duration = itemDuration
                }
                guard seconds.isFinite else { return }
                self.progress = min(max(seconds, 0), self.duration)
                self.bufferedProgress = self.loadedSeconds()
                self.markFullyHeardIfNeeded()
                self.syncPlaybackStateFromEngine()
            }
        }
    }

    /// The single source of truth for `isPlaying`: whatever the engine is actually doing.
    private func syncPlaybackStateFromEngine() {
        if isTTS {
            isPlaying = synthesizer.isSpeaking && !synthesizer.isPaused
            return
        }
        guard let player else {
            isPlaying = false
            return
        }
        // `.waitingToPlayAtSpecifiedRate` is a stall inside a play intent — the transport
        // is live, so the button stays on "pause" rather than flicking back to "play".
        isPlaying = player.timeControlStatus != .paused
    }

    private func markFullyHeardIfNeeded() {
        guard duration > 0, progress >= duration - completionSlop else { return }
        markFullyHeard()
    }

    private func markFullyHeard() {
        hasFullyHeardCurrent = true
        finishedItemID = current?.id
    }

    private func loadedSeconds() -> TimeInterval {
        guard let item = player?.currentItem else { return progress }
        let now = item.currentTime().seconds
        var loadedEnd = now
        for value in item.loadedTimeRanges {
            let range = value.timeRangeValue
            let start = range.start.seconds
            let end = range.end.seconds
            guard start.isFinite, end.isFinite else { continue }
            if now >= start - 1, now <= end + 1 {
                loadedEnd = max(loadedEnd, end)
            }
        }
        return min(max(loadedEnd, progress), duration)
    }

    private func teardownObserver() {
        if let timeObserver {
            player?.removeTimeObserver(timeObserver)
            self.timeObserver = nil
        }
    }

    private func observeItem(_ item: AVPlayerItem?) {
        teardownItemObserver()
        guard let item else { return }
        itemStatusObserver = item.observe(\.status, options: [.new]) { [weak self] observed, _ in
            Task { @MainActor in
                self?.handleItemStatus(observed)
            }
        }
        if item.status == .failed {
            handleItemStatus(item)
        }
    }

    private func observeTimeControl(_ player: AVPlayer) {
        teardownTimeControlObserver()
        timeControlObserver = player.observe(\.timeControlStatus, options: [.new, .initial]) { [weak self] _, _ in
            Task { @MainActor in
                self?.syncPlaybackStateFromEngine()
            }
        }
    }

    private func observePlaybackEnd(_ item: AVPlayerItem?) {
        teardownEndObserver()
        guard let item else { return }
        endObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: item,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                self.progress = self.duration
                self.markFullyHeard()
                self.syncPlaybackStateFromEngine()
            }
        }
    }

    private func teardownItemObserver() {
        itemStatusObserver?.invalidate()
        itemStatusObserver = nil
    }

    private func teardownTimeControlObserver() {
        timeControlObserver?.invalidate()
        timeControlObserver = nil
    }

    private func teardownEndObserver() {
        if let endObserver {
            NotificationCenter.default.removeObserver(endObserver)
            self.endObserver = nil
        }
    }

    private func handleItemStatus(_ item: AVPlayerItem) {
        guard item === player?.currentItem else { return }
        switch item.status {
        case .readyToPlay:
            errorMessage = nil
            let itemDuration = item.duration.seconds
            if itemDuration.isFinite, itemDuration > 0 {
                duration = itemDuration
            }
            syncPlaybackStateFromEngine()
        case .failed:
            if !didAttemptRecovery, let current, let url = current.audioURL {
                didAttemptRecovery = true
                teardownObserver()
                teardownEndObserver()
                startAudio(url: url, start: max(progress, current.startTime), key: current.dedupeKey)
            } else if !didAttemptRecovery, let current, current.audioURL == nil {
                // A rendered WAV that won't open — bin it so it gets synthesized again, and
                // speak the answer rather than dead-ending the card on an error.
                didAttemptRecovery = true
                teardownObserver()
                teardownEndObserver()
                player = nil
                SpeechRenderer.discardRender(for: current.text)
                isTTS = true
                startTTS(fullText: current.text, from: 0, estimatedTotal: max(current.duration, 8))
            } else {
                errorMessage = "Couldn't play this clip. Tap play to retry."
                syncPlaybackStateFromEngine()
            }
        default:
            break
        }
    }

    // MARK: - TTS

    /// Speak `fullText` starting at UTF-16 offset `from`. Progress is reported as the
    /// fraction of `fullText` the synthesizer has actually spoken, so the bar tracks real
    /// speech instead of a wall clock that drifts from it.
    private func startTTS(fullText: String, from offset: Int, estimatedTotal: TimeInterval) {
        synthesizer.delegate = nil
        ttsDelegate = nil
        synthesizer.stopSpeaking(at: .immediate)

        let text = fullText as NSString
        ttsFullText = fullText
        ttsUtteranceOffset = min(max(0, offset), text.length)
        duration = max(estimatedTotal, 1)
        progress = ttsProgress(spokenCharacters: ttsUtteranceOffset)
        // Speech is synthesized locally — there's nothing to buffer.
        bufferedProgress = duration

        let remaining = text.substring(from: ttsUtteranceOffset)
        guard !remaining.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            markFullyHeard()
            syncPlaybackStateFromEngine()
            return
        }

        let utterance = AVSpeechUtterance(string: remaining)
        utterance.voice = AVSpeechSynthesisVoice(language: "en-US")
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate

        let delegate = TTSDelegate(
            onWillSpeakRange: { [weak self] range in
                Task { @MainActor in
                    guard let self else { return }
                    self.progress = self.ttsProgress(
                        spokenCharacters: self.ttsUtteranceOffset + range.location + range.length
                    )
                    self.syncPlaybackStateFromEngine()
                }
            },
            onFinish: { [weak self] in
                Task { @MainActor in
                    guard let self else { return }
                    self.progress = self.duration
                    self.markFullyHeard()
                    self.syncPlaybackStateFromEngine()
                }
            },
            onStateChange: { [weak self] in
                Task { @MainActor in self?.syncPlaybackStateFromEngine() }
            }
        )
        ttsDelegate = delegate
        synthesizer.delegate = delegate
        synthesizer.speak(utterance)
        syncPlaybackStateFromEngine()
    }

    /// Position on the bar for a count of characters spoken out of the whole answer.
    private func ttsProgress(spokenCharacters chars: Int) -> TimeInterval {
        let total = (ttsFullText as NSString).length
        guard total > 0, duration > 0 else { return 0 }
        let fraction = min(max(Double(chars) / Double(total), 0), 1)
        return fraction * duration
    }

    /// The inverse: the word-aligned UTF-16 offset into the answer for a point on the bar.
    private func ttsOffset(forSeconds seconds: TimeInterval) -> Int {
        let text = ttsFullText as NSString
        guard text.length > 0, duration > 0 else { return 0 }
        let fraction = min(max(seconds / duration, 0), 1)
        let raw = min(Int(fraction * Double(text.length)), text.length)
        guard raw > 0 else { return 0 }
        // Snap back to the start of the word containing `raw` — mid-word is unspeakable.
        let preceding = text.rangeOfCharacter(
            from: .whitespacesAndNewlines,
            options: .backwards,
            range: NSRange(location: 0, length: raw)
        )
        guard preceding.location != NSNotFound else { return 0 }
        return min(preceding.location + preceding.length, text.length)
    }

    private func configureSession() {
        guard !sessionConfigured else { return }
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .spokenAudio)
            try session.setActive(true, options: [])
            sessionConfigured = true
        } catch {
            print("[ClipPreviewPlayer] session error: \(error)")
        }
    }

    deinit {
        if let timeObserver {
            player?.removeTimeObserver(timeObserver)
        }
        itemStatusObserver?.invalidate()
        timeControlObserver?.invalidate()
        if let endObserver {
            NotificationCenter.default.removeObserver(endObserver)
        }
    }
}

/// Thin NSObject bridge for AVSpeechSynthesizerDelegate.
private final class TTSDelegate: NSObject, AVSpeechSynthesizerDelegate {
    let onWillSpeakRange: (NSRange) -> Void
    let onFinish: () -> Void
    /// Fired for start / pause / continue / cancel — the player re-reads the synthesizer
    /// rather than being told what state to be in.
    let onStateChange: () -> Void

    init(
        onWillSpeakRange: @escaping (NSRange) -> Void,
        onFinish: @escaping () -> Void,
        onStateChange: @escaping () -> Void
    ) {
        self.onWillSpeakRange = onWillSpeakRange
        self.onFinish = onFinish
        self.onStateChange = onStateChange
    }

    func speechSynthesizer(
        _ synthesizer: AVSpeechSynthesizer,
        willSpeakRangeOfSpeechString characterRange: NSRange,
        utterance: AVSpeechUtterance
    ) {
        onWillSpeakRange(characterRange)
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didStart utterance: AVSpeechUtterance) {
        onStateChange()
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        onFinish()
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        onStateChange()
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didPause utterance: AVSpeechUtterance) {
        onStateChange()
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didContinue utterance: AVSpeechUtterance) {
        onStateChange()
    }
}

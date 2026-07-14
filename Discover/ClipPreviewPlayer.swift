import Foundation
import AVFoundation
import Combine

/// Audition player for Discover cards — ported from keepMovin's ClipPreviewPlayer.
/// Plays file/remote audio, or speaks text answers via AVSpeechSynthesizer when no audio URL.
///
/// Progress is one-way for product rules: you can re-listen / seek backward, but never
/// jump past the farthest point already heard (`farthestProgress`).
@MainActor
final class ClipPreviewPlayer: ObservableObject {
    @Published var isPlaying = false
    @Published var progress: TimeInterval = 0
    /// Furthest position reached by natural playback (not seeks). Scrubbing is capped here.
    @Published var farthestProgress: TimeInterval = 0
    @Published var duration: TimeInterval = 0
    @Published var bufferedProgress: TimeInterval = 0
    @Published var errorMessage: String?
    /// True once the active clip has been heard all the way through at least once.
    @Published var hasFullyHeardCurrent = false

    private var player: AVPlayer?
    private var timeObserver: Any?
    private var itemStatusObserver: NSKeyValueObservation?
    private var timeControlObserver: NSKeyValueObservation?
    private var endObserver: NSObjectProtocol?
    private var clip: ArgumentClip?
    private var sessionConfigured = false
    private var userPaused = false
    private var didAttemptRecovery = false

    // TTS path
    private let synthesizer = AVSpeechSynthesizer()
    private var ttsDelegate: TTSDelegate?
    private var isTTS = false
    private var ttsTimer: Timer?
    private var ttsStartDate: Date?
    private var ttsEstimatedDuration: TimeInterval = 0

    private struct ClipKey: Hashable {
        let answerId: UUID
        let url: String
    }

    private var activeKey: ClipKey?
    private var preloaded: [ClipKey: AVPlayer] = [:]
    private var preloadOrder: [ClipKey] = []
    private let maxPreloaded = 3
    private let fullEpisodeForwardBuffer: TimeInterval = 60
    /// Treat within this many seconds of duration as "fully heard".
    private let completionSlop: TimeInterval = 0.6

    private func key(for clip: ArgumentClip) -> ClipKey {
        ClipKey(answerId: clip.answerId, url: clip.audioURL?.absoluteString ?? "tts:\(clip.answerId)")
    }

    func play(clip: ArgumentClip, url: URL? = nil) {
        let k = key(for: clip)

        if k == activeKey, (player != nil || isTTS), errorMessage == nil {
            guard !userPaused else { return }
            resumeCurrent()
            return
        }

        configureSession()
        stopPlayersOnly()

        self.clip = clip
        self.activeKey = k
        self.errorMessage = nil
        self.didAttemptRecovery = false
        self.userPaused = false
        self.progress = clip.startTime
        self.farthestProgress = clip.startTime
        self.bufferedProgress = clip.startTime
        self.hasFullyHeardCurrent = false

        // Prefer real audio (segment file or original URL).
        let playURL = url ?? clip.audioURL
        if let playURL {
            isTTS = false
            duration = max(clip.duration, 1)
            startAudio(url: playURL, start: clip.startTime, key: k)
            return
        }

        // Text-only answer → speak it.
        isTTS = true
        startTTS(text: clip.answerText, estimated: max(clip.duration, 8))
    }

    func preload(clip: ArgumentClip) {
        guard let audioURL = clip.audioURL else { return }
        let k = key(for: clip)
        guard k != activeKey, preloaded[k] == nil else { return }
        configureSession()
        let warm = AVPlayer(url: audioURL)
        warm.currentItem?.preferredForwardBufferDuration = fullEpisodeForwardBuffer
        warm.seek(to: CMTime(seconds: clip.startTime, preferredTimescale: 600))
        preloaded[k] = warm
        preloadOrder.append(k)
        while preloadOrder.count > maxPreloaded {
            let oldest = preloadOrder.removeFirst()
            preloaded[oldest]?.pause()
            preloaded.removeValue(forKey: oldest)
        }
    }

    func togglePlayPause() {
        if errorMessage != nil, let clip {
            errorMessage = nil
            didAttemptRecovery = false
            play(clip: clip, url: clip.audioURL)
            return
        }

        if isTTS {
            if synthesizer.isSpeaking && !synthesizer.isPaused {
                synthesizer.pauseSpeaking(at: .word)
                isPlaying = false
                userPaused = true
                pauseTTSTimer()
            } else if synthesizer.isPaused {
                synthesizer.continueSpeaking()
                isPlaying = true
                userPaused = false
                resumeTTSTimer()
            } else if let clip {
                // Finished or not started — restart from beginning (or resume progress via remaining text).
                if hasFullyHeardCurrent || progress >= duration - completionSlop {
                    startTTS(text: clip.answerText, estimated: max(duration, 8))
                } else if progress > 0.5 {
                    seek(to: progress)
                } else {
                    startTTS(text: clip.answerText, estimated: max(duration, 8))
                }
            }
            return
        }

        guard let player else { return }
        // Prefer actual AVPlayer rate over our published flag so the button stays honest.
        let actuallyPlaying = player.rate > 0.01 || player.timeControlStatus == .playing
        if actuallyPlaying || isPlaying {
            player.pause()
            isPlaying = false
            userPaused = true
        } else {
            userPaused = false
            // Finished clip: restart from the beginning so play is meaningful again.
            if hasFullyHeardCurrent, duration > 0, progress >= duration - completionSlop {
                player.seek(to: .zero) { [weak player] _ in
                    Task { @MainActor in
                        player?.play()
                        self.progress = 0
                        self.isPlaying = true
                    }
                }
            } else {
                player.play()
                isPlaying = true
            }
        }
    }

    /// Seek, clamped so you cannot jump past content not yet heard.
    func seek(to seconds: TimeInterval) {
        let upper = max(farthestProgress, 0)
        let clamped = min(max(0, seconds), min(upper, max(duration, 1)))
        progress = clamped
        if isTTS {
            guard let clip else { return }
            let words = clip.answerText.split(whereSeparator: { $0.isWhitespace || $0.isNewline })
            let fraction = duration > 0 ? clamped / duration : 0
            let startWord = min(Int(Double(words.count) * fraction), max(words.count - 1, 0))
            let remaining = words.dropFirst(startWord).joined(separator: " ")
            startTTS(text: remaining, estimated: max(duration - clamped, 4), progressOffset: clamped)
            return
        }
        player?.seek(to: CMTime(seconds: clamped, preferredTimescale: 600))
    }

    func skipBackward(_ seconds: TimeInterval = 15) { seek(to: progress - seconds) }

    func stop() {
        stopPlayersOnly()
        clip = nil
        activeKey = nil
        progress = 0
        farthestProgress = 0
        bufferedProgress = 0
        duration = 0
        errorMessage = nil
        isPlaying = false
        userPaused = false
        isTTS = false
        hasFullyHeardCurrent = false
    }

    func teardownAll() {
        stop()
        for k in preloadOrder { preloaded[k]?.pause() }
        preloaded.removeAll()
        preloadOrder.removeAll()
    }

    // MARK: - Audio

    private func startAudio(url: URL, start: TimeInterval, key k: ClipKey) {
        if let warm = preloaded.removeValue(forKey: k) {
            preloadOrder.removeAll { $0 == k }
            if warm.currentItem?.status != .failed {
                player = warm
                observeItem(warm.currentItem)
                observeTimeControl(warm)
                observePlaybackEnd(warm.currentItem)
                warm.play()
                syncPlayingFromPlayer()
                addObserver()
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
        newPlayer.seek(to: CMTime(seconds: start, preferredTimescale: 600)) { [weak newPlayer] _ in
            Task { @MainActor in
                newPlayer?.play()
                self.syncPlayingFromPlayer()
            }
        }
        // Optimistic until rate observer fires; still better than staying on "play".
        isPlaying = true
        addObserver()
    }

    private func resumeCurrent() {
        if isTTS {
            if synthesizer.isPaused {
                synthesizer.continueSpeaking()
                resumeTTSTimer()
            } else if !synthesizer.isSpeaking, let clip {
                startTTS(text: clip.answerText, estimated: max(duration, 8))
            }
            isPlaying = true
            return
        }
        player?.play()
        isPlaying = true
    }

    private func stopPlayersOnly() {
        player?.pause()
        teardownObserver()
        teardownItemObserver()
        teardownTimeControlObserver()
        teardownEndObserver()
        player = nil
        synthesizer.stopSpeaking(at: .immediate)
        ttsTimer?.invalidate()
        ttsTimer = nil
        ttsDelegate = nil
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
                self.progress = min(max(seconds, 0), self.duration)
                if seconds > self.farthestProgress {
                    self.farthestProgress = min(seconds, self.duration)
                }
                self.bufferedProgress = self.loadedSeconds()
                self.markFullyHeardIfNeeded()
                self.syncPlayingFromPlayer()
            }
        }
    }

    private func syncPlayingFromPlayer() {
        guard !isTTS, let player else { return }
        // Don't fight an explicit user pause, but clear "playing" when the engine stops.
        let ratePlaying = player.rate > 0.01
        let waiting = player.timeControlStatus == .waitingToPlayAtSpecifiedRate
        let enginePlaying = ratePlaying || waiting
        if userPaused {
            isPlaying = false
        } else {
            isPlaying = enginePlaying
        }
    }

    private func markFullyHeardIfNeeded() {
        guard duration > 0, farthestProgress >= duration - completionSlop else { return }
        hasFullyHeardCurrent = true
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
                self?.syncPlayingFromPlayer()
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
                self.isPlaying = false
                self.userPaused = true
                self.progress = self.duration
                self.farthestProgress = self.duration
                self.hasFullyHeardCurrent = true
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
            syncPlayingFromPlayer()
        case .failed:
            if !didAttemptRecovery, let clip, let url = clip.audioURL {
                didAttemptRecovery = true
                teardownObserver()
                teardownEndObserver()
                startAudio(url: url, start: max(progress, clip.startTime), key: key(for: clip))
            } else {
                isPlaying = false
                errorMessage = "Couldn't play this clip. Tap play to retry."
            }
        default:
            break
        }
    }

    // MARK: - TTS

    private func startTTS(text: String, estimated: TimeInterval, progressOffset: TimeInterval = 0) {
        synthesizer.stopSpeaking(at: .immediate)
        ttsTimer?.invalidate()

        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = AVSpeechSynthesisVoice(language: "en-US")
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate

        // Keep overall duration stable when seeking mid-utterance.
        if progressOffset <= 0 {
            duration = estimated
        } else {
            duration = max(duration, estimated + progressOffset)
        }
        progress = progressOffset
        // farthestProgress only moves forward with real listening; don't reduce on seek-back restart.
        farthestProgress = max(farthestProgress, progressOffset)
        bufferedProgress = duration
        ttsEstimatedDuration = estimated
        ttsStartDate = Date()
        userPaused = false

        let delegate = TTSDelegate(
            onFinish: { [weak self] in
                Task { @MainActor in
                    self?.isPlaying = false
                    self?.userPaused = true
                    self?.progress = self?.duration ?? 0
                    self?.farthestProgress = self?.duration ?? 0
                    self?.hasFullyHeardCurrent = true
                    self?.ttsTimer?.invalidate()
                }
            },
            onCancel: { [weak self] in
                Task { @MainActor in
                    self?.isPlaying = false
                    self?.ttsTimer?.invalidate()
                }
            },
            onPause: { [weak self] in
                Task { @MainActor in
                    self?.isPlaying = false
                }
            },
            onContinue: { [weak self] in
                Task { @MainActor in
                    self?.isPlaying = true
                }
            }
        )
        ttsDelegate = delegate
        synthesizer.delegate = delegate
        synthesizer.speak(utterance)
        isPlaying = true
        resumeTTSTimer()
    }

    private func resumeTTSTimer() {
        ttsTimer?.invalidate()
        ttsStartDate = Date().addingTimeInterval(-progress)
        ttsTimer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self, self.isPlaying, let start = self.ttsStartDate else { return }
                let elapsed = Date().timeIntervalSince(start)
                self.progress = min(elapsed, self.duration)
                if self.progress > self.farthestProgress {
                    self.farthestProgress = self.progress
                }
                self.markFullyHeardIfNeeded()
            }
        }
    }

    private func pauseTTSTimer() {
        ttsTimer?.invalidate()
        ttsTimer = nil
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
    let onFinish: () -> Void
    let onCancel: () -> Void
    let onPause: () -> Void
    let onContinue: () -> Void

    init(
        onFinish: @escaping () -> Void,
        onCancel: @escaping () -> Void,
        onPause: @escaping () -> Void = {},
        onContinue: @escaping () -> Void = {}
    ) {
        self.onFinish = onFinish
        self.onCancel = onCancel
        self.onPause = onPause
        self.onContinue = onContinue
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        onFinish()
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        onCancel()
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didPause utterance: AVSpeechUtterance) {
        onPause()
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didContinue utterance: AVSpeechUtterance) {
        onContinue()
    }
}

import SwiftUI

/// The player chrome for one page of the Discover feed: **what is being said**, over the
/// video it's said on.
///
/// There is no artwork and no title. An argument has neither — it's a person talking, so
/// the page shows the transcript of what they said and plays it. There are no transport
/// buttons either: the whole page is the control (a single tap toggles play/pause, a double
/// tap skips back — see `playbackTapControls`), so this view is just the transcript, a
/// read-only position bar, and — while a neural voice is synthesizing — a "warming up" note.
/// The position bar never seeks: the only way forward is to listen (see `ClipPreviewPlayer.seek`).
struct NowPlayingContent: View {
    /// What's being said on this page — shown while it plays.
    let transcript: String
    let currentTime: TimeInterval
    let duration: TimeInterval
    var bufferedTime: TimeInterval? = nil
    /// A neural voice is still synthesizing this card and nothing is audible yet — shown as a
    /// "warming up" note so a tap that can't play anything yet doesn't read as broken.
    var isLoading: Bool = false
    var errorMessage: String? = nil
    var accent: Color = SteelmanTheme.accent
    var badge: String? = nil
    var badgeColor: Color = .secondary

    var body: some View {
        VStack(spacing: 24) {
            if let badge {
                Text(badge)
                    .font(.caption.weight(.bold))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(badgeColor.opacity(0.92), in: Capsule())
                    .foregroundStyle(.white)
            }

            transcriptView

            if isLoading { preparingNote }

            progress

            if let errorMessage {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill")
                    Text(errorMessage)
                        .multilineTextAlignment(.center)
                }
                .font(.footnote)
                .foregroundColor(.red)
                .padding(.horizontal)
            }
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// The page is a fixed height and doesn't scroll — swiping is how you change pages —
    /// so a long answer shrinks to fit rather than opening a competing scroll gesture.
    private var transcriptView: some View {
        Text(transcript)
            .font(.system(.title3, design: .serif))
            .lineSpacing(6)
            .multilineTextAlignment(.leading)
            .minimumScaleFactor(0.5)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            .padding(.horizontal, 8)
    }

    /// The only status the page shows in place of the old transport: the neural voice is
    /// still rendering this card. Play/pause and skip-back are gestures now, not buttons.
    private var preparingNote: some View {
        HStack(spacing: 8) {
            ProgressView()
            Text("Warming up the voice")
        }
        .font(.subheadline.weight(.semibold))
        .foregroundStyle(.secondary)
    }

    private var progress: some View {
        VStack(spacing: 8) {
            PlaybackIndicator(
                currentTime: currentTime,
                duration: duration,
                bufferedTime: bufferedTime,
                accent: accent
            )
            .padding(.horizontal)

            HStack {
                Text(formatTime(currentTime))
                    .font(.caption)
                    .foregroundColor(.secondary)
                Spacer()
                Text(formatTime(duration))
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal)
        }
    }

    private func formatTime(_ time: TimeInterval) -> String {
        guard time.isFinite, time >= 0 else { return "0:00" }
        let hours = Int(time) / 3600
        let minutes = (Int(time) % 3600) / 60
        let seconds = Int(time) % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        }
        return String(format: "%d:%02d", minutes, seconds)
    }
}

/// Read-only playback position bar: no thumb, no gesture, no seeking. This is what
/// Discover shows — the bar reports where playback is, it isn't a control.
struct PlaybackIndicator: View {
    let currentTime: TimeInterval
    let duration: TimeInterval
    var bufferedTime: TimeInterval? = nil
    var accent: Color = SteelmanTheme.accent

    private let trackHeight: CGFloat = 4

    var body: some View {
        GeometryReader { geo in
            let width = max(geo.size.width, 1)
            let total = max(duration, 1)
            let played = min(max(currentTime / total, 0), 1)
            let buffered = min(max((bufferedTime ?? currentTime) / total, played), 1)

            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.secondary.opacity(0.2))
                Capsule()
                    .fill(accent.opacity(0.35))
                    .frame(width: width * buffered)
                Capsule()
                    .fill(accent)
                    .frame(width: width * played)
            }
            .frame(height: trackHeight)
            .frame(maxHeight: .infinity, alignment: .center)
            .animation(.linear(duration: 0.2), value: played)
        }
        .frame(height: trackHeight)
        .allowsHitTesting(false)
        .accessibilityElement()
        .accessibilityLabel("Playback progress")
    }
}

// MARK: - Tap-to-play transport

/// The brief indicator a tap flashes in the centre of a page — the TikTok-style feedback
/// that replaces the on-screen play/skip buttons. It shows the state the tap moved *to*.
private enum PlaybackFlash: Equatable {
    /// The tap started playback.
    case playing
    /// The tap paused playback.
    case paused
    /// A double tap skipped back 15 seconds.
    case skippedBack

    var systemImage: String {
        switch self {
        case .playing: return "play.fill"
        case .paused: return "pause.fill"
        case .skippedBack: return "gobackward.15"
        }
    }

    var accessibilityLabel: String {
        switch self {
        case .playing: return "Playing"
        case .paused: return "Paused"
        case .skippedBack: return "Skipped back 15 seconds"
        }
    }
}

/// Turns a whole page into its own transport. There are no play or skip-back buttons to aim
/// at: a **single tap** anywhere toggles play/pause, a **double tap** skips back 15 seconds,
/// and each flashes a `PlaybackFlash` in the centre that fades on its own after a beat —
/// the way TikTok and its kin surface a control just long enough to see it, then get out of
/// the way. Only the on-screen (current) page reacts.
private struct PlaybackTapControls: ViewModifier {
    let isCurrent: Bool
    /// Playback state *before* the tap, so the toggle can flash the state it moves to.
    let isPlaying: Bool
    let onToggle: () -> Void
    let onSkipBackward: () -> Void

    @State private var flash: PlaybackFlash?
    @State private var flashDismiss: Task<Void, Never>?

    func body(content: Content) -> some View {
        content
            .contentShape(Rectangle())
            // The double tap is declared first so SwiftUI waits to tell it apart from a single
            // tap before firing the toggle — the same disambiguation TikTok's like-vs-pause uses.
            .onTapGesture(count: 2) {
                guard isCurrent else { return }
                onSkipBackward()
                showFlash(.skippedBack)
            }
            .onTapGesture {
                guard isCurrent else { return }
                onToggle()
                showFlash(isPlaying ? .paused : .playing)
            }
            .overlay { flashView }
    }

    @ViewBuilder
    private var flashView: some View {
        if let flash {
            Image(systemName: flash.systemImage)
                .font(.system(size: 60, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 120, height: 120)
                .background(.ultraThinMaterial, in: Circle())
                .shadow(radius: 12)
                .transition(.scale(scale: 0.7).combined(with: .opacity))
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
    }

    /// Show `kind` now and schedule it to fade out on its own. A fresh tap supersedes the
    /// pending fade, so rapid taps don't leave a stale icon on screen or stack timers.
    private func showFlash(_ kind: PlaybackFlash) {
        flashDismiss?.cancel()
        withAnimation(.snappy(duration: 0.18)) { flash = kind }
        flashDismiss = Task {
            try? await Task.sleep(for: .seconds(0.8))
            guard !Task.isCancelled else { return }
            withAnimation(.easeOut(duration: 0.45)) { flash = nil }
        }
    }
}

extension View {
    /// Drive playback by tapping the page itself: single tap toggles play/pause, double tap
    /// skips back 15 seconds, each with a brief centre flash. See `PlaybackTapControls`.
    func playbackTapControls(
        isCurrent: Bool,
        isPlaying: Bool,
        onToggle: @escaping () -> Void,
        onSkipBackward: @escaping () -> Void
    ) -> some View {
        modifier(PlaybackTapControls(
            isCurrent: isCurrent,
            isPlaying: isPlaying,
            onToggle: onToggle,
            onSkipBackward: onSkipBackward
        ))
    }
}

import SwiftUI

/// The player chrome for one page of the Discover feed: **what is being said**, and the
/// controls to hear it.
///
/// There is no artwork and no title. An argument has neither — it's a person talking, so
/// the page shows the transcript of what they said and plays it. The position bar is a
/// read-only indicator: the only way forward is to listen (see `ClipPreviewPlayer.seek`).
struct NowPlayingContent: View {
    /// What's being said on this page — shown while it plays.
    let transcript: String
    let currentTime: TimeInterval
    let duration: TimeInterval
    var bufferedTime: TimeInterval? = nil
    let isPlaying: Bool
    var isLoading: Bool = false
    var showSkipBackward: Bool = true
    let onSkipBackward: () -> Void
    let onTogglePlayPause: () -> Void
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

            transport

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

    private var transport: some View {
        HStack(spacing: 60) {
            if showSkipBackward {
                Button(action: onSkipBackward) {
                    Image(systemName: "gobackward.15")
                        .font(.system(size: 32))
                }
                .accessibilityLabel("Skip back 15 seconds")
            } else {
                Color.clear.frame(width: 32, height: 32)
            }

            Button(action: onTogglePlayPause) {
                if isLoading {
                    ProgressView()
                        .frame(width: 70, height: 70)
                } else {
                    Image(systemName: isPlaying ? "pause.circle.fill" : "play.circle.fill")
                        .font(.system(size: 70))
                }
            }
            .accessibilityLabel(isPlaying ? "Pause" : "Play")

            // There is deliberately no skip-forward: the only way forward is to listen.
            // The spacer keeps play centered against the skip-back button.
            Color.clear.frame(width: 32, height: 32)
        }
        .foregroundStyle(accent)
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

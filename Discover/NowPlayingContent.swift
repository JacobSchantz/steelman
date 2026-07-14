import SwiftUI

/// Shared player chrome from keepMovin (`MiniPlayerView.NowPlayingContent`).
/// Discover cards use `scrollable: false`; full screens can use scrollable true.
struct NowPlayingContent: View {
    let artworkURL: URL?
    let localArtworkURL: URL?
    let title: String
    let subtitle: String?
    let currentTime: TimeInterval
    let duration: TimeInterval
    var bufferedTime: TimeInterval? = nil
    let isPlaying: Bool
    var isLoading: Bool = false
    let description: String
    var sliderInteractive: Bool = true
    var onScrubbingChanged: ((Bool) -> Void)? = nil
    var scrollable: Bool = true
    let onSeek: (TimeInterval) -> Void
    let onSkipBackward: () -> Void
    let onTogglePlayPause: () -> Void
    let onSkipForward: () -> Void
    var errorMessage: String? = nil
    /// Optional tint for the large artwork placeholder (side color).
    var accent: Color = SteelmanTheme.accent
    var badge: String? = nil
    var badgeColor: Color = .secondary

    var body: some View {
        if scrollable {
            ScrollView { content }
        } else {
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var content: some View {
        VStack(spacing: 24) {
            Spacer()

            ZStack {
                CachedAsyncImage(url: artworkURL, localURL: localArtworkURL) {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(accent.opacity(0.25))
                        .overlay(
                            Image(systemName: "bubble.left.and.bubble.right.fill")
                                .font(.system(size: 60))
                                .foregroundColor(accent)
                        )
                }
                .frame(width: 300, height: 300)
                .cornerRadius(12)
                .shadow(radius: 10)

                if let badge {
                    VStack {
                        HStack {
                            Text(badge)
                                .font(.caption.weight(.bold))
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background(badgeColor.opacity(0.92), in: Capsule())
                                .foregroundStyle(.white)
                            Spacer()
                        }
                        Spacer()
                    }
                    .padding(12)
                    .frame(width: 300, height: 300)
                }
            }

            VStack(spacing: 4) {
                Text(title)
                    .font(.title2)
                    .fontWeight(.bold)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .padding(.horizontal)

                if let subtitle, !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .lineLimit(2)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                }
            }

            HStack(spacing: 60) {
                Button(action: onSkipBackward) {
                    Image(systemName: "gobackward.15")
                        .font(.system(size: 32))
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

                Button(action: onSkipForward) {
                    Image(systemName: "goforward.15")
                        .font(.system(size: 32))
                }
            }
            .foregroundStyle(accent)

            VStack(spacing: 8) {
                if let bufferedTime {
                    BufferedScrubber(
                        currentTime: currentTime,
                        duration: duration,
                        bufferedTime: bufferedTime,
                        interactive: sliderInteractive,
                        accent: accent,
                        onSeek: onSeek,
                        onScrubbingChanged: onScrubbingChanged
                    )
                    .padding(.horizontal)
                } else {
                    Slider(value: Binding(
                        get: { currentTime },
                        set: { onSeek($0) }
                    ), in: 0...max(duration, 1))
                    .tint(accent)
                    .padding(.horizontal)
                    .allowsHitTesting(sliderInteractive)
                }

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

            if scrollable, !description.isEmpty {
                Text(description)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.leading)
                    .padding(.horizontal)
                    .padding(.top, 16)
            }

            Spacer()
        }
        .padding()
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

/// Scrubber with buffered track — from keepMovin Discover.
struct BufferedScrubber: View {
    let currentTime: TimeInterval
    let duration: TimeInterval
    let bufferedTime: TimeInterval
    let interactive: Bool
    var accent: Color = SteelmanTheme.accent
    let onSeek: (TimeInterval) -> Void
    var onScrubbingChanged: ((Bool) -> Void)? = nil

    @State private var dragFraction: Double? = nil

    private let trackHeight: CGFloat = 4
    private let thumbSize: CGFloat = 16

    var body: some View {
        GeometryReader { geo in
            let width = geo.size.width
            let usable = max(width - thumbSize, 1)
            let total = max(duration, 1)
            let playedFraction = dragFraction ?? min(max(currentTime / total, 0), 1)
            let bufferedFraction = min(max(max(bufferedTime / total, currentTime / total), 0), 1)
            let playedX = thumbSize / 2 + usable * playedFraction
            let bufferedX = thumbSize / 2 + usable * bufferedFraction

            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.secondary.opacity(0.2))
                    .frame(height: trackHeight)
                Capsule()
                    .fill(accent.opacity(0.45))
                    .frame(width: bufferedX, height: trackHeight)
                Capsule()
                    .fill(accent)
                    .frame(width: playedX, height: trackHeight)
                Circle()
                    .fill(accent)
                    .frame(width: thumbSize, height: thumbSize)
                    .shadow(radius: 1)
                    .offset(x: playedX - thumbSize / 2)
            }
            .frame(height: thumbSize)
            .contentShape(Rectangle())
            .gesture(interactive
                ? DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        onScrubbingChanged?(true)
                        dragFraction = min(max((value.location.x - thumbSize / 2) / usable, 0), 1)
                    }
                    .onEnded { value in
                        let f = min(max((value.location.x - thumbSize / 2) / usable, 0), 1)
                        dragFraction = nil
                        onSeek(f * total)
                        onScrubbingChanged?(false)
                    }
                : nil)
        }
        .frame(height: thumbSize)
    }
}

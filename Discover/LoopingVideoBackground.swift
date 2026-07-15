import SwiftUI
import UIKit
import AVFoundation

/// A full-bleed, silently looping video that sits behind a Discover page.
///
/// The product direction is that a page isn't just audio anymore — it's a full-screen
/// video with the transcript over it. For now every page shares one bundled background
/// clip (`DiscoverBackground.mp4`); later each answer can carry its own. The clip is
/// muted, loops seamlessly (it's authored as a forward-then-reverse palindrome so the
/// wrap has no visible cut), and fills the screen with `.resizeAspectFill` so there are
/// never letterbox bars whatever the device aspect ratio.
///
/// It plays purely for atmosphere: no transport, no audio session takeover (it uses the
/// ambient category so it never interrupts the Kokoro/AVSpeech narration that IS the
/// content), and it pauses itself when its page scrolls away so off-screen pages aren't
/// decoding video for nothing.
struct LoopingVideoBackground: View {
    /// Only the on-screen page should be decoding frames. Off-screen cards pass `false`
    /// so the feed isn't running a stack of video players at once.
    var isActive: Bool = true

    var body: some View {
        if let url = Self.videoURL {
            LoopingVideoLayer(url: url, isActive: isActive)
                .ignoresSafeArea()
        } else {
            // No bundled clip (shouldn't happen in a shipped build) — fall back to the
            // flat background so the page still renders.
            Color(.systemBackground)
                .ignoresSafeArea()
        }
    }

    /// The one background clip bundled with the app. Resolved once and cached.
    static let videoURL: URL? = Bundle.main.url(forResource: "DiscoverBackground", withExtension: "mp4")
}

/// Wraps a Discover page's content over the looping video: the clip, a legibility scrim,
/// then the content. Every card renders through this so the video treatment — and the
/// text colours that go with it — live in exactly one place.
///
/// The scrim is a top-and-bottom darkening gradient: the middle stays open so the video
/// reads, while the transcript and the transport controls (which sit toward the edges)
/// keep a dark backing whatever frame the loop is on. Content is forced into the dark
/// colour scheme so the semantic `.primary`/`.secondary` text used across the cards comes
/// out light over the video without every call site having to special-case its colours.
struct VideoBackdrop<Content: View>: View {
    /// Whether this page is the on-screen one — forwarded to the player so off-screen
    /// cards don't decode video.
    var isActive: Bool = true
    @ViewBuilder var content: Content

    var body: some View {
        ZStack {
            LoopingVideoBackground(isActive: isActive)

            LinearGradient(
                colors: [.black.opacity(0.55), .black.opacity(0.2), .black.opacity(0.6)],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            content
        }
        .environment(\.colorScheme, .dark)
    }
}

/// UIKit bridge: an `AVPlayerLayer` driven by an `AVQueuePlayer` + `AVPlayerLooper`.
///
/// SwiftUI has no native looping-video primitive, and `AVPlayerLooper` is the only way to
/// get a gapless loop (naively observing `didPlayToEnd` and seeking to zero stutters at
/// the wrap). The looper must be retained for the life of the player, so the coordinator
/// holds it.
private struct LoopingVideoLayer: UIViewRepresentable {
    let url: URL
    let isActive: Bool

    func makeCoordinator() -> Coordinator { Coordinator(url: url) }

    func makeUIView(context: Context) -> PlayerView {
        let view = PlayerView()
        view.playerLayer.player = context.coordinator.player
        view.playerLayer.videoGravity = .resizeAspectFill
        if isActive { context.coordinator.player.play() }
        return view
    }

    func updateUIView(_ uiView: PlayerView, context: Context) {
        if isActive {
            context.coordinator.player.play()
        } else {
            context.coordinator.player.pause()
        }
    }

    static func dismantleUIView(_ uiView: PlayerView, coordinator: Coordinator) {
        coordinator.player.pause()
    }

    final class Coordinator {
        let player: AVQueuePlayer
        private let looper: AVPlayerLooper

        init(url: URL) {
            // Deliberately does NOT touch AVAudioSession. The clip is muted and has no
            // audio track, so it needs no session of its own — and the narration player
            // owns the session (`.playback`/`.spokenAudio`, so answers play with the mute
            // switch on and in the background). Setting a category here would clobber that.
            let item = AVPlayerItem(url: url)
            let queue = AVQueuePlayer(playerItem: item)
            queue.isMuted = true
            queue.actionAtItemEnd = .advance
            self.player = queue
            self.looper = AVPlayerLooper(player: queue, templateItem: item)
        }
    }

    /// A view whose backing layer IS the `AVPlayerLayer`, so it resizes with the view
    /// automatically instead of having to hand-sync a sublayer's frame.
    final class PlayerView: UIView {
        override static var layerClass: AnyClass { AVPlayerLayer.self }
        var playerLayer: AVPlayerLayer { layer as! AVPlayerLayer }
    }
}

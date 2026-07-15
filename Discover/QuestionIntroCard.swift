import SwiftUI

/// The card that opens a question: a screen that does nothing but read the question out
/// loud. Every question starts here — you hear what's being argued before you hear anyone
/// argue it, and (like a clip) you can't scroll past it until it has been read.
///
/// It sits on the same background as every other page. The question doesn't need a colour
/// of its own to be understood as a question — the type and the reading say that.
struct QuestionIntroCard: View {
    let question: Question
    let answerCount: Int
    let isCurrent: Bool
    /// The peek page: visible so the user knows what's next, but not yet earned.
    let isLocked: Bool
    @ObservedObject var player: ClipPreviewPlayer

    private var isReading: Bool { isCurrent && player.isPlaying }

    var body: some View {
        VideoBackdrop(isActive: isCurrent) {
            VStack(spacing: 18) {
                Spacer()

                Text(question.prompt)
                    .font(.system(.largeTitle, design: .serif).weight(.bold))
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.primary)
                    .padding(.horizontal, 28)

                Spacer()

                footer
                    .padding(.bottom, 48)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        // Same whole-page transport as the argument cards: a tap toggles the reading, a double
        // tap replays the last 15 seconds, each with a brief centre flash.
        .playbackTapControls(
            isCurrent: isCurrent,
            isPlaying: player.isPlaying,
            onToggle: { player.togglePlayPause() },
            onSkipBackward: { player.skipBackward() }
        )
        .overlay { if isLocked { LockedPeekOverlay() } }
    }

    @ViewBuilder
    private var footer: some View {
        if isCurrent, player.isPreparing {
            HStack(spacing: 8) {
                ProgressView()
                Text("Warming up the voice")
            }
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.secondary)
        } else if isReading {
            HStack(spacing: 8) {
                Image(systemName: "speaker.wave.3.fill")
                    .symbolEffect(.variableColor.iterative, isActive: true)
                Text("Reading the question")
            }
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(SteelmanTheme.accent)
        } else if answerCount == 0 {
            Text("Tap to hear it again")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
        } else {
            VStack(spacing: 6) {
                Image(systemName: "chevron.compact.up")
                    .font(.system(size: 30, weight: .semibold))
                Text("Swipe up for the first argument")
                    .font(.subheadline.weight(.semibold))
            }
            .foregroundStyle(.secondary)
        }
    }
}

/// Frosts a peek page and swallows taps, so the page beyond what you've earned can be
/// seen but not driven. Shared by the question card and the clip card.
struct LockedPeekOverlay: View {
    var message = "Finish listening to this one first"

    var body: some View {
        ZStack {
            Rectangle()
                .fill(.ultraThinMaterial)
            VStack(spacing: 14) {
                Image(systemName: "lock.fill")
                    .font(.system(size: 44))
                Text(message)
                    .font(.headline)
                    .multilineTextAlignment(.center)
            }
            .foregroundStyle(.secondary)
            .padding()
        }
        .contentShape(Rectangle())
    }
}

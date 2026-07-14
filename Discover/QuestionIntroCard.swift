import SwiftUI

/// The card that opens a question: a solid screen that does nothing but read the question
/// out loud. Every question starts here — you hear what's being argued before you hear
/// anyone argue it, and (like a clip) you can't scroll past it until it has been read.
struct QuestionIntroCard: View {
    let question: Question
    let answerCount: Int
    let isCurrent: Bool
    /// The peek page: visible so the user knows what's next, but not yet earned.
    let isLocked: Bool
    @ObservedObject var player: ClipPreviewPlayer

    private var isReading: Bool { isCurrent && player.isPlaying }

    var body: some View {
        ZStack {
            SteelmanTheme.accent

            VStack(spacing: 18) {
                Spacer()

                Text("Question")
                    .font(.caption.weight(.bold))
                    .tracking(1.8)
                    .textCase(.uppercase)
                    .foregroundStyle(.white.opacity(0.65))

                Text(question.prompt)
                    .font(.system(.largeTitle, design: .serif).weight(.bold))
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 28)

                Text(answerCountText)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.white.opacity(0.65))

                Spacer()

                footer
                    .padding(.bottom, 48)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .contentShape(Rectangle())
        .onTapGesture {
            guard isCurrent else { return }
            player.togglePlayPause()
        }
        .overlay { if isLocked { LockedPeekOverlay() } }
    }

    private var answerCountText: String {
        switch answerCount {
        case 0: return "No answers yet"
        case 1: return "1 answer"
        default: return "\(answerCount) answers"
        }
    }

    @ViewBuilder
    private var footer: some View {
        if isReading {
            HStack(spacing: 8) {
                Image(systemName: "speaker.wave.3.fill")
                    .symbolEffect(.variableColor.iterative, isActive: true)
                Text("Reading the question")
            }
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.white.opacity(0.8))
        } else if answerCount == 0 {
            Text("Tap to hear it again")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.white.opacity(0.8))
        } else {
            VStack(spacing: 6) {
                Image(systemName: "chevron.compact.up")
                    .font(.system(size: 30, weight: .semibold))
                Text("Swipe up for the first argument")
                    .font(.subheadline.weight(.semibold))
            }
            .foregroundStyle(.white.opacity(0.8))
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

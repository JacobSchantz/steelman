import SwiftUI

/// Summed-up numbers about your whole body of answers, computed once from the store's list.
struct AnswerStats {
    let total: Int
    let sideA: Int
    let sideB: Int
    let withAudio: Int
    let liked: Int
    let disliked: Int
    let flaggedProfanity: Int
    let questionsAnswered: Int

    init(answers: [Answer], questions: QuestionStore) {
        total = answers.count
        sideA = answers.filter { $0.resolvedSide == .a }.count
        sideB = answers.filter { $0.resolvedSide == .b }.count
        withAudio = answers.filter(\.hasAudio).count
        liked = answers.filter { $0.reaction == .like }.count
        disliked = answers.filter { $0.reaction == .dislike }.count
        flaggedProfanity = answers.filter { $0.analysis?.containsProfanity == true }.count
        questionsAnswered = Set(answers.map(\.questionId)).count
    }
}

/// The statistics header at the top of the Answers tab: a couple of headline tiles plus a
/// bar showing how your answers split across the two sides.
struct AnswerStatsView: View {
    let stats: AnswerStats

    private var columns: [GridItem] {
        [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            LazyVGrid(columns: columns, spacing: 12) {
                tile(value: "\(stats.total)", label: "Answers", tint: SteelmanTheme.accent)
                tile(value: "\(stats.questionsAnswered)", label: "Questions", tint: SteelmanTheme.accent)
                tile(value: "\(stats.withAudio)", label: "With audio", tint: .secondary)
                tile(value: "\(stats.liked)", label: "Liked", systemImage: "hand.thumbsup.fill", tint: SteelmanTheme.accent)
                tile(value: "\(stats.disliked)", label: "Disliked", systemImage: "hand.thumbsdown.fill", tint: SteelmanTheme.danger)
                tile(value: "\(stats.flaggedProfanity)", label: "Flagged", tint: SteelmanTheme.danger)
            }

            if stats.sideA + stats.sideB > 0 {
                sideSplit
            }
        }
    }

    private func tile(value: String, label: String, systemImage: String? = nil, tint: Color) -> some View {
        VStack(spacing: 4) {
            HStack(spacing: 4) {
                if let systemImage {
                    Image(systemName: systemImage)
                        .font(.caption)
                        .foregroundStyle(tint)
                }
                Text(value)
                    .font(.title2.weight(.bold))
                    .foregroundStyle(.primary)
            }
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12))
    }

    /// A single stacked bar showing how many answers landed on each side.
    private var sideSplit: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Sides")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            GeometryReader { geo in
                let total = max(stats.sideA + stats.sideB, 1)
                let aWidth = geo.size.width * CGFloat(stats.sideA) / CGFloat(total)
                HStack(spacing: 0) {
                    SteelmanTheme.sideA.frame(width: aWidth)
                    SteelmanTheme.sideB
                }
                .clipShape(Capsule())
            }
            .frame(height: 12)
            HStack {
                Label("\(stats.sideA) Side A", systemImage: "circle.fill")
                    .foregroundStyle(SteelmanTheme.sideA)
                Spacer()
                Label("\(stats.sideB) Side B", systemImage: "circle.fill")
                    .foregroundStyle(SteelmanTheme.sideB)
            }
            .font(.caption2)
            .labelStyle(.titleAndIcon)
        }
    }
}

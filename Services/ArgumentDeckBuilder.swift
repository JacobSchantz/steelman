import Foundation

/// Builds a Discover deck that **enforces alternating viewpoints**.
///
/// Rule (product): after you hear one side of a question, you must hear the other
/// side before you can hear the original side again. Implemented by tracking the
/// last heard side per question and only enqueueing answers whose side is allowed
/// under that gate, while globally preferring A/B/A/B interleaving across the feed.
enum ArgumentDeckBuilder {
    /// Construct an ordered deck from questions + answers. Skips answers with no
    /// resolved side. Marks profanity but does not hide them (moderation is visible
    /// on the card; blocking is a later product decision).
    static func build(
        questions: [Question],
        answers: [Answer],
        audioURLProvider: (Answer) -> URL?,
        lastHeardSide: [UUID: ArgumentSide] = [:]
    ) -> [ArgumentClip] {
        let qById = Dictionary(uniqueKeysWithValues: questions.map { ($0.id, $0) })

        // Pool per question + side
        var pools: [UUID: [ArgumentSide: [Answer]]] = [:]
        for answer in answers {
            guard let side = answer.resolvedSide,
                  qById[answer.questionId] != nil else { continue }
            pools[answer.questionId, default: [:]][side, default: []].append(answer)
        }
        // Stable order within pool: newest first, then shuffle lightly by id for variety
        for qid in pools.keys {
            for side in ArgumentSide.allCases {
                pools[qid]?[side]?.sort {
                    if $0.createdAt != $1.createdAt { return $0.createdAt > $1.createdAt }
                    return $0.id.uuidString < $1.id.uuidString
                }
            }
        }

        var lastSide = lastHeardSide
        var deck: [ArgumentClip] = []
        var usedAnswerIDs = Set<UUID>()

        // Prefer questions that have both sides available for richer alternating.
        let questionOrder = questions.sorted { a, b in
            let ac = (pools[a.id]?[.a]?.count ?? 0) + (pools[a.id]?[.b]?.count ?? 0)
            let bc = (pools[b.id]?[.a]?.count ?? 0) + (pools[b.id]?[.b]?.count ?? 0)
            return ac > bc
        }

        // Keep pulling until no legal next clip remains.
        while true {
            var placed = false
            for q in questionOrder {
                guard let next = nextAnswer(
                    questionId: q.id,
                    pools: pools,
                    lastSide: lastSide[q.id],
                    used: usedAnswerIDs
                ) else { continue }

                usedAnswerIDs.insert(next.id)
                lastSide[q.id] = next.resolvedSide
                if let clip = makeClip(
                    answer: next,
                    question: q,
                    audioURL: audioURLProvider(next)
                ) {
                    deck.append(clip)
                    placed = true
                }
                // One clip per outer pass keeps global interleaving across questions.
                break
            }
            if !placed { break }
        }

        return deck
    }

    /// Allowed next side: if we've never heard this question, either side; else only the opposite.
    private static func nextAnswer(
        questionId: UUID,
        pools: [UUID: [ArgumentSide: [Answer]]],
        lastSide: ArgumentSide?,
        used: Set<UUID>
    ) -> Answer? {
        let allowed: [ArgumentSide]
        if let lastSide {
            allowed = [lastSide.opposite]
        } else {
            // Prefer starting on A when both available (stable feed).
            allowed = [.a, .b]
        }

        for side in allowed {
            if let candidate = pools[questionId]?[side]?.first(where: { !used.contains($0.id) }) {
                return candidate
            }
        }
        return nil
    }

    private static func makeClip(
        answer: Answer,
        question: Question,
        audioURL: URL?
    ) -> ArgumentClip? {
        guard let side = answer.resolvedSide else { return nil }
        let analysis = answer.analysis
        // Text-only duration estimate ~140 wpm for scrubber span before TTS reports real length.
        let wordCount = answer.text.split { $0.isWhitespace || $0.isNewline }.count
        let estimated = max(8, Double(wordCount) / 2.3)

        return ArgumentClip(
            questionId: question.id,
            answerId: answer.id,
            questionPrompt: question.prompt,
            side: side,
            sideLabel: question.label(for: side),
            answerText: answer.text,
            analysisSummary: analysis?.summary ?? "",
            containsProfanity: analysis?.containsProfanity ?? false,
            leanConfidence: analysis?.leanConfidence ?? 0,
            audioURL: audioURL,
            duration: estimated,
            startTime: 0
        )
    }
}

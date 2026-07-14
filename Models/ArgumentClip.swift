import Foundation

/// One full-screen Discover card: a single viewpoint (answer) on a question.
/// Mirrors keepMovin's `PodcastRecommendation` + `PodcastClip` pair in one type
/// for the steelman domain.
struct ArgumentClip: Identifiable, Codable, Equatable {
    let id: UUID
    let questionId: UUID
    let answerId: UUID
    let questionPrompt: String
    let side: ArgumentSide
    let sideLabel: String
    let answerText: String
    let analysisSummary: String
    let containsProfanity: Bool
    let leanConfidence: Double
    /// Playable audio (file URL). Nil → text-only; Discover plays via TTS.
    var audioURL: URL?
    var duration: TimeInterval
    /// Always 0 for submitted answers (full take, not a random mid-episode seek).
    var startTime: TimeInterval
    /// Pre-downloaded segment file name in the clip cache (keepMovin Discover pattern).
    var segmentFileName: String?

    init(
        id: UUID = UUID(),
        questionId: UUID,
        answerId: UUID,
        questionPrompt: String,
        side: ArgumentSide,
        sideLabel: String,
        answerText: String,
        analysisSummary: String = "",
        containsProfanity: Bool = false,
        leanConfidence: Double = 0,
        audioURL: URL? = nil,
        duration: TimeInterval = 0,
        startTime: TimeInterval = 0,
        segmentFileName: String? = nil
    ) {
        self.id = id
        self.questionId = questionId
        self.answerId = answerId
        self.questionPrompt = questionPrompt
        self.side = side
        self.sideLabel = sideLabel
        self.answerText = answerText
        self.analysisSummary = analysisSummary
        self.containsProfanity = containsProfanity
        self.leanConfidence = leanConfidence
        self.audioURL = audioURL
        self.duration = duration
        self.startTime = startTime
        self.segmentFileName = segmentFileName
    }

    /// Headline for NowPlayingContent (episode-title slot in keepMovin). The question
    /// isn't repeated on the card — Discover scrolls one question at a time, so the
    /// question card and the toolbar already say what's being argued.
    var title: String { sideLabel }

    var description: String {
        if !analysisSummary.isEmpty {
            return analysisSummary + "\n\n" + answerText
        }
        return answerText
    }
}

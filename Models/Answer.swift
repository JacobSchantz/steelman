import Foundation

/// User-submitted text or audio response to a question.
struct Answer: Identifiable, Codable, Hashable {
    let id: UUID
    var questionId: UUID
    /// Author's claimed side (optional; AI may reclassify).
    var claimedSide: ArgumentSide?
    var text: String
    /// Relative filename under Documents/AnswerAudio, or nil for text-only.
    var audioFileName: String?
    var createdAt: Date
    var analysis: AnswerAnalysis?

    init(
        id: UUID = UUID(),
        questionId: UUID,
        claimedSide: ArgumentSide? = nil,
        text: String = "",
        audioFileName: String? = nil,
        createdAt: Date = Date(),
        analysis: AnswerAnalysis? = nil
    ) {
        self.id = id
        self.questionId = questionId
        self.claimedSide = claimedSide
        self.text = text
        self.audioFileName = audioFileName
        self.createdAt = createdAt
        self.analysis = analysis
    }

    /// Side used for deck ordering / alternating: AI lean if available, else claimed.
    var resolvedSide: ArgumentSide? {
        analysis?.leanSide ?? claimedSide
    }

    var hasAudio: Bool { audioFileName != nil }
}

/// AI review of an answer: profanity + which side of the question it supports.
struct AnswerAnalysis: Codable, Hashable {
    var leanSide: ArgumentSide
    var leanConfidence: Double
    var containsProfanity: Bool
    var profanityScore: Double
    var summary: String
    var analyzedAt: Date

    init(
        leanSide: ArgumentSide,
        leanConfidence: Double,
        containsProfanity: Bool,
        profanityScore: Double,
        summary: String,
        analyzedAt: Date = Date()
    ) {
        self.leanSide = leanSide
        self.leanConfidence = leanConfidence
        self.containsProfanity = containsProfanity
        self.profanityScore = profanityScore
        self.summary = summary
        self.analyzedAt = analyzedAt
    }
}

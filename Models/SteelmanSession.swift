import Foundation

/// One steelmanning exercise: claim → strongest case → strongest rebuttal → earned position.
struct SteelmanSession: Identifiable, Codable, Hashable {
    var id: UUID
    var title: String
    /// The claim or side you're steelmanning (not necessarily your own view).
    var claim: String
    /// Strongest honest version of the argument — to that side's satisfaction.
    var steelman: String
    /// Hardest objection the steelman has to answer.
    var strongestRebuttal: String
    /// How the steelman answers that rebuttal (or admits it can't).
    var rebuttalAnswer: String
    /// Your position — only filled after the steelman is earned.
    var ownPosition: String
    /// Whether this crossed the hard line (rule 6) and should stop.
    var isWeapon: Bool
    var createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        title: String = "",
        claim: String = "",
        steelman: String = "",
        strongestRebuttal: String = "",
        rebuttalAnswer: String = "",
        ownPosition: String = "",
        isWeapon: Bool = false,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.title = title
        self.claim = claim
        self.steelman = steelman
        self.strongestRebuttal = strongestRebuttal
        self.rebuttalAnswer = rebuttalAnswer
        self.ownPosition = ownPosition
        self.isWeapon = isWeapon
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    var displayTitle: String {
        let t = title.trimmingCharacters(in: .whitespacesAndNewlines)
        if !t.isEmpty { return t }
        let c = claim.trimmingCharacters(in: .whitespacesAndNewlines)
        if !c.isEmpty {
            return c.count > 48 ? String(c.prefix(45)) + "…" : c
        }
        return "Untitled steelman"
    }

    /// Progress through the honesty pipeline (claim → steelman → rebuttal → answer → opinion).
    var completedSteps: Int {
        var n = 0
        if !claim.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { n += 1 }
        if !steelman.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { n += 1 }
        if !strongestRebuttal.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { n += 1 }
        if !rebuttalAnswer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { n += 1 }
        if !ownPosition.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { n += 1 }
        return n
    }

    var totalSteps: Int { 5 }

    /// Opinion is "earned" only after steelman + rebuttal + answer exist (rules 7–8).
    var hasEarnedOpinion: Bool {
        !steelman.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !strongestRebuttal.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !rebuttalAnswer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

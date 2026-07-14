import Foundation

/// A steelman debate prompt with two labeled sides.
struct Question: Identifiable, Codable, Hashable {
    let id: UUID
    var prompt: String
    var sideALabel: String
    var sideBLabel: String
    var detail: String
    /// What this question is *about* — "Cities", "Work". Free text rather than a fixed
    /// taxonomy: the browse page builds its filter row from the categories questions
    /// actually wear, so the vocabulary is whatever people write. Optional, and optional in
    /// the JSON too, so questions saved before categories existed still decode.
    var category: String?
    var createdAt: Date

    init(
        id: UUID = UUID(),
        prompt: String,
        sideALabel: String,
        sideBLabel: String,
        detail: String = "",
        category: String? = nil,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.prompt = prompt
        self.sideALabel = sideALabel
        self.sideBLabel = sideBLabel
        self.detail = detail
        self.category = category
        self.createdAt = createdAt
    }

    func label(for side: ArgumentSide) -> String {
        switch side {
        case .a: return sideALabel
        case .b: return sideBLabel
        }
    }

    /// Everything about a question that reads as text, for the browse page's search field:
    /// you should find "remote work" by typing it, but also by typing a side you remember
    /// ("office-first") or the category it sits in.
    var searchText: String {
        [prompt, detail, sideALabel, sideBLabel, category ?? ""]
            .joined(separator: " ")
            .lowercased()
    }

    /// The category with its whitespace trimmed, and nil rather than "" when it's blank —
    /// so `if let` is enough to know whether to draw a chip.
    var normalizedCategory: String? {
        guard let trimmed = category?.trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmed.isEmpty else { return nil }
        return trimmed
    }
}

enum ArgumentSide: String, Codable, CaseIterable, Hashable {
    case a
    case b

    var opposite: ArgumentSide {
        switch self {
        case .a: return .b
        case .b: return .a
        }
    }

    var displayName: String {
        switch self {
        case .a: return "Side A"
        case .b: return "Side B"
        }
    }
}

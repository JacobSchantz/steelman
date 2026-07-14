import Foundation

/// A steelman debate prompt with two labeled sides.
struct Question: Identifiable, Codable, Hashable {
    let id: UUID
    var prompt: String
    var sideALabel: String
    var sideBLabel: String
    var detail: String
    var createdAt: Date

    init(
        id: UUID = UUID(),
        prompt: String,
        sideALabel: String,
        sideBLabel: String,
        detail: String = "",
        createdAt: Date = Date()
    ) {
        self.id = id
        self.prompt = prompt
        self.sideALabel = sideALabel
        self.sideBLabel = sideBLabel
        self.detail = detail
        self.createdAt = createdAt
    }

    func label(for side: ArgumentSide) -> String {
        switch side {
        case .a: return sideALabel
        case .b: return sideBLabel
        }
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

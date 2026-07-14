import Foundation
import SwiftUI

@MainActor
final class QuestionStore: ObservableObject {
    @Published private(set) var questions: [Question] = []

    private let fileURL: URL
    private let encoder = JSONEncoder.steelman
    private let decoder = JSONDecoder.steelman

    init() {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        fileURL = docs.appendingPathComponent("steelman_questions.json")
        load()
        if questions.isEmpty {
            questions = Self.seedQuestions
            persist()
        }
    }

    func question(id: UUID) -> Question? {
        questions.first { $0.id == id }
    }

    /// Every category currently in use, alphabetically. There is no category list to
    /// maintain — a category exists exactly as long as a question wears it, which is what
    /// lets the browse page's filter row be built straight from the data. Case-insensitively
    /// de-duplicated ("Work" and "work" are one category), displayed as first written.
    var categories: [String] {
        var firstSpelling: [String: String] = [:]
        for question in questions {
            guard let category = question.normalizedCategory else { continue }
            let key = category.lowercased()
            if firstSpelling[key] == nil { firstSpelling[key] = category }
        }
        return firstSpelling.values.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }

    func add(_ question: Question) {
        questions.insert(question, at: 0)
        persist()
    }

    func delete(_ question: Question) {
        questions.removeAll { $0.id == question.id }
        persist()
    }

    private func load() {
        guard let data = try? Data(contentsOf: fileURL),
              let decoded = try? decoder.decode([Question].self, from: data) else {
            questions = []
            return
        }
        questions = decoded
    }

    private func persist() {
        guard let data = try? encoder.encode(questions) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }

    /// Starter debates so Discover has content before users submit.
    static let seedQuestions: [Question] = [
        Question(
            id: UUID(uuidString: "11111111-1111-1111-1111-111111111111")!,
            prompt: "Should cities ban cars from downtown cores on weekdays?",
            sideALabel: "Ban cars downtown",
            sideBLabel: "Keep cars downtown",
            detail: "Public space, climate, equity for people who can't easily switch modes.",
            category: "Cities"
        ),
        Question(
            id: UUID(uuidString: "22222222-2222-2222-2222-222222222222")!,
            prompt: "Is remote work better for most knowledge workers than full-time office?",
            sideALabel: "Remote-first is better",
            sideBLabel: "Office-first is better",
            detail: "Productivity, mentorship, loneliness, real-estate, and who bears the costs.",
            category: "Work"
        ),
        Question(
            id: UUID(uuidString: "33333333-3333-3333-3333-333333333333")!,
            prompt: "Should social platforms be legally required to verify adult users' ages?",
            sideALabel: "Require age verification",
            sideBLabel: "No mandated verification",
            detail: "Child safety, privacy, free speech, and enforcement costs.",
            category: "Technology"
        ),
    ]
}

extension JSONEncoder {
    static let steelman: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        return e
    }()
}

extension JSONDecoder {
    static let steelman: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()
}

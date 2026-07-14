import Foundation
import SwiftUI

@MainActor
final class SessionStore: ObservableObject {
    @Published private(set) var sessions: [SteelmanSession] = []

    private let fileURL: URL
    private let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        return e
    }()
    private let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()

    init() {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        fileURL = docs.appendingPathComponent("steelman_sessions.json")
        load()
    }

    func load() {
        guard FileManager.default.fileExists(atPath: fileURL.path),
              let data = try? Data(contentsOf: fileURL),
              let decoded = try? decoder.decode([SteelmanSession].self, from: data) else {
            sessions = []
            return
        }
        sessions = decoded.sorted { $0.updatedAt > $1.updatedAt }
    }

    func save(_ session: SteelmanSession) {
        var s = session
        s.updatedAt = Date()
        if let idx = sessions.firstIndex(where: { $0.id == s.id }) {
            sessions[idx] = s
        } else {
            sessions.insert(s, at: 0)
        }
        sessions.sort { $0.updatedAt > $1.updatedAt }
        persist()
    }

    func delete(_ session: SteelmanSession) {
        sessions.removeAll { $0.id == session.id }
        persist()
    }

    func delete(at offsets: IndexSet) {
        for i in offsets {
            sessions.remove(at: i)
        }
        persist()
    }

    private func persist() {
        guard let data = try? encoder.encode(sessions) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }
}

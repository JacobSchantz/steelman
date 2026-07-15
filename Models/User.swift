import SwiftUI

/// A person who submits answers. The app has no accounts or network identity — a "user" is
/// just a local label you attach to answers so the two-per-question rule (one answer per side)
/// can be enforced per person rather than per device. Which user is *active* lives on
/// `UserStore`, not here; this is only the identity.
struct User: Identifiable, Codable, Hashable {
    let id: UUID
    var name: String
    var createdAt: Date

    init(id: UUID = UUID(), name: String, createdAt: Date = Date()) {
        self.id = id
        self.name = name
        self.createdAt = createdAt
    }

    /// The name with surrounding whitespace stripped, or nil when it's effectively blank —
    /// so `if let` is enough to know whether the user typed a real name.
    var normalizedName: String? {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    /// The one or two letters shown in the avatar circle, derived from the name so the same
    /// user always wears the same monogram.
    var initials: String {
        let words = (normalizedName ?? "?")
            .split(separator: " ")
            .prefix(2)
            .compactMap { $0.first }
        return String(words).uppercased()
    }

    /// A stable colour for the avatar, hashed from the id the same way categories are hashed
    /// from their name (djb2, not `hashValue`, so it survives across launches).
    var color: Color {
        var hash: UInt64 = 5381
        for byte in id.uuidString.utf8 {
            hash = (hash &* 33) &+ UInt64(byte)
        }
        return User.avatarPalette[Int(hash % UInt64(User.avatarPalette.count))]
    }

    private static let avatarPalette: [Color] = [
        Color(red: 0.22, green: 0.45, blue: 0.72),
        Color(red: 0.85, green: 0.45, blue: 0.22),
        Color(red: 0.30, green: 0.56, blue: 0.40),
        Color(red: 0.55, green: 0.36, blue: 0.68),
        Color(red: 0.78, green: 0.55, blue: 0.20),
        Color(red: 0.24, green: 0.55, blue: 0.62),
    ]
}

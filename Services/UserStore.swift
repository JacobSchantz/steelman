import Foundation
import SwiftUI

/// The single signed-in user. Every answer is stamped with this user's id at submit time, and
/// the "one answer per side" rule is checked against it. There's no roster and no switching —
/// one person is signed in, so any answer they submit is obviously theirs.
///
/// There is always a user: the store seeds one on an empty load and preserves the id across
/// launches, so callers can read `currentUser` without unwrapping a "no user yet" state. The
/// backing file is still a `[User]` array (older installs may hold several from when switching
/// existed); we keep the saved-active user and simply ignore the rest.
@MainActor
final class UserStore: ObservableObject {
    /// The full roster as loaded from disk. Kept private now that there's no switching UI — it
    /// exists only to preserve the active user's id (and any legacy extras) across launches.
    private var users: [User] = []
    @Published private(set) var currentUserID: UUID
    /// Whether the account is signed in. The app has no auth backend yet, so this is a local
    /// flag: signing out drops the Profile tab to its sign-in screen without touching any data,
    /// and signing back in restores it. It's the hook a real identity provider (Sign in with
    /// Apple, a server) would replace later.
    @Published private(set) var isSignedIn: Bool

    private let fileURL: URL
    private let currentKey = "steelman.currentUserID"
    private let signedInKey = "steelman.isSignedIn"
    private let encoder = JSONEncoder.steelman
    private let decoder = JSONDecoder.steelman

    init() {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        fileURL = docs.appendingPathComponent("steelman_users.json")

        let loaded = Self.load(from: fileURL, decoder: decoder)
        let roster = loaded.isEmpty ? [User(name: "You")] : loaded
        users = roster

        // Restore the saved active user, but never trust an id that isn't in the roster
        // anymore (a deleted user, or a fresh install): fall back to the first user.
        let savedID = UserDefaults.standard.string(forKey: currentKey).flatMap(UUID.init)
        currentUserID = roster.first { $0.id == savedID }?.id ?? roster[0].id

        // Default to signed in so existing installs aren't kicked out; sign-out is an explicit
        // choice the account holder makes.
        isSignedIn = UserDefaults.standard.object(forKey: signedInKey) as? Bool ?? true

        if loaded.isEmpty { persist() }
        UserDefaults.standard.set(currentUserID.uuidString, forKey: currentKey)
    }

    var currentUser: User {
        users.first { $0.id == currentUserID } ?? users[0]
    }

    func user(id: UUID) -> User? {
        users.first { $0.id == id }
    }

    /// Rename the signed-in user.
    func rename(to name: String) {
        guard let i = users.firstIndex(where: { $0.id == currentUserID }) else { return }
        users[i].name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        persist()
    }

    /// Sign in the account, optionally renaming the user to the name typed on the sign-in
    /// screen so "my account" carries the name I just gave it.
    func signIn(name: String? = nil) {
        if let name = name?.trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty {
            rename(to: name)
        }
        isSignedIn = true
        UserDefaults.standard.set(true, forKey: signedInKey)
    }

    /// Sign out. Local-only: nothing is deleted, the Profile tab just returns to its sign-in
    /// screen. Answers and the account roster stay on the device.
    func signOut() {
        isSignedIn = false
        UserDefaults.standard.set(false, forKey: signedInKey)
    }

    private static func load(from url: URL, decoder: JSONDecoder) -> [User] {
        guard let data = try? Data(contentsOf: url),
              let decoded = try? decoder.decode([User].self, from: data) else {
            return []
        }
        return decoded
    }

    private func persist() {
        guard let data = try? encoder.encode(users) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }
}

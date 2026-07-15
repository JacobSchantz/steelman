import SwiftUI

/// The **Users** tab — the roster of people who answer on this device, and a way to pick who's
/// currently answering.
///
/// The app has no accounts; a "user" is just a local label. What it buys you is the two-per-
/// question rule: each person gets one answer per side, so the same phone can hold several
/// people's takes on the same debate without one person flooding a side. Whoever is marked
/// active here is the author stamped on the next answer you submit — and the count beside each
/// name is how many answers already carry it. The feed itself never names the author; the
/// association lives here, not in Discover.
struct UsersView: View {
    @ObservedObject var users: UserStore
    @ObservedObject var answers: AnswerStore

    @State private var addingUser = false
    @State private var newName = ""
    @State private var renaming: User?
    @State private var renameText = ""

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(users.users) { user in
                        Button {
                            users.setCurrent(user.id)
                        } label: {
                            UserRow(
                                user: user,
                                answerCount: answerCount(for: user),
                                isActive: user.id == users.currentUserID
                            )
                        }
                        .buttonStyle(.plain)
                        .swipeActions(edge: .trailing) {
                            if users.users.count > 1 {
                                Button(role: .destructive) {
                                    users.delete(user.id)
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                            }
                            Button {
                                renaming = user
                                renameText = user.name
                            } label: {
                                Label("Rename", systemImage: "pencil")
                            }
                            .tint(SteelmanTheme.accent)
                        }
                    }
                } footer: {
                    Text("Tap a person to make them active — their name is attached to the answers you submit next. Each person gets one answer per side of a question.")
                }
            }
            .navigationTitle("Users")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        newName = ""
                        addingUser = true
                    } label: {
                        Label("Add user", systemImage: "person.badge.plus")
                    }
                }
            }
            .alert("New user", isPresented: $addingUser) {
                TextField("Name", text: $newName)
                Button("Cancel", role: .cancel) {}
                Button("Add") {
                    let trimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !trimmed.isEmpty { users.add(name: trimmed) }
                }
            } message: {
                Text("Adds a person and makes them the active author.")
            }
            .alert("Rename user", isPresented: Binding(
                get: { renaming != nil },
                set: { if !$0 { renaming = nil } }
            )) {
                TextField("Name", text: $renameText)
                Button("Cancel", role: .cancel) { renaming = nil }
                Button("Save") {
                    if let user = renaming {
                        let trimmed = renameText.trimmingCharacters(in: .whitespacesAndNewlines)
                        if !trimmed.isEmpty { users.rename(user.id, to: trimmed) }
                    }
                    renaming = nil
                }
            }
        }
    }

    private func answerCount(for user: User) -> Int {
        answers.answers.reduce(0) { $0 + ($1.userId == user.id ? 1 : 0) }
    }
}

/// One person in the roster: avatar monogram, name, how many answers carry their id, and a
/// checkmark when they're the active author.
private struct UserRow: View {
    let user: User
    let answerCount: Int
    let isActive: Bool

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle().fill(user.color.opacity(0.22))
                Text(user.initials)
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(user.color)
            }
            .frame(width: 40, height: 40)

            VStack(alignment: .leading, spacing: 2) {
                Text(user.normalizedName ?? "Unnamed")
                    .font(.body.weight(.medium))
                    .foregroundStyle(.primary)
                Text(answerCount == 1 ? "1 answer" : "\(answerCount) answers")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if isActive {
                Label("Active", systemImage: "checkmark.circle.fill")
                    .labelStyle(.iconOnly)
                    .font(.title3)
                    .foregroundStyle(SteelmanTheme.accent)
                    .accessibilityLabel("Active user")
            }
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
    }
}

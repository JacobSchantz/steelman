import SwiftUI

/// The **Profile** tab — *my account*.
///
/// This used to be a flat roster of everyone who answers on the device. The reframe: lead with
/// a single account — mine — the way a TikTok-style profile does. My avatar, my name, how many
/// answers carry it, and the account controls: edit my name, and sign in / out.
///
/// The app still has no auth backend, so "sign in / out" is a local flag on `UserStore`
/// (see `isSignedIn`) — signing out drops this screen to its sign-in landing without deleting
/// anything, and signing back in restores it. It's the seam a real identity provider (Sign in
/// with Apple, a server) would slot into later.
///
/// The multi-person capability the two-per-question rule leans on (one answer per side, per
/// person) isn't gone — it moves into a secondary **Switch account** section, mirroring the
/// account switcher a real profile screen carries. Whoever is active there is still the author
/// stamped on the next answer.
struct ProfileView: View {
    @ObservedObject var users: UserStore
    @ObservedObject var answers: AnswerStore

    @State private var addingUser = false
    @State private var newName = ""
    @State private var renaming: User?
    @State private var renameText = ""
    @State private var signInName = ""

    var body: some View {
        NavigationStack {
            Group {
                if users.isSignedIn {
                    signedInProfile
                } else {
                    signedOutState
                }
            }
            .navigationTitle("Profile")
            .navigationBarTitleDisplayMode(users.isSignedIn ? .large : .inline)
            .alert("New account", isPresented: $addingUser) {
                TextField("Name", text: $newName)
                Button("Cancel", role: .cancel) {}
                Button("Add") {
                    let trimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !trimmed.isEmpty { users.add(name: trimmed) }
                }
            } message: {
                Text("Adds another person on this device and makes them the active author.")
            }
            .alert("Edit name", isPresented: Binding(
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

    // MARK: - Signed in

    private var signedInProfile: some View {
        List {
            Section {
                profileHeader
            }
            .listRowBackground(Color.clear)
            .listRowInsets(EdgeInsets(top: 8, leading: 0, bottom: 8, trailing: 0))

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
                Button {
                    newName = ""
                    addingUser = true
                } label: {
                    Label("Add another account", systemImage: "person.badge.plus")
                }
            } header: {
                Text("Switch account")
            } footer: {
                Text("Tap a person to make them the active author — their name is attached to the answers you submit next. Each person gets one answer per side of a question.")
            }

            Section {
                Button(role: .destructive) {
                    users.signOut()
                } label: {
                    Label("Sign out", systemImage: "rectangle.portrait.and.arrow.right")
                }
            } footer: {
                Text("Signing out returns you to the sign-in screen. Your accounts and answers stay on this device.")
            }
        }
    }

    /// The account header — a TikTok-style profile summit: big avatar, name, answer count, and
    /// a quick "Edit name" chip.
    private var profileHeader: some View {
        let me = users.currentUser
        return VStack(spacing: 10) {
            ZStack {
                Circle().fill(me.color.opacity(0.22))
                Text(me.initials)
                    .font(.largeTitle.weight(.bold))
                    .foregroundStyle(me.color)
            }
            .frame(width: 88, height: 88)

            Text(me.normalizedName ?? "You")
                .font(.title2.weight(.semibold))
                .foregroundStyle(.primary)

            Text(answerCountText(for: me))
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Button {
                renaming = me
                renameText = me.name
            } label: {
                Text("Edit name")
                    .font(.subheadline.weight(.medium))
                    .padding(.horizontal, 18)
                    .padding(.vertical, 7)
                    .background(SteelmanTheme.accent.opacity(0.15), in: Capsule())
                    .foregroundStyle(SteelmanTheme.accent)
            }
            .padding(.top, 2)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
    }

    // MARK: - Signed out

    private var signedOutState: some View {
        VStack(spacing: 18) {
            Image(systemName: "person.crop.circle.badge.questionmark")
                .font(.system(size: 64))
                .foregroundStyle(SteelmanTheme.accent)

            VStack(spacing: 8) {
                Text("Sign in to Steelman")
                    .font(.title2.weight(.semibold))
                Text("Your account is what stamps your name on the answers you submit and keeps the one-per-side rule yours.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }

            VStack(spacing: 12) {
                TextField("Your name", text: $signInName)
                    .textFieldStyle(.roundedBorder)
                    .textInputAutocapitalization(.words)

                Button {
                    let trimmed = signInName.trimmingCharacters(in: .whitespacesAndNewlines)
                    users.signIn(name: trimmed.isEmpty ? nil : trimmed)
                    signInName = ""
                } label: {
                    Text("Sign in")
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                }
                .buttonStyle(.borderedProminent)
                .tint(SteelmanTheme.accent)
            }
            .padding(.horizontal, 32)
            .padding(.top, 4)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear { signInName = users.currentUser.normalizedName ?? "" }
    }

    // MARK: - Helpers

    private func answerCount(for user: User) -> Int {
        answers.answers.reduce(0) { $0 + ($1.userId == user.id ? 1 : 0) }
    }

    private func answerCountText(for user: User) -> String {
        let n = answerCount(for: user)
        return n == 1 ? "1 answer" : "\(n) answers"
    }
}

/// One account in the switcher: avatar monogram, name, how many answers carry their id, and a
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
                    .accessibilityLabel("Active account")
            }
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
    }
}

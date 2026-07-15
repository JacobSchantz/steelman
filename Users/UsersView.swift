import SwiftUI

/// The **Profile** tab — *my account*.
///
/// There is exactly one user signed in at a time, so this screen is just that: my avatar, my
/// name, how many answers carry it, and the account controls — edit my name, and sign in / out.
/// A TikTok-style profile summit with nothing below it to switch between, because there's
/// nothing to switch to.
///
/// The app still has no auth backend, so "sign in / out" is a local flag on `UserStore`
/// (see `isSignedIn`) — signing out drops this screen to its sign-in landing without deleting
/// anything, and signing back in restores it. It's the seam a real identity provider (Sign in
/// with Apple, a server) would slot into later.
///
/// Every answer you submit is stamped with your id and, because you're the only user, is
/// obviously yours — the Answers tab shows only those. Other people's answers (once a backend
/// brings them in) carry their own ids and never appear as yours.
struct ProfileView: View {
    @ObservedObject var users: UserStore
    @ObservedObject var answers: AnswerStore

    @State private var renaming: User?
    @State private var renameText = ""
    @State private var signInName = ""
    /// Settings used to hang off the feed's action rail; it now lives here, next to the rest of
    /// the account controls, reached from the gear in this tab's navigation bar.
    @State private var showingSettings = false

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
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showingSettings = true
                    } label: {
                        Image(systemName: "gearshape")
                    }
                    .accessibilityLabel("Settings")
                }
            }
            // The voice/playback settings, moved here from the feed's action rail. A sheet keeps
            // it a quick flick-and-dismiss that leaves the Profile screen's own state untouched.
            .sheet(isPresented: $showingSettings) {
                SettingsView(settings: SpeechSettings.shared)
            }
            .alert("Edit name", isPresented: Binding(
                get: { renaming != nil },
                set: { if !$0 { renaming = nil } }
            )) {
                TextField("Name", text: $renameText)
                Button("Cancel", role: .cancel) { renaming = nil }
                Button("Save") {
                    if renaming != nil {
                        let trimmed = renameText.trimmingCharacters(in: .whitespacesAndNewlines)
                        if !trimmed.isEmpty { users.rename(to: trimmed) }
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
                Button(role: .destructive) {
                    users.signOut()
                } label: {
                    Label("Sign out", systemImage: "rectangle.portrait.and.arrow.right")
                }
            } footer: {
                Text("Signing out returns you to the sign-in screen. Your answers stay on this device.")
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

            Text(answerCountText)
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

    /// How many answers carry my id — the only author on this device.
    private var answerCountText: String {
        let n = answers.answers.reduce(0) { $0 + ($1.userId == users.currentUserID ? 1 : 0) }
        return n == 1 ? "1 answer" : "\(n) answers"
    }
}

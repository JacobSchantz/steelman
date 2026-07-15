import SwiftUI
import TestablesKit

@main
struct SteelmanApp: App {
    @StateObject private var questions = QuestionStore()
    @StateObject private var answers = AnswerStore()
    @StateObject private var users = UserStore()

    var body: some Scene {
        WindowGroup {
            RootView(questions: questions, answers: answers, users: users)
        }
    }
}

/// Two tabs. **Feed** is the Discover experience — you're inside a question, listening to the
/// viewpoints on it one at a time, and the toolbar's question picker is the only way sideways.
/// **Answers** is the other view of the same corpus: a flat, editable list of everything you've
/// said, with statistics and a thumbs up/down per answer. The Feed tab is how you get back to
/// listening from there.
///
/// `QuestionsView` (add a question) is still in the project but no longer has an entry point —
/// it's one line away from coming back behind a button if we want it on this screen.
///
/// **Profile** is the third tab: *my account*. It leads with a single account — mine — the way
/// a TikTok profile does (avatar, name, answer count, sign in / out), with an account switcher
/// tucked below it so the two-per-question rule (one answer per side, per person) still means
/// something: the same phone can carry several people's takes.
@MainActor
struct RootView: View {
    @ObservedObject var questions: QuestionStore
    @ObservedObject var answers: AnswerStore
    @ObservedObject var users: UserStore

    var body: some View {
        TabView {
            DiscoverView(questions: questions, answers: answers, users: users)
                .tabItem {
                    Label("Feed", systemImage: "play.rectangle.on.rectangle")
                }

            AnswersView(questions: questions, answers: answers)
                .tabItem {
                    Label("Answers", systemImage: "text.bubble")
                }

            ProfileView(users: users, answers: answers)
                .tabItem {
                    Label("Profile", systemImage: "person.crop.circle")
                }
        }
        .tint(SteelmanTheme.accent)
        .overlay(alignment: .top) {
            TestingBannerView(config: TestingViewModel.shared.config)
        }
        .onAppear {
            TestingViewModel.shared.loadTestables()
        }
    }
}

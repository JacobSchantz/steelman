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
/// **Profile** is the third tab: *my account*. There's exactly one user signed in, so it's just
/// that — my avatar, my name, my answer count, and sign in / out. No account switcher: every
/// answer is obviously mine, and the Answers tab shows only mine.
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

            AnswersView(questions: questions, answers: answers, users: users)
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

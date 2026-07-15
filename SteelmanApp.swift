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
/// **Users** is the third tab: the roster of people who answer on this device and a picker for
/// who's currently answering. It's what makes the two-per-question rule (one answer per side,
/// per person) mean something — the same phone can carry several people's takes.
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

            UsersView(users: users, answers: answers)
                .tabItem {
                    Label("Users", systemImage: "person.2")
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

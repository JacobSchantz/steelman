import SwiftUI
import TestablesKit

@main
struct SteelmanApp: App {
    @StateObject private var questions = QuestionStore()
    @StateObject private var answers = AnswerStore()

    var body: some Scene {
        WindowGroup {
            RootView(questions: questions, answers: answers)
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
@MainActor
struct RootView: View {
    @ObservedObject var questions: QuestionStore
    @ObservedObject var answers: AnswerStore

    var body: some View {
        TabView {
            DiscoverView(questions: questions, answers: answers)
                .tabItem {
                    Label("Feed", systemImage: "play.rectangle.on.rectangle")
                }

            AnswersView(questions: questions, answers: answers)
                .tabItem {
                    Label("Answers", systemImage: "text.bubble")
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

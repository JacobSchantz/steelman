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

/// The whole app is the Discover feed. There are no tabs: you are always inside a
/// question, listening to the viewpoints on it, and the toolbar's question picker is the
/// only way sideways.
///
/// `QuestionsView` / `SubmitAnswerView` (add a question, dictate an answer, AI lean +
/// profanity scoring) are still in the project but no longer have an entry point — they
/// are one line away from coming back behind a button if we want them on this screen.
@MainActor
struct RootView: View {
    @ObservedObject var questions: QuestionStore
    @ObservedObject var answers: AnswerStore

    var body: some View {
        DiscoverView(questions: questions, answers: answers)
            .tint(SteelmanTheme.accent)
            .overlay(alignment: .top) {
                TestingBannerView(config: TestingViewModel.shared.config)
            }
            .onAppear {
                TestingViewModel.shared.loadTestables()
            }
    }
}

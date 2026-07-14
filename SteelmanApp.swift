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

@MainActor
struct RootView: View {
    @ObservedObject var questions: QuestionStore
    @ObservedObject var answers: AnswerStore

    var body: some View {
        TabView {
            DiscoverView(questions: questions, answers: answers)
                .tabItem {
                    Label("Discover", systemImage: "sparkles")
                }

            QuestionsView(questions: questions, answers: answers)
                .tabItem {
                    Label("Questions", systemImage: "text.bubble.fill")
                }

            SubmitAnswerView(questions: questions, answers: answers)
                .tabItem {
                    Label("Answer", systemImage: "mic.badge.plus")
                }

            RulesAboutView()
                .tabItem {
                    Label("Rules", systemImage: "book.closed.fill")
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

/// Compact rules + about (from the project README).
struct RulesAboutView: View {
    private let rules: [(Int, String, String)] = [
        (1, "Both sides have a defensible core", "If smart, honest people land on different sides, there's something worth building."),
        (2, "You can't guess how it ends", "If the strongest version might surprise you, that's the good stuff."),
        (3, "It makes you roll your eyes", "Eye-rolling is a green light — you may never have heard the best version."),
        (4, "\"Obvious\" stuff is worth arguing for", "Defending the consensus turns a borrowed belief into one you own."),
        (5, "False beliefs still teach reasoning", "Steelman why a reasonable person once concluded it — not the false claim itself."),
        (6, "If the strongest version IS the harm, stop", "When it's built, is it an idea or a weapon?"),
        (7, "Earn your opinion", "Steelman the other side to their satisfaction before stating yours."),
        (8, "Meet the strongest rebuttal", "A steelman that dodges the hard objection is a nicer strawman."),
    ]

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text("Hear one side, then the other, before that side again. Discover enforces the alternation. Answers are AI-scored for lean + profanity.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Section("Steelmanning rules") {
                    ForEach(rules, id: \.0) { rule in
                        VStack(alignment: .leading, spacing: 4) {
                            Text("\(rule.0). \(rule.1)")
                                .font(.headline)
                            Text(rule.2)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 2)
                    }
                }

                if GitInfo.shortHash != "unknown" {
                    Section {
                        Text("Build \(GitInfo.shortHash) · \(GitInfo.branch)")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                }
            }
            .navigationTitle("Rules")
        }
    }
}

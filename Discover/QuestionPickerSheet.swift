import SwiftUI

/// The question list behind the toolbar icon. Deliberately says nothing about the answers
/// themselves — just what's being asked and how many answers are waiting. Picking one
/// switches the feed to that question, starting from its question card.
struct QuestionPickerSheet: View {
    @ObservedObject var questions: QuestionStore
    @ObservedObject var answers: AnswerStore
    let currentQuestionID: UUID?
    let onSelect: (UUID) -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List(questions.questions) { question in
                Button {
                    onSelect(question.id)
                    dismiss()
                } label: {
                    row(for: question)
                }
            }
            .listStyle(.plain)
            .navigationTitle("Questions")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .safeAreaInset(edge: .bottom) { buildStamp }
        }
        .presentationDetents([.medium, .large])
    }

    private func row(for question: Question) -> some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(question.prompt)
                    .font(.headline)
                    .foregroundStyle(.primary)
                    .multilineTextAlignment(.leading)
                Text(answerCountText(for: question))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 0)

            if question.id == currentQuestionID {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(SteelmanTheme.accent)
                    .accessibilityLabel("Now playing")
            }
        }
        .padding(.vertical, 6)
    }

    private func answerCountText(for question: Question) -> String {
        let count = answers.answers(for: question.id).count
        switch count {
        case 0: return "No answers yet"
        case 1: return "1 answer"
        default: return "\(count) answers"
        }
    }

    /// The build stamp used to live on the Rules tab; the tabs are gone, so it lives here.
    @ViewBuilder
    private var buildStamp: some View {
        if GitInfo.shortHash != "unknown" {
            Text("Build \(GitInfo.shortHash) · \(GitInfo.branch)")
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .background(.bar)
        }
    }
}

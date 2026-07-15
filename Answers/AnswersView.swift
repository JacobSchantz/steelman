import SwiftUI

/// The **Answers** tab — everything you've said, in one place.
///
/// The Discover feed plays answers *at* you one question at a time; this is the other view of
/// the same corpus: a flat, editable list of every answer, a statistics header that sums them
/// up, and a thumbs up/down on each one. Tapping an answer opens the editor; the Feed tab is a
/// tap away for going back to listening.
struct AnswersView: View {
    @ObservedObject var questions: QuestionStore
    @ObservedObject var answers: AnswerStore

    @State private var editingAnswer: Answer?

    /// Answers grouped by their question, newest question activity first, so the list reads as
    /// "here's what you said about X, and about Y" rather than one undifferentiated stream.
    private var groups: [AnswerGroup] {
        let byQuestion = Dictionary(grouping: answers.answers, by: \.questionId)
        return byQuestion.compactMap { questionId, items -> AnswerGroup? in
            guard let question = questions.question(id: questionId) else { return nil }
            let sorted = items.sorted { $0.createdAt > $1.createdAt }
            return AnswerGroup(question: question, answers: sorted)
        }
        .sorted { ($0.answers.first?.createdAt ?? .distantPast) > ($1.answers.first?.createdAt ?? .distantPast) }
    }

    var body: some View {
        NavigationStack {
            Group {
                if answers.answers.isEmpty {
                    emptyState
                } else {
                    List {
                        Section {
                            AnswerStatsView(stats: AnswerStats(answers: answers.answers, questions: questions))
                                .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                        }

                        ForEach(groups) { group in
                            Section {
                                ForEach(group.answers) { answer in
                                    Button {
                                        editingAnswer = answer
                                    } label: {
                                        AnswerListRow(
                                            answer: answer,
                                            question: group.question,
                                            onReact: { toggleReaction($0, on: answer) }
                                        )
                                    }
                                    .buttonStyle(.plain)
                                }
                                .onDelete { offsets in
                                    delete(offsets, in: group)
                                }
                            } header: {
                                Text(group.question.prompt)
                                    .font(.subheadline.weight(.semibold))
                                    .textCase(nil)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Answers")
            .sheet(item: $editingAnswer) { answer in
                EditAnswerView(questions: questions, answers: answers, answer: answer)
            }
        }
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label("No answers yet", systemImage: "text.bubble")
        } description: {
            Text("Answer a question from the Feed tab and it shows up here, where you can edit it, see how your answers break down, and give each one a thumbs up or down.")
        }
    }

    /// A thumbs press toggles: tapping the reaction you already have clears it, otherwise it
    /// replaces whatever was there.
    private func toggleReaction(_ reaction: AnswerReaction, on answer: Answer) {
        let next = answer.reaction == reaction ? nil : reaction
        answers.setReaction(next, for: answer.id)
    }

    private func delete(_ offsets: IndexSet, in group: AnswerGroup) {
        for index in offsets {
            answers.delete(group.answers[index])
        }
    }
}

/// One question and every answer you've given it, for a section of the list.
private struct AnswerGroup: Identifiable {
    let question: Question
    let answers: [Answer]
    var id: UUID { question.id }
}

/// A single answer in the list: which side it landed on, the text, and the thumbs up/down.
private struct AnswerListRow: View {
    let answer: Answer
    let question: Question
    let onReact: (AnswerReaction) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                if let side = answer.resolvedSide {
                    Text(question.label(for: side))
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(SteelmanTheme.color(for: side).opacity(0.18), in: Capsule())
                        .foregroundStyle(SteelmanTheme.color(for: side))
                }
                if answer.hasAudio {
                    Image(systemName: "waveform")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if answer.analysis?.containsProfanity == true {
                    Text("Profanity")
                        .font(.caption2.weight(.semibold))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(SteelmanTheme.danger.opacity(0.15), in: Capsule())
                        .foregroundStyle(SteelmanTheme.danger)
                }
                Spacer()
                Text(answer.createdAt.formatted(date: .abbreviated, time: .omitted))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            Text(answer.text)
                .font(.subheadline)
                .foregroundStyle(.primary)
                .lineLimit(3)

            HStack(spacing: 20) {
                reactionButton(.like, filled: "hand.thumbsup.fill", hollow: "hand.thumbsup", tint: SteelmanTheme.accent)
                reactionButton(.dislike, filled: "hand.thumbsdown.fill", hollow: "hand.thumbsdown", tint: SteelmanTheme.danger)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
    }

    private func reactionButton(_ reaction: AnswerReaction, filled: String, hollow: String, tint: Color) -> some View {
        let isOn = answer.reaction == reaction
        return Button {
            onReact(reaction)
        } label: {
            Image(systemName: isOn ? filled : hollow)
                .font(.body)
                .foregroundStyle(isOn ? tint : Color.secondary)
        }
        // The row itself is a button (opens the editor); without this the tap would fall
        // through to the row instead of toggling the reaction.
        .buttonStyle(.borderless)
        .accessibilityLabel(reaction == .like ? "Like" : "Dislike")
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }
}

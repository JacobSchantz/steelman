import SwiftUI

/// Edit one answer: change its text, re-run the AI lean/profanity analysis, and see the
/// per-answer statistics (which side it lands on, confidence, when you wrote it, your
/// reaction). Reached by tapping an answer in the Answers tab.
struct EditAnswerView: View {
    @ObservedObject var questions: QuestionStore
    @ObservedObject var answers: AnswerStore
    /// The answer as it was when the sheet opened. Edits are staged locally and only written
    /// back to the store on Save.
    let answer: Answer

    @Environment(\.dismiss) private var dismiss
    @StateObject private var analysisService = AnswerAnalysisService()

    @State private var text: String
    @State private var reaction: AnswerReaction?
    @State private var analysis: AnswerAnalysis?
    @State private var statusMessage: String?

    init(questions: QuestionStore, answers: AnswerStore, answer: Answer) {
        self.questions = questions
        self.answers = answers
        self.answer = answer
        _text = State(initialValue: answer.text)
        _reaction = State(initialValue: answer.reaction)
        _analysis = State(initialValue: answer.analysis)
    }

    private var question: Question? { questions.question(id: answer.questionId) }

    private var trimmed: String { text.trimmingCharacters(in: .whitespacesAndNewlines) }

    private var isDirty: Bool {
        trimmed != answer.text.trimmingCharacters(in: .whitespacesAndNewlines) || reaction != answer.reaction
    }

    var body: some View {
        NavigationStack {
            Form {
                if let question {
                    Section("Question") {
                        Text(question.prompt).font(.headline)
                    }
                }

                Section {
                    TextField("Your answer…", text: $text, axis: .vertical)
                        .lineLimit(6...20)
                } header: {
                    Text("Answer")
                } footer: {
                    Text("Editing the text doesn't re-run the AI on its own — tap Re-analyze if you want the side and profanity flag recomputed.")
                }

                Section("Your reaction") {
                    Picker("Reaction", selection: $reaction) {
                        Label("Like", systemImage: "hand.thumbsup").tag(AnswerReaction?.some(.like))
                        Label("None", systemImage: "circle.slash").tag(AnswerReaction?.none)
                        Label("Dislike", systemImage: "hand.thumbsdown").tag(AnswerReaction?.some(.dislike))
                    }
                    .pickerStyle(.segmented)
                }

                statisticsSection

                Section {
                    Button {
                        Task { await reanalyze() }
                    } label: {
                        if analysisService.isLoading {
                            HStack { ProgressView(); Text("Analyzing…") }
                        } else {
                            Label("Re-analyze", systemImage: "sparkles")
                        }
                    }
                    .disabled(analysisService.isLoading || trimmed.isEmpty)
                }

                if let statusMessage {
                    Section { Text(statusMessage).foregroundStyle(.secondary) }
                }
            }
            .navigationTitle("Edit answer")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .disabled(trimmed.isEmpty || (!isDirty && analysis == answer.analysis))
                }
            }
        }
    }

    /// Per-answer statistics: what the AI made of it, and the bookkeeping around it.
    @ViewBuilder
    private var statisticsSection: some View {
        Section("Statistics") {
            if let analysis, let question {
                LabeledContent("AI lean", value: question.label(for: analysis.leanSide))
                LabeledContent("Confidence", value: "\(Int(analysis.leanConfidence * 100))%")
                LabeledContent("Profanity", value: analysis.containsProfanity ? "Flagged" : "Clean")
            } else {
                LabeledContent("AI lean", value: "Not analyzed")
            }
            LabeledContent("Words", value: "\(wordCount)")
            LabeledContent("Created", value: answer.createdAt.formatted(date: .abbreviated, time: .shortened))
            LabeledContent("Audio", value: answer.hasAudio ? "Yes" : "Text only")
        }
    }

    private var wordCount: Int {
        trimmed.split { $0 == " " || $0 == "\n" || $0 == "\t" }.count
    }

    private func reanalyze() async {
        guard let question, !trimmed.isEmpty else { return }
        statusMessage = nil
        let result = await analysisService.analyze(question: question, text: trimmed, claimedSide: answer.claimedSide)
        analysis = result
        statusMessage = "Re-analyzed · lean \(question.label(for: result.leanSide)) (\(Int(result.leanConfidence * 100))%)"
            + (result.containsProfanity ? " · profanity flagged" : "")
    }

    private func save() {
        var updated = answer
        updated.text = trimmed
        updated.reaction = reaction
        updated.analysis = analysis
        answers.save(updated)
        dismiss()
    }
}

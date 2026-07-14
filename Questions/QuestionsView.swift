import SwiftUI

struct QuestionsView: View {
    @ObservedObject var questions: QuestionStore
    @ObservedObject var answers: AnswerStore
    @State private var showingNew = false

    var body: some View {
        NavigationStack {
            List {
                ForEach(questions.questions) { q in
                    NavigationLink {
                        QuestionDetailView(question: q, answers: answers)
                    } label: {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(q.prompt)
                                .font(.headline)
                                .lineLimit(3)
                            HStack(spacing: 8) {
                                sideChip(q.sideALabel, color: SteelmanTheme.sideA)
                                sideChip(q.sideBLabel, color: SteelmanTheme.sideB)
                            }
                            Text("\(answers.answers(for: q.id).count) answers")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 4)
                    }
                }
                .onDelete { indexSet in
                    for i in indexSet {
                        questions.delete(questions.questions[i])
                    }
                }
            }
            .navigationTitle("Questions")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button { showingNew = true } label: {
                        Image(systemName: "plus.circle.fill")
                    }
                }
            }
            .sheet(isPresented: $showingNew) {
                NewQuestionSheet(store: questions)
            }
        }
    }

    private func sideChip(_ text: String, color: Color) -> some View {
        Text(text)
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(color.opacity(0.15), in: Capsule())
            .foregroundStyle(color)
            .lineLimit(1)
    }
}

struct QuestionDetailView: View {
    let question: Question
    @ObservedObject var answers: AnswerStore

    var body: some View {
        List {
            Section {
                Text(question.prompt)
                    .font(.title3.weight(.semibold))
                if !question.detail.isEmpty {
                    Text(question.detail)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                HStack {
                    Label(question.sideALabel, systemImage: "a.circle.fill")
                        .foregroundStyle(SteelmanTheme.sideA)
                    Spacer()
                    Label(question.sideBLabel, systemImage: "b.circle.fill")
                        .foregroundStyle(SteelmanTheme.sideB)
                }
                .font(.subheadline)
            }

            Section("Answers") {
                let list = answers.answers(for: question.id)
                if list.isEmpty {
                    Text("No answers yet. Submit one from the Answer tab.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(list) { answer in
                        AnswerRow(answer: answer, question: question)
                    }
                    .onDelete { offsets in
                        for i in offsets {
                            answers.delete(list[i])
                        }
                    }
                }
            }
        }
        .navigationTitle("Question")
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct AnswerRow: View {
    let answer: Answer
    let question: Question

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                if let side = answer.resolvedSide {
                    Text(question.label(for: side))
                        .font(.caption.weight(.bold))
                        .foregroundStyle(SteelmanTheme.color(for: side))
                }
                if answer.hasAudio {
                    Image(systemName: "waveform")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if answer.analysis?.containsProfanity == true {
                    Text("Profanity")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(SteelmanTheme.danger, in: Capsule())
                }
                Spacer()
                Text(answer.createdAt, style: .relative)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            Text(answer.text)
                .font(.subheadline)
                .lineLimit(4)
            if let summary = answer.analysis?.summary, !summary.isEmpty {
                Text(summary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }
}

struct NewQuestionSheet: View {
    @ObservedObject var store: QuestionStore
    @Environment(\.dismiss) private var dismiss

    @State private var prompt = ""
    @State private var sideA = ""
    @State private var sideB = ""
    @State private var detail = ""

    var body: some View {
        NavigationStack {
            Form {
                Section("Question") {
                    TextField("What are we steelmanning?", text: $prompt, axis: .vertical)
                        .lineLimit(3...8)
                    TextField("Optional context", text: $detail, axis: .vertical)
                        .lineLimit(2...5)
                }
                Section("Sides") {
                    TextField("Side A label", text: $sideA)
                    TextField("Side B label", text: $sideB)
                }
            }
            .navigationTitle("New question")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        store.add(Question(
                            prompt: prompt.trimmingCharacters(in: .whitespacesAndNewlines),
                            sideALabel: sideA.trimmingCharacters(in: .whitespacesAndNewlines),
                            sideBLabel: sideB.trimmingCharacters(in: .whitespacesAndNewlines),
                            detail: detail.trimmingCharacters(in: .whitespacesAndNewlines)
                        ))
                        dismiss()
                    }
                    .disabled(
                        prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                            || sideA.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                            || sideB.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    )
                }
            }
        }
    }
}

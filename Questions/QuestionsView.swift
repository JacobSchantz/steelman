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
    @StateObject private var dictation = OnDeviceSpeechTranscriber()

    @State private var prompt = ""

    private var trimmedPrompt: String {
        prompt.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        NavigationStack {
            Form {
                // A new question is now just the prompt itself — no sides, context, or
                // category to fill in. Type it, or speak it with the audio field below.
                Section("Question") {
                    TextField("What are we steelmanning?", text: $prompt, axis: .vertical)
                        .lineLimit(3...8)
                        .disabled(dictation.isListening)
                }

                Section {
                    if dictation.isListening {
                        Button(role: .destructive) {
                            stopDictation()
                        } label: {
                            Label("Stop recording", systemImage: "stop.circle.fill")
                        }
                        Text("Listening… \(Int(dictation.seconds))s · on-device")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        if !dictation.partialTranscript.isEmpty {
                            Text(dictation.partialTranscript)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    } else {
                        Button {
                            Task { await startDictation() }
                        } label: {
                            Label(
                                trimmedPrompt.isEmpty ? "Record question" : "Record more",
                                systemImage: "waveform.badge.mic"
                            )
                        }
                    }
                    if let err = dictation.errorMessage {
                        Text(err).font(.caption).foregroundStyle(.red)
                    }
                } header: {
                    Text("Audio")
                } footer: {
                    Text("Speak your question — on-device speech recognition fills the box above.")
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
                        if dictation.isListening { stopDictation() }
                        store.add(Question(prompt: trimmedPrompt))
                        dismiss()
                    }
                    .disabled(dictation.isListening || trimmedPrompt.isEmpty)
                }
            }
            .onChange(of: dictation.partialTranscript) { _, _ in
                guard dictation.isListening else { return }
                prompt = dictation.liveText
            }
            .onChange(of: dictation.finalTranscript) { _, _ in
                guard !dictation.isListening else { return }
                let live = dictation.liveText
                if !live.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    prompt = live
                }
            }
        }
    }

    private func startDictation() async {
        await dictation.start(prefixExistingText: prompt)
    }

    private func stopDictation() {
        dictation.stop()
        let live = dictation.liveText
        if !live.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            prompt = live
        }
    }
}

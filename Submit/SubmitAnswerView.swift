import SwiftUI
import AVFoundation

struct SubmitAnswerView: View {
    @ObservedObject var questions: QuestionStore
    @ObservedObject var answers: AnswerStore
    @ObservedObject var users: UserStore
    /// The question to open on. Discover passes the one you're currently listening to so the
    /// composer lands on it instead of defaulting to the top of the list; nil keeps the old
    /// "first question" behaviour for any other caller.
    var initialQuestionID: UUID? = nil
    /// Called after a successful save so the presenter can dismiss the composer.
    var onSaved: (() -> Void)? = nil
    @Environment(\.dismiss) private var dismiss
    @StateObject private var analysisService = AnswerAnalysisService()
    @StateObject private var dictation = OnDeviceSpeechTranscriber()

    @State private var selectedQuestionId: UUID?
    @State private var text = ""
    @State private var isSubmitting = false
    @State private var statusMessage: String?
    @State private var statusIsError = false

    private var selectedQuestion: Question? {
        if let id = selectedQuestionId {
            return questions.question(id: id)
        }
        return questions.questions.first
    }

    var body: some View {
        NavigationStack {
            Form {
                if let q = selectedQuestion {
                    Section {
                        Text(q.prompt)
                            .font(.headline)
                    } header: {
                        Text("Question")
                    }

                    Section {
                        HStack(spacing: 10) {
                            Image(systemName: "person.crop.circle.fill")
                                .foregroundStyle(users.currentUser.color)
                            Text(users.currentUser.normalizedName ?? "Unnamed")
                                .font(.subheadline.weight(.medium))
                            Spacer()
                        }
                    } header: {
                        Text("Answering as")
                    } footer: {
                        Text("Answers are attributed to the active user (change it in the Users tab). Each person gets one answer per side of a question.")
                    }

                    Section {
                        TextField("Write or dictate your strongest honest case…", text: $text, axis: .vertical)
                            .lineLimit(6...16)
                            .disabled(dictation.isListening)
                    } header: {
                        Text("Answer")
                    } footer: {
                        Text("Write or dictate your answer. AI figures out which side you land on and flags profanity; text answers play via TTS in Discover.")
                    }

                    Section("Dictate (on-device STT)") {
                        if dictation.isListening {
                            Button(role: .destructive) {
                                stopDictation()
                            } label: {
                                Label("Stop dictation", systemImage: "stop.circle.fill")
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
                                    text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                                        ? "Dictate answer"
                                        : "Dictate more",
                                    systemImage: "waveform.badge.mic"
                                )
                            }
                        }
                        if let err = dictation.errorMessage {
                            Text(err).font(.caption).foregroundStyle(.red)
                        }
                    }

                    Section {
                        Button {
                            Task { await submit(question: q) }
                        } label: {
                            if isSubmitting || analysisService.isLoading {
                                HStack {
                                    ProgressView()
                                    Text("Analyzing…")
                                }
                            } else {
                                Text("Submit & analyze")
                            }
                        }
                        .disabled(
                            isSubmitting
                                || dictation.isListening
                                || text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                        )
                    }

                    if let statusMessage {
                        Section {
                            Text(statusMessage)
                                .foregroundStyle(statusIsError ? .red : .secondary)
                        }
                    }
                } else {
                    Section {
                        Text("Add a question first.")
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle("Answer")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .onAppear {
                if selectedQuestionId == nil {
                    selectedQuestionId = initialQuestionID ?? questions.questions.first?.id
                }
            }
            .onChange(of: dictation.partialTranscript) { _, _ in
                guard dictation.isListening else { return }
                text = dictation.liveText
            }
            .onChange(of: dictation.finalTranscript) { _, _ in
                guard !dictation.isListening else { return }
                let live = dictation.liveText
                if !live.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    text = live
                }
            }
        }
    }

    private func startDictation() async {
        statusMessage = nil
        await dictation.start(prefixExistingText: text)
    }

    private func stopDictation() {
        dictation.stop()
        let live = dictation.liveText
        if !live.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            text = live
        }
    }

    private func submit(question: Question) async {
        isSubmitting = true
        statusMessage = nil
        defer { isSubmitting = false }

        if dictation.isListening {
            stopDictation()
        }

        let answerId = UUID()
        let body = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !body.isEmpty else {
            statusIsError = true
            statusMessage = "Add text or dictate an answer first."
            return
        }

        // No claimed side: the answer sheet is just a fixed question plus the answer.
        // AI classifies which side it lands on during analysis.
        let analysis = await analysisService.analyze(
            question: question,
            text: body,
            claimedSide: nil
        )

        // One answer per side, per person. The side is only known once the AI has classified
        // the text, so the limit is enforced here — after analysis, before the answer is
        // saved — against the currently active user. If they've already taken this side (which
        // also means they've hit two answers on a question once both sides are spoken for),
        // the submission is refused and the text is left in place to edit or redirect.
        let author = users.currentUser
        if answers.hasAnswered(side: analysis.leanSide, for: question.id, by: author.id) {
            statusIsError = true
            statusMessage = "\(author.normalizedName ?? "This user") already argued “\(question.label(for: analysis.leanSide))” on this question. Each person gets one answer per side — switch users or edit your existing answer."
            return
        }

        let answer = Answer(
            id: answerId,
            questionId: question.id,
            userId: author.id,
            claimedSide: nil,
            text: body,
            audioFileName: nil,
            analysis: analysis
        )
        answers.save(answer)
        dictation.reset()
        text = ""
        statusIsError = false
        statusMessage = "Saved · lean \(question.label(for: analysis.leanSide)) (\(Int(analysis.leanConfidence * 100))%)"
            + (analysis.containsProfanity ? " · profanity flagged" : "")
        // Opened from Discover: hand control back to the feed now that the answer is in the
        // deck. A standalone presentation (onSaved == nil) stays open so you can add another.
        onSaved?()
    }
}

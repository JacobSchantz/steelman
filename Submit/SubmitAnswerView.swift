import SwiftUI
import AVFoundation

struct SubmitAnswerView: View {
    @ObservedObject var questions: QuestionStore
    @ObservedObject var answers: AnswerStore
    @StateObject private var analysisService = AnswerAnalysisService()
    @StateObject private var dictation = OnDeviceSpeechTranscriber()

    @State private var selectedQuestionId: UUID?
    @State private var claimedSide: ArgumentSide = .a
    @State private var text = ""
    @State private var tokenInput = ""
    @State private var showToken = false
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
                Section {
                    if questions.questions.isEmpty {
                        Text("Add a question first.")
                            .foregroundStyle(.secondary)
                    } else {
                        Picker("Question", selection: Binding(
                            get: { selectedQuestionId ?? questions.questions.first?.id },
                            set: { selectedQuestionId = $0 }
                        )) {
                            ForEach(questions.questions) { q in
                                Text(q.prompt).lineLimit(2).tag(Optional(q.id))
                            }
                        }
                    }
                } header: {
                    Text("Question")
                }

                if let q = selectedQuestion {
                    Section("Your claimed side") {
                        Picker("Side", selection: $claimedSide) {
                            Text(q.sideALabel).tag(ArgumentSide.a)
                            Text(q.sideBLabel).tag(ArgumentSide.b)
                        }
                        .pickerStyle(.segmented)
                    }

                    Section {
                        TextField("Write or dictate your strongest honest case…", text: $text, axis: .vertical)
                            .lineLimit(6...16)
                            .disabled(dictation.isListening)
                    } header: {
                        Text("Answer")
                    } footer: {
                        Text("Dictate with on-device speech recognition (same approach as ATG). AI classifies lean + profanity. Discover alternates sides before replaying a side; text answers play via TTS.")
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
                }

                Section {
                    Button {
                        showToken = true
                    } label: {
                        Label(
                            AnswerAnalysisService.hasToken ? "OpenRouter token set" : "Add OpenRouter token",
                            systemImage: "key.fill"
                        )
                    }
                } footer: {
                    Text("Without a token, lean/profanity use a simple on-device heuristic. Token is stored in Keychain.")
                }
            }
            .navigationTitle("Answer")
            .sheet(isPresented: $showToken) {
                NavigationStack {
                    Form {
                        SecureField("sk-or-...", text: $tokenInput)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                        Button("Save") {
                            AnswerAnalysisService.apiToken = tokenInput
                            showToken = false
                        }
                        .disabled(tokenInput.trimmingCharacters(in: .whitespaces).isEmpty)
                        if AnswerAnalysisService.hasToken {
                            Button("Clear token", role: .destructive) {
                                AnswerAnalysisService.apiToken = nil
                                tokenInput = ""
                            }
                        }
                    }
                    .navigationTitle("OpenRouter")
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Close") { showToken = false }
                        }
                    }
                }
                .presentationDetents([.medium])
            }
            .onAppear {
                if selectedQuestionId == nil {
                    selectedQuestionId = questions.questions.first?.id
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

        let analysis = await analysisService.analyze(
            question: question,
            text: body,
            claimedSide: claimedSide
        )

        let answer = Answer(
            id: answerId,
            questionId: question.id,
            claimedSide: claimedSide,
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
    }
}

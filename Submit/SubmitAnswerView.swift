import SwiftUI
import AVFoundation

struct SubmitAnswerView: View {
    @ObservedObject var questions: QuestionStore
    @ObservedObject var answers: AnswerStore
    @StateObject private var analysisService = AnswerAnalysisService()
    @StateObject private var recorder = AnswerAudioRecorder()

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
                        TextField("Write your strongest honest case…", text: $text, axis: .vertical)
                            .lineLimit(6...16)
                    } header: {
                        Text("Text answer")
                    } footer: {
                        Text("AI classifies lean + profanity. Discover will alternate sides before replaying a side.")
                    }

                    Section("Audio answer (optional)") {
                        if recorder.isRecording {
                            Button(role: .destructive) {
                                recorder.stop()
                            } label: {
                                Label("Stop recording", systemImage: "stop.circle.fill")
                            }
                            Text("Recording… \(Int(recorder.seconds))s")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        } else {
                            Button {
                                Task { await recorder.start() }
                            } label: {
                                Label(
                                    recorder.fileURL == nil ? "Record audio" : "Re-record",
                                    systemImage: "mic.circle.fill"
                                )
                            }
                            if recorder.fileURL != nil {
                                Label("Audio attached", systemImage: "checkmark.circle.fill")
                                    .foregroundStyle(.green)
                                    .font(.subheadline)
                            }
                        }
                        if let err = recorder.errorMessage {
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
                                || (text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                                    && recorder.fileURL == nil)
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
        }
    }

    private func submit(question: Question) async {
        isSubmitting = true
        statusMessage = nil
        defer { isSubmitting = false }

        let answerId = UUID()
        var audioName: String?
        if let recorded = recorder.fileURL {
            let dest = answers.makeAudioFileURL(for: answerId)
            try? FileManager.default.removeItem(at: dest)
            do {
                try FileManager.default.copyItem(at: recorded, to: dest)
                audioName = dest.lastPathComponent
            } catch {
                statusIsError = true
                statusMessage = "Couldn't save audio: \(error.localizedDescription)"
                return
            }
        }

        let body = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let analysis = await analysisService.analyze(
            question: question,
            text: body.isEmpty ? "(audio-only submission)" : body,
            claimedSide: claimedSide
        )

        let answer = Answer(
            id: answerId,
            questionId: question.id,
            claimedSide: claimedSide,
            text: body.isEmpty ? analysis.summary : body,
            audioFileName: audioName,
            analysis: analysis
        )
        answers.save(answer)
        recorder.clear()
        text = ""
        statusIsError = false
        statusMessage = "Saved · lean \(question.label(for: analysis.leanSide)) (\(Int(analysis.leanConfidence * 100))%)"
            + (analysis.containsProfanity ? " · profanity flagged" : "")
    }
}

// MARK: - Recorder

@MainActor
final class AnswerAudioRecorder: NSObject, ObservableObject {
    @Published var isRecording = false
    @Published var seconds: TimeInterval = 0
    @Published var fileURL: URL?
    @Published var errorMessage: String?

    private var recorder: AVAudioRecorder?
    private var timer: Timer?
    private var tempURL: URL?

    func start() async {
        errorMessage = nil
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker])
            try session.setActive(true)
        } catch {
            errorMessage = "Mic session failed: \(error.localizedDescription)"
            return
        }

        let granted: Bool
        if #available(iOS 17.0, *) {
            granted = await AVAudioApplication.requestRecordPermission()
        } else {
            granted = await withCheckedContinuation { cont in
                session.requestRecordPermission { cont.resume(returning: $0) }
            }
        }
        guard granted else {
            errorMessage = "Microphone permission denied."
            return
        }

        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("steelman-\(UUID().uuidString).m4a")
        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
            AVSampleRateKey: 44100,
            AVNumberOfChannelsKey: 1,
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue,
        ]
        do {
            let r = try AVAudioRecorder(url: url, settings: settings)
            r.record()
            recorder = r
            tempURL = url
            fileURL = nil
            isRecording = true
            seconds = 0
            timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
                Task { @MainActor in
                    self?.seconds = self?.recorder?.currentTime ?? 0
                }
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func stop() {
        recorder?.stop()
        timer?.invalidate()
        timer = nil
        isRecording = false
        fileURL = tempURL
        recorder = nil
    }

    func clear() {
        stop()
        if let tempURL {
            try? FileManager.default.removeItem(at: tempURL)
        }
        fileURL = nil
        tempURL = nil
        seconds = 0
    }
}

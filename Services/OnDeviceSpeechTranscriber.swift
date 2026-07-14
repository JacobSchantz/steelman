import AVFoundation
import Foundation
import Speech

/// Live on-device speech-to-text, matching the ATG stack (`speech_to_text` →
/// Apple Speech / SFSpeechRecognizer with on-device recognition preferred).
///
/// Speech audio is processed on-device when `requiresOnDeviceRecognition` is
/// honored. Cloud/upload STT can replace or sit beside this later.
@MainActor
final class OnDeviceSpeechTranscriber: NSObject, ObservableObject {
    @Published private(set) var isListening = false
    @Published private(set) var partialTranscript = ""
    @Published private(set) var finalTranscript = ""
    @Published private(set) var seconds: TimeInterval = 0
    @Published private(set) var errorMessage: String?

    private let speechRecognizer: SFSpeechRecognizer?
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private let audioEngine = AVAudioEngine()
    private var timer: Timer?
    private var sessionStartedAt: Date?

    /// Text that was already in the answer field when dictation started.
    private var prefixText = ""

    override init() {
        speechRecognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
        super.init()
    }

    /// Combined live transcript suitable for binding into a text field.
    var liveText: String {
        let spoken = isListening ? partialTranscript : finalTranscript
        if prefixText.isEmpty { return spoken }
        if spoken.isEmpty { return prefixText }
        let needsSpace = !prefixText.hasSuffix(" ") && !prefixText.hasSuffix("\n")
        return prefixText + (needsSpace ? " " : "") + spoken
    }

    func start(prefixExistingText: String = "") async {
        errorMessage = nil
        partialTranscript = ""
        finalTranscript = ""
        prefixText = prefixExistingText.trimmingCharacters(in: .whitespacesAndNewlines)

        guard let speechRecognizer, speechRecognizer.isAvailable else {
            errorMessage = "Speech recognition isn’t available on this device."
            return
        }

        let speechOK = await requestSpeechAuth()
        guard speechOK else {
            errorMessage = "Speech recognition permission denied."
            return
        }

        let micOK = await requestMicAuth()
        guard micOK else {
            errorMessage = "Microphone permission denied."
            return
        }

        do {
            try configureSession()
            try beginEngineAndRecognition(recognizer: speechRecognizer)
            isListening = true
            sessionStartedAt = Date()
            seconds = 0
            timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
                Task { @MainActor in
                    guard let self, let start = self.sessionStartedAt else { return }
                    self.seconds = Date().timeIntervalSince(start)
                }
            }
        } catch {
            tearDownEngine()
            errorMessage = error.localizedDescription
        }
    }

    func stop() {
        guard isListening || recognitionTask != nil else { return }

        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)
        recognitionRequest?.endAudio()
        recognitionRequest = nil

        // Prefer the last partial if the final callback hasn’t fired yet.
        if finalTranscript.isEmpty, !partialTranscript.isEmpty {
            finalTranscript = partialTranscript
        }

        recognitionTask?.finish()
        recognitionTask = nil

        timer?.invalidate()
        timer = nil
        isListening = false

        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    func reset() {
        stop()
        partialTranscript = ""
        finalTranscript = ""
        seconds = 0
        errorMessage = nil
        prefixText = ""
    }

    // MARK: - Private

    private func requestSpeechAuth() async -> Bool {
        await withCheckedContinuation { cont in
            SFSpeechRecognizer.requestAuthorization { status in
                cont.resume(returning: status == .authorized)
            }
        }
    }

    private func requestMicAuth() async -> Bool {
        if #available(iOS 17.0, *) {
            return await AVAudioApplication.requestRecordPermission()
        }
        return await withCheckedContinuation { cont in
            AVAudioSession.sharedInstance().requestRecordPermission { cont.resume(returning: $0) }
        }
    }

    private func configureSession() throws {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playAndRecord, mode: .measurement, options: [.defaultToSpeaker, .allowBluetooth])
        try session.setActive(true, options: .notifyOthersOnDeactivation)
    }

    private func beginEngineAndRecognition(recognizer: SFSpeechRecognizer) throws {
        recognitionTask?.cancel()
        recognitionTask = nil

        let request = SFSpeechAudioBufferRecognitionRequest()
        // Prefer fully on-device (no upload). Fall back if the device can’t.
        if recognizer.supportsOnDeviceRecognition {
            request.requiresOnDeviceRecognition = true
        }
        request.shouldReportPartialResults = true
        request.taskHint = .dictation
        recognitionRequest = request

        let input = audioEngine.inputNode
        let format = input.outputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0 else {
            throw TranscriberError.invalidAudioFormat
        }

        // Capture for the realtime tap — do not hop to MainActor from the audio thread.
        let requestForTap = request

        input.removeTap(onBus: 0)
        input.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in
            requestForTap.append(buffer)
        }

        audioEngine.prepare()
        try audioEngine.start()

        recognitionTask = recognizer.recognitionTask(with: request) { [weak self] result, error in
            Task { @MainActor in
                guard let self else { return }
                if let result {
                    let text = result.bestTranscription.formattedString
                    self.partialTranscript = text
                    if result.isFinal {
                        self.finalTranscript = text
                    }
                }
                if let error {
                    // Ignore cancellation noise when the user stops intentionally.
                    let ns = error as NSError
                    if ns.domain == "kAFAssistantErrorDomain", ns.code == 216 || ns.code == 1110 {
                        return
                    }
                    if self.isListening {
                        self.errorMessage = error.localizedDescription
                    }
                }
            }
        }
    }

    private func tearDownEngine() {
        if audioEngine.isRunning {
            audioEngine.stop()
        }
        audioEngine.inputNode.removeTap(onBus: 0)
        recognitionRequest?.endAudio()
        recognitionRequest = nil
        recognitionTask?.cancel()
        recognitionTask = nil
        timer?.invalidate()
        timer = nil
        isListening = false
    }

    enum TranscriberError: LocalizedError {
        case invalidAudioFormat

        var errorDescription: String? {
            switch self {
            case .invalidAudioFormat:
                return "Couldn’t open the microphone audio format."
            }
        }
    }
}

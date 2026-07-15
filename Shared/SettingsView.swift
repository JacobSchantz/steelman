import SwiftUI

/// The settings sheet, opened from the toolbar gear.
///
/// Everything here controls how the feed reads to you. Four things live in it now:
/// - the **voice engine** — the neural Kokoro voice or Apple's system voice (a real choice,
///   since Kokoro is a 351 MB download some listeners would rather skip);
/// - the **voice** — which Kokoro speaker reads, when the neural engine is on;
/// - the **reading speed** — takes effect on the current card immediately (see
///   `DiscoverView`'s `onChange`) and on every card after it;
/// - the **voice model** — the download status of the on-device weights, with a way to
///   start the download or watch its progress.
struct SettingsView: View {
    @ObservedObject var settings: SpeechSettings
    @ObservedObject private var models = KokoroModelStore.shared
    @StateObject private var preview = VoicePreviewPlayer()
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                engineSection
                if settings.engine == .kokoro {
                    voiceSection
                }
                speedSection
                modelSection
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            // Stop auditioning when the sheet closes or the voice list is hidden, so a sample
            // never keeps playing over the feed after you leave.
            .onDisappear { preview.stop() }
            .onChange(of: settings.engine) { _, _ in preview.stop() }
        }
    }

    // MARK: - Sections

    private var engineSection: some View {
        Section {
            Picker("Voice engine", selection: $settings.engine) {
                ForEach(SpeechEngine.allCases) { engine in
                    Text(engine.title).tag(engine)
                }
            }
            .pickerStyle(.inline)
        } header: {
            Text("Voice engine")
        } footer: {
            Text(settings.engine.detail)
        }
    }

    /// An inline, tappable list rather than a `navigationLink` picker: the point is to
    /// *hear* a voice before choosing it, and a push-then-pop picker makes auditioning
    /// several voices tedious. Here each tap both selects the voice and plays a short sample
    /// in it, so flicking down the list is exactly the "preview before deciding" flow the
    /// request asks for.
    private var voiceSection: some View {
        Section {
            ForEach(SpeechSettings.voices) { voice in
                voiceRow(voice)
            }
        } header: {
            Text("Voice")
        } footer: {
            Text(voiceFooter)
        }
    }

    private func voiceRow(_ voice: KokoroVoice) -> some View {
        Button {
            settings.voiceID = voice.id
            preview.preview(voice)
        } label: {
            HStack(spacing: 12) {
                voicePreviewIcon(for: voice)
                VStack(alignment: .leading, spacing: 2) {
                    Text(voice.name)
                        .foregroundStyle(.primary)
                    Text(voice.detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if settings.voiceID == voice.id {
                    Image(systemName: "checkmark")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(.tint)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    /// Leading affordance: a speaker glyph you can tap to hear the voice, a filled/animated
    /// one while it's sounding, and a spinner while Kokoro is still rendering the sample.
    @ViewBuilder
    private func voicePreviewIcon(for voice: KokoroVoice) -> some View {
        Group {
            if preview.preparingVoiceID == voice.id {
                ProgressView()
                    .controlSize(.small)
            } else if preview.playingVoiceID == voice.id {
                Image(systemName: "speaker.wave.2.fill")
                    .foregroundStyle(.tint)
                    .symbolEffect(.variableColor.iterative, options: .repeating)
            } else {
                Image(systemName: "speaker.wave.2")
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: 24)
    }

    private var voiceFooter: String {
        let base = "Tap a voice to hear a sample. Changing it takes effect on the next card."
        guard VoicePreviewPlayer.canPreviewDistinctVoices else {
            return "Tap a voice to hear a sample. Until the voice model finishes downloading, "
                + "samples use the system voice and sound the same. Changing the voice takes "
                + "effect on the next card."
        }
        return base
    }

    private var speedSection: some View {
        Section {
            Picker("Reading speed", selection: $settings.speed) {
                ForEach(SpeechSettings.speedOptions, id: \.self) { speed in
                    Text(Self.label(for: speed)).tag(speed)
                }
            }
        } header: {
            Text("Reading speed")
        } footer: {
            Text("How fast the voice reads each question and answer aloud.")
        }
    }

    /// The download status of each voice model. Only Kokoro-82M ships today, but the row is
    /// per-model so a second model would simply add another row here.
    private var modelSection: some View {
        Section {
            modelRow
        } header: {
            Text("Voice model")
        } footer: {
            Text("The neural voice runs on-device. Until it finishes downloading, the system voice reads the feed.")
        }
    }

    @ViewBuilder
    private var modelRow: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Kokoro-82M")
                    Text(KokoroModel.displaySize)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                modelStatus
            }
            if let progress = models.progress {
                ProgressView(value: progress)
                    .progressViewStyle(.linear)
            }
        }
    }

    @ViewBuilder
    private var modelStatus: some View {
        if models.isReady {
            Label("Installed", systemImage: "checkmark.circle.fill")
                .labelStyle(.titleAndIcon)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.green)
        } else if let progress = models.progress {
            Text("Downloading… \(Int(progress * 100))%")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        } else {
            Button("Download") { models.ensureDownloaded() }
                .font(.subheadline.weight(.medium))
        }
    }

    /// 1.0 → "1×", 1.25 → "1.25×": trim a trailing ".0" so whole speeds read cleanly.
    private static func label(for speed: Double) -> String {
        let text = speed == speed.rounded() ? String(Int(speed)) : String(speed)
        return "\(text)×"
    }
}

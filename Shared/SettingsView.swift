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

    private var voiceSection: some View {
        Section {
            Picker("Voice", selection: $settings.voiceID) {
                ForEach(SpeechSettings.voices) { voice in
                    VStack(alignment: .leading) {
                        Text(voice.name)
                        Text(voice.detail)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .tag(voice.id)
                }
            }
            .pickerStyle(.navigationLink)
        } header: {
            Text("Voice")
        } footer: {
            Text("The speaker Kokoro uses. Changing it takes effect on the next card.")
        }
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

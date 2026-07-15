import SwiftUI

/// The settings sheet, opened from the toolbar gear.
///
/// Deliberately small: it controls how the feed reads to you, and nothing else lives here
/// yet. The one control is reading speed; changing it takes effect on the current card
/// immediately (see `DiscoverView`'s `onChange`) and on every card after it.
struct SettingsView: View {
    @ObservedObject var settings: SpeechSettings
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Reading speed", selection: $settings.speed) {
                        ForEach(SpeechSettings.speedOptions, id: \.self) { speed in
                            Text(Self.label(for: speed)).tag(speed)
                        }
                    }
                } header: {
                    Text("Speech")
                } footer: {
                    Text("How fast the voice reads each question and answer aloud.")
                }
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

    /// 1.0 → "1×", 1.25 → "1.25×": trim a trailing ".0" so whole speeds read cleanly.
    private static func label(for speed: Double) -> String {
        let text = speed == speed.rounded() ? String(Int(speed)) : String(speed)
        return "\(text)×"
    }
}

import SwiftUI

/// The listener-controlled speech settings, surfaced by the toolbar's gear.
///
/// The one knob today is **reading speed** — how fast the voice reads a question or an
/// answer aloud. It flows into both speech paths in `ClipPreviewPlayer`: `AVPlayer.defaultRate`
/// for Kokoro-rendered and recorded audio, and `AVSpeechUtterance.rate` for the fallback
/// voice. Persisted to `UserDefaults`, so the pace the listener picked survives a launch.
///
/// A shared singleton because both the settings sheet (which writes it) and the player
/// (which reads it at play time) need the same value, and there's only ever one listener.
@MainActor
final class SpeechSettings: ObservableObject {
    static let shared = SpeechSettings()

    /// Multiplier on the natural reading pace. 1.0 is normal; 2.0 is twice as fast.
    @Published var speed: Double {
        didSet {
            guard speed != oldValue else { return }
            UserDefaults.standard.set(speed, forKey: Self.speedKey)
        }
    }

    /// The speeds the picker offers — the familiar podcast-app steps, rather than a free
    /// slider that could land on a rate the fallback voice can't actually speak.
    static let speedOptions: [Double] = [0.75, 1.0, 1.25, 1.5, 2.0]

    private static let speedKey = "speech.speed"

    private init() {
        let saved = UserDefaults.standard.double(forKey: Self.speedKey)
        // `double(forKey:)` returns 0 for a key that was never set — fall back to natural pace.
        speed = saved > 0 ? saved : 1.0
    }
}

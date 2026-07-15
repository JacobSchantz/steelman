import SwiftUI

/// One of the on-device Kokoro speakers. The `id` is the sherpa-onnx speaker index the
/// engine actually renders with; the rest is how the picker names it to a listener.
///
/// These eleven embeddings all live inside the single `voices.bin` weight, so switching
/// between them costs nothing to download — it just re-renders upcoming cards with a new
/// timbre. `af_*` is American female, `am_*` American male, `bf_*`/`bm_*` British.
struct KokoroVoice: Identifiable, Hashable {
    let id: Int32
    let name: String
    /// Accent + gender, shown under the name so the list reads at a glance.
    let detail: String
}

/// Which speech engine reads the feed. Kokoro sounds far better but is a ~351 MB download;
/// the system voice is always there and needs nothing, so a listener on a metered
/// connection or a tight storage budget can opt out of the download entirely.
enum SpeechEngine: String, CaseIterable, Identifiable {
    /// Kokoro-82M, rendered on-device. The default, and what the download machinery serves.
    case kokoro
    /// Apple's built-in `AVSpeechSynthesizer`. No download, lower quality.
    case system

    var id: String { rawValue }

    var title: String {
        switch self {
        case .kokoro: return "Natural (Kokoro-82M)"
        case .system: return "System voice"
        }
    }

    var detail: String {
        switch self {
        case .kokoro: return "On-device neural voice. Best quality, one-time 351 MB download."
        case .system: return "Apple's built-in voice. Always available, no download."
        }
    }
}

/// The listener-controlled speech settings, surfaced by the toolbar's gear.
///
/// Three knobs today: which **engine** reads the feed (neural Kokoro vs. the system voice),
/// which Kokoro **voice** it uses, and the **reading speed**. Speed flows into both speech
/// paths in `ClipPreviewPlayer` (`AVPlayer.defaultRate` for rendered/recorded audio,
/// `AVSpeechUtterance.rate` for the fallback). Engine and voice steer `SpeechRenderer`:
/// the voice is part of the render's cache key, so each speaker caches separately and a
/// switch just changes how the *next* cards sound. All three persist to `UserDefaults`,
/// so the listener's choices survive a launch.
///
/// A shared singleton because the settings sheet (which writes it), the player, and the
/// prefetch (which both read it at play time) need the same value, and there's only ever
/// one listener.
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

    /// Which engine reads the feed. Persisted so an opt-out of the Kokoro download sticks.
    @Published var engine: SpeechEngine {
        didSet {
            guard engine != oldValue else { return }
            UserDefaults.standard.set(engine.rawValue, forKey: Self.engineKey)
        }
    }

    /// The chosen Kokoro speaker id. Only meaningful when `engine == .kokoro`; the system
    /// voice has no speaker to pick.
    @Published var voiceID: Int32 {
        didSet {
            guard voiceID != oldValue else { return }
            UserDefaults.standard.set(Int(voiceID), forKey: Self.voiceKey)
        }
    }

    /// The speeds the picker offers — the familiar podcast-app steps, rather than a free
    /// slider that could land on a rate the fallback voice can't actually speak.
    static let speedOptions: [Double] = [0.75, 1.0, 1.25, 1.5, 2.0]

    /// The eleven speakers baked into `voices.bin`, in the model's own index order.
    static let voices: [KokoroVoice] = [
        KokoroVoice(id: 0,  name: "Aria",     detail: "US · Female"),
        KokoroVoice(id: 1,  name: "Bella",    detail: "US · Female"),
        KokoroVoice(id: 2,  name: "Nicole",   detail: "US · Female"),
        KokoroVoice(id: 3,  name: "Sarah",    detail: "US · Female"),
        KokoroVoice(id: 4,  name: "Sky",      detail: "US · Female"),
        KokoroVoice(id: 5,  name: "Adam",     detail: "US · Male"),
        KokoroVoice(id: 6,  name: "Michael",  detail: "US · Male"),
        KokoroVoice(id: 7,  name: "Emma",     detail: "UK · Female"),
        KokoroVoice(id: 8,  name: "Isabella", detail: "UK · Female"),
        KokoroVoice(id: 9,  name: "George",   detail: "UK · Male"),
        KokoroVoice(id: 10, name: "Lewis",    detail: "UK · Male"),
    ]

    /// Kept as the default because it's the voice Steelman shipped with before there was a
    /// picker — existing listeners hear no change until they choose otherwise.
    static let defaultVoiceID: Int32 = 5

    /// The `KokoroVoice` for the current `voiceID`, falling back to the default if a stored
    /// id ever goes stale (e.g. the voice list shrinks in a later build).
    var voice: KokoroVoice {
        Self.voices.first { $0.id == voiceID } ?? Self.voices.first { $0.id == Self.defaultVoiceID }!
    }

    private static let speedKey = "speech.speed"
    private static let engineKey = "speech.engine"
    private static let voiceKey = "speech.voiceID"

    private init() {
        let savedSpeed = UserDefaults.standard.double(forKey: Self.speedKey)
        // `double(forKey:)` returns 0 for a key that was never set — fall back to natural pace.
        speed = savedSpeed > 0 ? savedSpeed : 1.0

        // A missing engine key reads as nil → default to the neural voice, matching the
        // behaviour before this setting existed.
        engine = UserDefaults.standard.string(forKey: Self.engineKey)
            .flatMap(SpeechEngine.init(rawValue:)) ?? .kokoro

        // `object(forKey:)` distinguishes "never set" (nil) from a stored 0, so voice index 0
        // isn't mistaken for the unset default.
        if let stored = UserDefaults.standard.object(forKey: Self.voiceKey) as? Int {
            voiceID = Int32(stored)
        } else {
            voiceID = Self.defaultVoiceID
        }
    }
}

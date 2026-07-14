import Foundation
import CryptoKit

/// Turns an argument's text into a real audio file, spoken by Kokoro-82M on-device.
///
/// The point of rendering to a *file* rather than streaming straight to the speaker is
/// that it collapses the two playback paths in `ClipPreviewPlayer` into one. Spoken text
/// becomes an ordinary WAV on disk, so it plays through the same `AVPlayer` code that
/// recorded answers do — which means a real duration, a real scrubber, and a real
/// end-of-playback signal, instead of the character-counting estimates the
/// AVSpeechSynthesizer path has to fake. The "you must hear this all the way through"
/// rule gets to key off actual audio.
///
/// Synthesis is slow (a long argument can take seconds), so nothing waits for it on the
/// hot path: `DiscoverView` renders the next few cards while you're listening to the
/// current one, and anything not ready in time is spoken by AVSpeechSynthesizer instead.
/// The app is never silent because Kokoro isn't ready — it just sounds better once it is.
actor SpeechRenderer {
    static let shared = SpeechRenderer()

    /// Kokoro speaker 5 is "Adam" — a US male voice. Kept as a constant rather than a
    /// setting because there's no voice picker in Steelman yet.
    private static let speakerID: Int32 = 5
    private static let speed: Float = 1.0

    private let engine = KokoroEngine()
    /// Renders already running, keyed by cache key, so two cards asking for the same text
    /// (or a prefetch racing the player) synthesize it once and share the result.
    private var inFlight: [String: Task<URL?, Never>] = [:]

    private init() {}

    /// Whether Kokoro can actually speak right now: the native backend is linked *and* the
    /// weights have finished downloading. False on either count means callers fall back.
    nonisolated static var isAvailable: Bool {
        KokoroTTSBridge.isBackendAvailable() && KokoroModel.isInstalled
    }

    // MARK: - Cache

    private static var cacheDirectory: URL {
        let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        let dir = base.appendingPathComponent("SpokenText", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    /// Same text + same voice + same speed always maps to the same file, so a re-listen or
    /// a deck rebuild reuses what we already synthesized.
    private static func cacheKey(for text: String) -> String {
        let normalized = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let seed = "\(speakerID)|\(speed)|\(normalized)"
        let digest = SHA256.hash(data: Data(seed.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    /// The rendered file for `text`, or nil if it hasn't been synthesized yet. Cheap and
    /// synchronous — `ClipPreviewPlayer` calls it on the main thread to decide, without
    /// awaiting anything, whether it can go straight down the audio path.
    nonisolated static func cachedURL(for text: String) -> URL? {
        let url = cacheDirectory.appendingPathComponent("\(cacheKey(for: text)).wav")
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    /// Throw away a rendered file that turned out to be unplayable, so the next request
    /// synthesizes it again instead of handing AVPlayer the same broken WAV forever.
    nonisolated static func discardRender(for text: String) {
        guard let url = cachedURL(for: text) else { return }
        try? FileManager.default.removeItem(at: url)
    }

    // MARK: - Rendering

    /// Synthesize `text` to a cached WAV and return it, or nil if Kokoro can't speak it.
    /// Never throws: every failure path (backend missing, weights absent, synthesis error)
    /// returns nil so the caller can fall back to AVSpeechSynthesizer.
    func render(_ text: String) async -> URL? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        if let existing = Self.cachedURL(for: trimmed) { return existing }
        guard Self.isAvailable else { return nil }

        let key = Self.cacheKey(for: trimmed)
        if let running = inFlight[key] { return await running.value }

        let task = Task<URL?, Never> { [engine] in
            guard let pcm = await engine.synthesize(trimmed,
                                                    speaker: Self.speakerID,
                                                    speed: Self.speed) else { return nil }
            let url = Self.cacheDirectory.appendingPathComponent("\(key).wav")
            // Write to a sibling temp file and move it into place, so a cancelled or
            // crashed render can't leave a truncated WAV that `cachedURL` would then
            // happily hand to AVPlayer.
            let temp = url.appendingPathExtension("partial")
            do {
                try pcm.wav.write(to: temp, options: .atomic)
                try? FileManager.default.removeItem(at: url)
                try FileManager.default.moveItem(at: temp, to: url)
            } catch {
                try? FileManager.default.removeItem(at: temp)
                return nil
            }
            Self.evictIfNeeded()
            return url
        }
        inFlight[key] = task
        let url = await task.value
        inFlight[key] = nil
        return url
    }

    /// Keep the rendered-speech cache under budget, oldest first. Speech is ~48 KB/sec, so
    /// this holds roughly an hour of audio before it starts recycling.
    private static let maxCacheBytes: Int64 = 150 * 1024 * 1024

    private nonisolated static func evictIfNeeded() {
        let fm = FileManager.default
        guard let entries = try? fm.contentsOfDirectory(
            at: cacheDirectory,
            includingPropertiesForKeys: [.contentModificationDateKey, .fileSizeKey]
        ) else { return }

        var files = entries.compactMap { url -> (URL, Date, Int64)? in
            guard let values = try? url.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey]),
                  let date = values.contentModificationDate,
                  let size = values.fileSize else { return nil }
            return (url, date, Int64(size))
        }
        var total = files.reduce(Int64(0)) { $0 + $1.2 }
        guard total > maxCacheBytes else { return }

        files.sort { $0.1 < $1.1 }
        for (url, _, size) in files {
            guard total > maxCacheBytes else { break }
            try? fm.removeItem(at: url)
            total -= size
        }
    }
}

/// Owns the one resident Kokoro engine and serializes synthesis onto a dedicated thread.
///
/// It's a `DispatchQueue` rather than an actor on purpose: `generate` is a blocking C++
/// call that can run for seconds, and parking a Swift-concurrency cooperative thread that
/// long can starve the pool. This keeps the stall on a thread of our own.
private final class KokoroEngine: @unchecked Sendable {
    struct PCM { let wav: Data }

    private let bridge = KokoroTTSBridge()
    private let queue = DispatchQueue(label: "com.steelman.kokoro", qos: .userInitiated)
    private var loaded = false

    func synthesize(_ text: String, speaker: Int32, speed: Float) async -> PCM? {
        await withCheckedContinuation { continuation in
            queue.async { [self] in
                continuation.resume(returning: renderOnQueue(text, speaker: speaker, speed: speed))
            }
        }
    }

    /// Must only run on `queue` — the bridge is not thread-safe.
    private func renderOnQueue(_ text: String, speaker: Int32, speed: Float) -> PCM? {
        do {
            try ensureLoaded()
            var sampleRate: Int32 = 24_000
            let samples = try bridge.generate(forText: text,
                                              speakerId: speaker,
                                              speed: speed,
                                              sampleRate: &sampleRate)
            guard !samples.isEmpty else { return nil }
            return PCM(wav: Self.makeWAV(floatSamples: samples, sampleRate: Int(sampleRate)))
        } catch {
            print("[SpeechRenderer] synthesis failed: \(error)")
            return nil
        }
    }

    private func ensureLoaded() throws {
        if loaded, bridge.isLoaded { return }
        // tokens.txt + espeak-ng-data ship in the bundle as a *folder reference*; sherpa-onnx
        // needs data_dir to be a real directory, so it can't be a flattened resource group.
        guard let assets = Bundle.main.url(forResource: "KokoroAssets", withExtension: nil) else {
            // NS_ERROR_ENUM imports as a nested Code type, not a flat name.
            throw NSError(domain: KokoroTTSErrorDomain,
                          code: KokoroTTSError.Code.modelLoadFailed.rawValue,
                          userInfo: [NSLocalizedDescriptionKey: "KokoroAssets missing from the app bundle."])
        }
        try bridge.load(withModelPath: KokoroModel.modelPath,
                        voicesPath: KokoroModel.voicesPath,
                        tokensPath: assets.appendingPathComponent("tokens.txt").path,
                        dataDir: assets.appendingPathComponent("espeak-ng-data").path)
        loaded = true
    }

    /// Wrap Kokoro's mono Float32 PCM in a 16-bit WAV. The header is what lets the result
    /// be an ordinary audio file that `AVPlayer` opens with no special handling.
    private static func makeWAV(floatSamples: Data, sampleRate: Int) -> Data {
        let count = floatSamples.count / MemoryLayout<Float>.size
        var pcm = Data(capacity: count * 2)
        floatSamples.withUnsafeBytes { raw in
            let floats = raw.bindMemory(to: Float.self)
            for i in 0..<count {
                let clamped = max(-1.0, min(1.0, floats[i]))
                var sample = Int16(clamped * 32767).littleEndian
                withUnsafeBytes(of: &sample) { pcm.append(contentsOf: $0) }
            }
        }

        var out = Data()
        func le32(_ v: UInt32) { var x = v.littleEndian; withUnsafeBytes(of: &x) { out.append(contentsOf: $0) } }
        func le16(_ v: UInt16) { var x = v.littleEndian; withUnsafeBytes(of: &x) { out.append(contentsOf: $0) } }

        out.append(contentsOf: Array("RIFF".utf8))
        le32(UInt32(36 + pcm.count))
        out.append(contentsOf: Array("WAVE".utf8))
        out.append(contentsOf: Array("fmt ".utf8))
        le32(16)                          // PCM header length
        le16(1); le16(1)                  // format = PCM, channels = mono
        le32(UInt32(sampleRate))
        le32(UInt32(sampleRate * 2))      // byte rate: mono 16-bit
        le16(2); le16(16)                 // block align, bits per sample
        out.append(contentsOf: Array("data".utf8))
        le32(UInt32(pcm.count))
        out.append(pcm)
        return out
    }
}

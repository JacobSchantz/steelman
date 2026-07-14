import Foundation
import CryptoKit
import Combine

/// Where the Kokoro-82M weights live and how we know they're intact.
///
/// Deliberately free of actor isolation and observable state: `SpeechRenderer` reads these
/// paths from its synthesis thread, while `KokoroModelStore` (below) drives the download
/// from the main actor. Splitting them keeps the file paths callable from anywhere.
enum KokoroModel {
    /// Weights come from the sherpa-onnx author's HuggingFace mirror, which serves the two
    /// files individually — the upstream Kokoro release is a single .tar.bz2 we'd have to
    /// unpack on-device.
    static let baseURL = "https://huggingface.co/csukuangfj/kokoro-en-v0_19/resolve/main"
    static let id = "kokoro-en-v0_19"

    struct Weight {
        let name: String
        let bytes: Int64
        let sha256: String
    }

    /// ~351 MB together. These are *not* bundled — only the small G2P assets
    /// (`tokens.txt` + `espeak-ng-data/`) ship inside the binary, because sherpa-onnx needs
    /// `data_dir` to be a real directory on disk when it builds the engine.
    static let weights = [
        Weight(name: "model.onnx",
               bytes: 345_555_491,
               sha256: "10ff414106a038ce7e9e0126c6461e4dc8a86efaa89dc91d2009d69fe635e339"),
        Weight(name: "voices.bin",
               bytes: 5_755_904,
               sha256: "a372c67b056ef0b695c375d39b99630d23fb07ad4c8d87aa32a19a62fca523ad"),
    ]

    static var directory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("Models/\(id)", isDirectory: true)
    }

    static var modelPath: String { directory.appendingPathComponent("model.onnx").path }
    static var voicesPath: String { directory.appendingPathComponent("voices.bin").path }

    /// Both weights present at exactly the expected size. This is a size check, not a
    /// re-hash: the SHA-256 was verified at download time, and re-hashing 345 MB on every
    /// launch would stall the feed for seconds.
    static var isInstalled: Bool {
        weights.allSatisfy { fileSize(at: directory.appendingPathComponent($0.name)) == $0.bytes }
    }

    static func fileSize(at url: URL) -> Int64? {
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
              let size = attrs[.size] as? NSNumber else { return nil }
        return size.int64Value
    }

    /// Hash in 1 MB chunks. `Data(contentsOf:)` on a 345 MB model would spike memory hard
    /// enough to risk getting jetsammed on an older phone.
    static func sha256(of url: URL) -> String? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        var hasher = SHA256()
        while let chunk = try? handle.read(upToCount: 1 << 20), !chunk.isEmpty {
            hasher.update(data: chunk)
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }
}

/// Downloads the Kokoro weights once, in the background, and reports progress.
///
/// The contract the rest of the app leans on: **a weight file only ever appears at its
/// final path if its SHA-256 matched.** Each file is verified in its temp location and
/// then moved into place, so an interrupted or corrupted transfer can't leave a truncated
/// `model.onnx` that sherpa-onnx would later choke on — it just leaves nothing, and
/// `KokoroModel.isInstalled` stays false.
///
/// Until both files land, speech falls back to AVSpeechSynthesizer. The app always talks;
/// it just starts sounding better once this finishes.
@MainActor
final class KokoroModelStore: ObservableObject {
    static let shared = KokoroModelStore()

    /// 0...1 while downloading, nil when idle.
    @Published private(set) var progress: Double?
    /// Observable mirror of `KokoroModel.isInstalled`, so SwiftUI can react when the weights
    /// land mid-session.
    @Published private(set) var isReady: Bool = KokoroModel.isInstalled

    private var downloading = false

    private init() {}

    /// Start the download if the weights aren't already here. Safe to call repeatedly — a
    /// call made while one is in flight is ignored.
    func ensureDownloaded() {
        guard !KokoroModel.isInstalled, !downloading else { return }
        downloading = true
        Task { await download() }
    }

    private func download() async {
        defer {
            downloading = false
            progress = nil
            isReady = KokoroModel.isInstalled
        }

        try? FileManager.default.createDirectory(
            at: KokoroModel.directory, withIntermediateDirectories: true)

        // Weight the bar by bytes, not by file count — model.onnx is 98% of the transfer, so
        // counting files would sit at 0% and then jump straight to done.
        let totalBytes = KokoroModel.weights.reduce(Int64(0)) { $0 + $1.bytes }
        var completed: Int64 = 0

        for weight in KokoroModel.weights {
            let destination = KokoroModel.directory.appendingPathComponent(weight.name)
            if KokoroModel.fileSize(at: destination) == weight.bytes {
                completed += weight.bytes
                progress = Double(completed) / Double(totalBytes)
                continue
            }
            guard let url = URL(string: "\(KokoroModel.baseURL)/\(weight.name)") else { return }

            do {
                let (temp, _) = try await URLSession.shared.download(from: url)
                // Verify before it becomes visible at the real path. A corrupt model that
                // sherpa-onnx tries to load is worse than no model at all.
                guard KokoroModel.sha256(of: temp) == weight.sha256 else {
                    try? FileManager.default.removeItem(at: temp)
                    print("[KokoroModelStore] checksum mismatch for \(weight.name); discarded")
                    return
                }
                try? FileManager.default.removeItem(at: destination)
                try FileManager.default.moveItem(at: temp, to: destination)
                completed += weight.bytes
                progress = Double(completed) / Double(totalBytes)
            } catch {
                print("[KokoroModelStore] download failed for \(weight.name): \(error)")
                return
            }
        }
    }
}

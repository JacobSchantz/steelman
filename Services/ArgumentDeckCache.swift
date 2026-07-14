import Foundation
import AVFoundation

/// Persists Discover deck + pre-downloads short audio segments (keepMovin DiscoverDeckCache).
final class ArgumentDeckCache {
    static let shared = ArgumentDeckCache()

    struct Snapshot: Codable {
        var clips: [ArgumentClip]
        var currentID: UUID?
        var lastHeardSide: [String: String] // questionId.uuidString → side.rawValue
    }

    static let segmentSeconds: TimeInterval = 30
    private let maxCacheBytes: Int64 = 200 * 1024 * 1024
    private let snapshotFileName = "argument_deck.json"
    private let audioExtension = "m4a"

    private var cacheRoot: URL {
        let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        let dir = base.appendingPathComponent("ArgumentClips", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private var snapshotURL: URL { cacheRoot.appendingPathComponent(snapshotFileName) }

    func loadSnapshot() -> Snapshot? {
        guard let data = try? Data(contentsOf: snapshotURL),
              let snapshot = try? JSONDecoder().decode(Snapshot.self, from: data),
              !snapshot.clips.isEmpty else {
            return nil
        }
        return snapshot
    }

    func save(_ snapshot: Snapshot) {
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        try? data.write(to: snapshotURL, options: .atomic)
    }

    func clearSnapshot() {
        try? FileManager.default.removeItem(at: snapshotURL)
    }

    func localSegmentURL(for clip: ArgumentClip) -> URL? {
        guard let name = clip.segmentFileName else { return nil }
        let url = cacheRoot.appendingPathComponent(name)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    /// Pre-download a short segment for instant start when the clip has remote/local file audio.
    func downloadSegment(for clip: ArgumentClip, id: UUID) async -> String? {
        guard let audioURL = clip.audioURL else { return nil }

        if let name = clip.segmentFileName,
           FileManager.default.fileExists(atPath: cacheRoot.appendingPathComponent(name).path) {
            return name
        }

        // Local file shorter than segment: just copy (or point by name).
        if audioURL.isFileURL {
            let fileName = "\(id.uuidString).\(audioExtension)"
            let destination = cacheRoot.appendingPathComponent(fileName)
            if FileManager.default.fileExists(atPath: destination.path) { return fileName }
            do {
                try FileManager.default.copyItem(at: audioURL, to: destination)
                enforceCacheLimit()
                return fileName
            } catch {
                return nil
            }
        }

        let asset = AVURLAsset(url: audioURL)
        guard let export = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetAppleM4A) else {
            return nil
        }

        let fileName = "\(id.uuidString).\(audioExtension)"
        let destination = cacheRoot.appendingPathComponent(fileName)
        try? FileManager.default.removeItem(at: destination)

        let start = CMTime(seconds: clip.startTime, preferredTimescale: 600)
        let length = CMTime(seconds: Self.segmentSeconds, preferredTimescale: 600)
        export.timeRange = CMTimeRange(start: start, duration: length)
        export.outputURL = destination
        export.outputFileType = .m4a

        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            export.exportAsynchronously { continuation.resume() }
        }
        guard export.status == .completed,
              FileManager.default.fileExists(atPath: destination.path) else {
            try? FileManager.default.removeItem(at: destination)
            return nil
        }
        enforceCacheLimit()
        return fileName
    }

    private func enforceCacheLimit() {
        let fm = FileManager.default
        guard let entries = try? fm.contentsOfDirectory(
            at: cacheRoot,
            includingPropertiesForKeys: [.fileSizeKey, .contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else { return }

        var sized = entries
            .filter { $0.pathExtension == audioExtension }
            .map { url -> (url: URL, size: Int64, date: Date) in
                let values = try? url.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey])
                return (url, Int64(values?.fileSize ?? 0), values?.contentModificationDate ?? .distantPast)
            }

        var total = sized.reduce(Int64(0)) { $0 + $1.size }
        guard total > maxCacheBytes else { return }

        sized.sort { $0.date < $1.date }
        for entry in sized {
            guard total > maxCacheBytes else { break }
            try? fm.removeItem(at: entry.url)
            total -= entry.size
        }
    }
}

import Foundation
import AVFoundation

/// Persists where the listener is + pre-downloads short audio segments
/// (keepMovin DiscoverDeckCache).
///
/// The deck itself is **not** stored: clips are rebuilt from `QuestionStore` /
/// `AnswerStore`, which are the source of truth, and a clip's id is its answer's id.
/// All that has to survive a launch is the listener's place in the feed.
final class ArgumentDeckCache {
    static let shared = ArgumentDeckCache()

    struct Snapshot: Codable {
        /// The question currently being scrolled through.
        var selectedQuestionID: UUID?
        /// The page (question card or clip) the feed is parked on.
        var currentPageID: UUID?
        /// How far into the current question's feed the listener has earned their way, as an
        /// index into its pages. Deliberately *not* a set of every page ever heard: that set
        /// only ever grew, and since a question card's page id is the question's id, one lap
        /// around the loop put every page of every question in it and switched the lock off
        /// for good. An index resets when you enter a question, so the gate re-arms.
        /// Optional so snapshots written before this change still decode (as "start at the
        /// top", which is the safe answer).
        var unlockedIndex: Int?
        /// Questions whose clips have all been heard; the next-question pick skips these.
        var completedQuestionIDs: [UUID]
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
              let snapshot = try? JSONDecoder().decode(Snapshot.self, from: data) else {
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
        let name = clip.segmentFileName ?? segmentFileName(for: clip.id)
        let url = cacheRoot.appendingPathComponent(name)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    /// A clip's segment is named after the clip, so a rebuilt deck finds an already
    /// downloaded segment without having to persist the deck to remember it.
    func cachedSegmentName(for clipID: UUID) -> String? {
        let name = segmentFileName(for: clipID)
        let url = cacheRoot.appendingPathComponent(name)
        return FileManager.default.fileExists(atPath: url.path) ? name : nil
    }

    private func segmentFileName(for clipID: UUID) -> String {
        "\(clipID.uuidString).\(audioExtension)"
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
            let fileName = segmentFileName(for: id)
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

        let fileName = segmentFileName(for: id)
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

import SwiftUI

/// TikTok-style vertical Discover feed — layout and player chrome mirror keepMovin's
/// `AddWithAIView`, but each page is one side of an argument. The deck is ordered so
/// you cannot hear the same side of a question twice without hearing the other side first.
///
/// Product gates on the feed itself:
/// - No skip-forward and no scrubbing at all — the bar is a playback indicator.
/// - The *next* viewpoint can be peeked at by scrolling, but the feed bounces back to the
///   current one with a lock message until the current clip has been heard to the end.
/// - Answer body text is hidden for now (title/subtitle remain).
struct DiscoverView: View {
    @ObservedObject var questions: QuestionStore
    @ObservedObject var answers: AnswerStore

    @StateObject private var clipPlayer = ClipPreviewPlayer()

    @State private var clips: [ArgumentClip] = []
    @State private var currentID: UUID?
    @State private var lastHeardSide: [UUID: ArgumentSide] = [:]
    @State private var downloadingClips: Set<UUID> = []
    @State private var didInitialLoad = false
    /// Clips the user has listened all the way through — unlocks scrolling past them.
    @State private var fullyHeardIDs: Set<UUID> = []
    /// Shown after the feed bounces the user back off a locked card.
    @State private var showLockMessage = false
    @State private var lockMessageTask: Task<Void, Never>?

    @AppStorage("discoverTotalSwiped") private var totalSwiped = 0
    @State private var countedIDs: Set<UUID> = []

    private let deckCache = ArgumentDeckCache.shared
    private let clipDownloadCount = 10
    private let playerPreloadCount = 2

    private var currentClip: ArgumentClip? {
        if let currentID, let c = clips.first(where: { $0.id == currentID }) { return c }
        return clips.first
    }

    /// Highest index the user is allowed to land on: everything through the first
    /// not-yet-finished clip (inclusive). Past that is locked until they finish listening.
    private var maxAllowedIndex: Int {
        guard !clips.isEmpty else { return 0 }
        for (i, clip) in clips.enumerated() {
            if !fullyHeardIDs.contains(clip.id) {
                return i
            }
        }
        return clips.count - 1
    }

    var body: some View {
        NavigationStack {
            Group {
                if clips.isEmpty {
                    emptyState
                } else {
                    feed
                }
            }
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text("Discover")
                        .font(.headline)
                }
            }
            .task(id: currentID) { await prepareAndPlayCurrent() }
            .onAppear {
                if !didInitialLoad {
                    didInitialLoad = true
                    rebuildDeck(preferCache: true)
                }
            }
            .onChange(of: answers.answers) { _, _ in
                rebuildDeck(preferCache: false)
            }
            .onChange(of: questions.questions) { _, _ in
                rebuildDeck(preferCache: false)
            }
            .onChange(of: clipPlayer.finishedClipID) { _, finished in
                // The player names the clip that reached its end, so a card change mid-
                // completion can't credit the wrong one.
                guard let finished else { return }
                fullyHeardIDs.insert(finished)
            }
            .onChange(of: currentID) { _, newID in
                guard let newID, let newIndex = clips.firstIndex(where: { $0.id == newID }) else { return }
                if newIndex > maxAllowedIndex {
                    bounceBackToCurrent()
                }
            }
            .onDisappear { lockMessageTask?.cancel() }
        }
    }

    /// The user scrolled onto the locked peek card. Let them see it, then bounce them back
    /// to the clip they still owe a listen to, and say why.
    private func bounceBackToCurrent() {
        guard !clips.isEmpty else { return }
        let allowedID = clips[maxAllowedIndex].id
        withAnimation(.snappy) {
            showLockMessage = true
            if currentID != allowedID {
                currentID = allowedID
            }
        }
        lockMessageTask?.cancel()
        lockMessageTask = Task {
            try? await Task.sleep(for: .seconds(2.5))
            guard !Task.isCancelled else { return }
            withAnimation(.snappy) { showLockMessage = false }
        }
    }

    // MARK: - Feed (keepMovin Discover scroll mechanics)

    /// Past clips, the first unfinished one, and **one page beyond it** — the peek. The
    /// peek page exists so the user can scroll down and see that a next viewpoint is
    /// waiting; landing on it bounces them straight back (`bounceBackToCurrent`).
    private var scrollableClips: [ArgumentClip] {
        guard !clips.isEmpty else { return [] }
        let end = min(maxAllowedIndex + 2, clips.count)
        return Array(clips.prefix(end))
    }

    /// True for the peek page — the one viewpoint rendered beyond what's been earned.
    private func isLocked(_ clip: ArgumentClip) -> Bool {
        guard let idx = clips.firstIndex(where: { $0.id == clip.id }) else { return false }
        return idx > maxAllowedIndex
    }

    private var feed: some View {
        ScrollView(.vertical) {
            LazyVStack(spacing: 0) {
                ForEach(scrollableClips) { clip in
                    let locked = isLocked(clip)
                    ArgumentFeedCard(
                        clip: clip,
                        isCurrent: !locked && clip.id == currentClip?.id,
                        isLocked: locked,
                        clipPlayer: clipPlayer
                    )
                    .containerRelativeFrame([.horizontal, .vertical])
                    .id(clip.id)
                }
            }
            .scrollTargetLayout()
        }
        .scrollTargetBehavior(.viewAligned(limitBehavior: .always))
        .scrollIndicators(.hidden)
        .scrollPosition(id: $currentID, anchor: .top)
        .overlay(alignment: .top) { lockMessage }
    }

    @ViewBuilder
    private var lockMessage: some View {
        if showLockMessage {
            HStack(spacing: 8) {
                Image(systemName: "lock.fill")
                Text("Finish listening to this one first")
            }
            .font(.subheadline.weight(.semibold))
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(.ultraThinMaterial, in: Capsule())
            .overlay(Capsule().stroke(Color.secondary.opacity(0.25)))
            .shadow(radius: 8, y: 2)
            .padding(.top, 12)
            .transition(.move(edge: .top).combined(with: .opacity))
            .allowsHitTesting(false)
        }
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label("No alternating clips yet", systemImage: "bubble.left.and.bubble.right")
        } description: {
            Text("Add answers on both sides of a question. Discover only advances to the other side after you hear one — then back again.")
        }
    }

    // MARK: - Deck build + play

    private func rebuildDeck(preferCache: Bool) {
        if preferCache, let snapshot = deckCache.loadSnapshot(), !snapshot.clips.isEmpty {
            clips = snapshot.clips
            lastHeardSide = snapshot.lastHeardSide.reduce(into: [:]) { dict, pair in
                if let qid = UUID(uuidString: pair.key),
                   let side = ArgumentSide(rawValue: pair.value) {
                    dict[qid] = side
                }
            }
            if let saved = snapshot.currentID, clips.contains(where: { $0.id == saved }) {
                currentID = saved
            } else {
                currentID = clips.first?.id
            }
            // Refresh from live stores if answers grew.
            let live = buildLiveDeck()
            if live.count > clips.count {
                clips = live
                currentID = clips.first?.id
            }
            return
        }

        clips = buildLiveDeck()
        currentID = clips.first?.id
        persist()
    }

    private func buildLiveDeck() -> [ArgumentClip] {
        ArgumentDeckBuilder.build(
            questions: questions.questions,
            answers: answers.answers,
            audioURLProvider: { answers.audioURL(for: $0) },
            lastHeardSide: [:] // full rebuild; alternating enforced by builder order
        )
    }

    private func persist() {
        let map = lastHeardSide.reduce(into: [String: String]()) { $0[$1.key.uuidString] = $1.value.rawValue }
        deckCache.save(ArgumentDeckCache.Snapshot(
            clips: clips,
            currentID: currentID,
            lastHeardSide: map
        ))
    }

    private func prepareAndPlayCurrent() async {
        guard let clip = currentClip else {
            clipPlayer.stop()
            return
        }

        // Landed on the locked peek page. Don't play it, don't count it — the currentID
        // change already kicked off the bounce back to the clip they still owe a listen.
        if let idx = clips.firstIndex(where: { $0.id == clip.id }), idx > maxAllowedIndex {
            return
        }

        if countedIDs.insert(clip.id).inserted {
            totalSwiped += 1
        }

        // Alternating bookkeeping: once you land on a side, that becomes last-heard for the question.
        lastHeardSide[clip.questionId] = clip.side
        persist()

        // Warm upcoming audio segments + players (keepMovin pattern).
        prefetchUpcoming(clip)

        let segment = deckCache.localSegmentURL(for: clip)
        clipPlayer.play(clip: clip, url: segment)
        downloadSegment(for: clip)
    }

    private func prefetchUpcoming(_ current: ArgumentClip) {
        guard let i = clips.firstIndex(where: { $0.id == current.id }) else { return }
        let upcoming = Array(clips.suffix(from: min(i + 1, clips.count)).prefix(clipDownloadCount))
        for clip in upcoming {
            downloadSegment(for: clip)
        }
        for clip in upcoming.prefix(playerPreloadCount) {
            clipPlayer.preload(clip: clip)
        }
    }

    private func downloadSegment(for clip: ArgumentClip) {
        guard clip.audioURL != nil,
              deckCache.localSegmentURL(for: clip) == nil,
              downloadingClips.insert(clip.id).inserted else { return }
        Task {
            let fileName = await deckCache.downloadSegment(for: clip, id: clip.id)
            downloadingClips.remove(clip.id)
            guard let fileName,
                  let idx = clips.firstIndex(where: { $0.id == clip.id }) else { return }
            clips[idx].segmentFileName = fileName
            persist()
        }
    }
}

// MARK: - Feed card

/// Full-bleed page: artwork + title/subtitle + transport (play/pause + skip back only).
/// The bar is a read-only indicator — there is no scrubbing and no skip-forward.
/// Side rail and answer body text are intentionally omitted for the current product pass.
private struct ArgumentFeedCard: View {
    let clip: ArgumentClip
    let isCurrent: Bool
    /// The peek page: visible so the user knows more is coming, but not yet earned.
    let isLocked: Bool
    @ObservedObject var clipPlayer: ClipPreviewPlayer

    var body: some View {
        NowPlayingContent(
            artworkURL: nil,
            localArtworkURL: nil,
            title: clip.title,
            subtitle: clip.subtitle,
            currentTime: isCurrent ? clipPlayer.progress : 0,
            duration: isCurrent ? clipPlayer.duration : max(clip.duration, 1),
            bufferedTime: isCurrent ? clipPlayer.bufferedProgress : 0,
            // Only the active card mirrors real engine state — other pages stay on "play".
            isPlaying: isCurrent && clipPlayer.isPlaying,
            description: "",
            sliderInteractive: false,
            showSkipBackward: true,
            showDescription: false,
            scrollable: false,
            onSeek: { _ in },
            onSkipBackward: { guard isCurrent else { return }; clipPlayer.skipBackward() },
            onTogglePlayPause: { guard isCurrent else { return }; clipPlayer.togglePlayPause() },
            errorMessage: isCurrent ? clipPlayer.errorMessage : nil,
            accent: SteelmanTheme.color(for: clip.side),
            badge: clip.containsProfanity ? "Profanity" : nil,
            badgeColor: SteelmanTheme.danger
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemBackground))
        .overlay { if isLocked { lockedOverlay } }
    }

    /// Frosts the peek page and swallows taps, so its transport can't be driven.
    private var lockedOverlay: some View {
        ZStack {
            Rectangle()
                .fill(.ultraThinMaterial)
            VStack(spacing: 14) {
                Image(systemName: "lock.fill")
                    .font(.system(size: 44))
                Text("Finish listening to this one first")
                    .font(.headline)
                    .multilineTextAlignment(.center)
            }
            .foregroundStyle(.secondary)
            .padding()
        }
        .contentShape(Rectangle())
    }
}

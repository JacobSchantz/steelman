import SwiftUI

/// TikTok-style vertical Discover feed — layout and player chrome mirror keepMovin's
/// `AddWithAIView`, but each page is one side of an argument. The deck is ordered so
/// you cannot hear the same side of a question twice without hearing the other side first.
struct DiscoverView: View {
    @ObservedObject var questions: QuestionStore
    @ObservedObject var answers: AnswerStore

    @StateObject private var clipPlayer = ClipPreviewPlayer()

    @State private var clips: [ArgumentClip] = []
    @State private var currentID: UUID?
    @State private var isListMode = false
    @State private var lastHeardSide: [UUID: ArgumentSide] = [:]
    @State private var downloadingClips: Set<UUID> = []
    @State private var didInitialLoad = false

    @AppStorage("discoverTotalSwiped") private var totalSwiped = 0
    @State private var countedIDs: Set<UUID> = []

    private let deckCache = ArgumentDeckCache.shared
    private let clipDownloadCount = 10
    private let playerPreloadCount = 2

    private var currentClip: ArgumentClip? {
        if let currentID, let c = clips.first(where: { $0.id == currentID }) { return c }
        return clips.first
    }

    private var currentIndex: Int? {
        guard let id = currentClip?.id else { return nil }
        return clips.firstIndex { $0.id == id }
    }

    var body: some View {
        NavigationStack {
            Group {
                if clips.isEmpty {
                    emptyState
                } else if isListMode {
                    listView
                } else {
                    feed
                }
            }
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button {
                        withAnimation { isListMode.toggle() }
                    } label: {
                        Image(systemName: "line.3.horizontal")
                            .foregroundStyle(isListMode ? SteelmanTheme.accent : Color.primary)
                    }
                    .accessibilityLabel(isListMode ? "Show full-screen feed" : "Show as list")
                }
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
        }
    }

    // MARK: - Feed (keepMovin Discover scroll mechanics)

    private var feed: some View {
        ScrollView(.vertical) {
            LazyVStack(spacing: 0) {
                ForEach(clips) { clip in
                    ArgumentFeedCard(
                        clip: clip,
                        isCurrent: clip.id == currentClip?.id,
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
    }

    // MARK: - List layout

    private var pastClips: [ArgumentClip] {
        guard let i = currentIndex, i > 0 else { return [] }
        return Array(clips[..<i])
    }

    private var upcomingClips: [ArgumentClip] {
        guard let i = currentIndex else { return clips }
        return Array(clips[(i + 1)...])
    }

    private var listView: some View {
        ScrollViewReader { proxy in
            List {
                if !pastClips.isEmpty {
                    Section("Already played · \(pastClips.count)") {
                        ForEach(pastClips) { listRow($0) }
                    }
                }
                if let clip = currentClip {
                    Section("Now playing") {
                        listRow(clip)
                    }
                }
                if !upcomingClips.isEmpty {
                    Section("Up next · \(upcomingClips.count)") {
                        ForEach(upcomingClips) { listRow($0) }
                    }
                }
            }
            .listStyle(.insetGrouped)
            .onAppear {
                if let id = currentClip?.id {
                    proxy.scrollTo(id, anchor: .center)
                }
            }
        }
    }

    private func listRow(_ clip: ArgumentClip) -> some View {
        let isCurrent = clip.id == currentClip?.id
        return Button {
            if isCurrent {
                clipPlayer.togglePlayPause()
            } else {
                currentID = clip.id
            }
        } label: {
            HStack(spacing: 12) {
                Circle()
                    .fill(SteelmanTheme.color(for: clip.side))
                    .frame(width: 44, height: 44)
                    .overlay {
                        Text(clip.side == .a ? "A" : "B")
                            .font(.headline.bold())
                            .foregroundStyle(.white)
                    }

                VStack(alignment: .leading, spacing: 2) {
                    Text(clip.sideLabel)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    Text(clip.subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }

                Spacer(minLength: 8)

                if isCurrent {
                    Image(systemName: clipPlayer.isPlaying ? "speaker.wave.2.fill" : "pause.fill")
                        .foregroundStyle(SteelmanTheme.accent)
                }
            }
        }
        .buttonStyle(.plain)
        .id(clip.id)
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

/// Full-bleed page mirroring keepMovin FeedCard + NowPlayingContent.
private struct ArgumentFeedCard: View {
    let clip: ArgumentClip
    let isCurrent: Bool
    @ObservedObject var clipPlayer: ClipPreviewPlayer

    var body: some View {
        NowPlayingContent(
            artworkURL: nil,
            localArtworkURL: nil,
            title: clip.title,
            subtitle: clip.subtitle,
            currentTime: clipPlayer.progress,
            duration: clipPlayer.duration,
            bufferedTime: clipPlayer.bufferedProgress,
            isPlaying: clipPlayer.isPlaying,
            description: clip.description,
            sliderInteractive: true,
            onScrubbingChanged: { _ in },
            scrollable: false,
            onSeek: { clipPlayer.seek(to: $0) },
            onSkipBackward: { clipPlayer.skipBackward() },
            onTogglePlayPause: { clipPlayer.togglePlayPause() },
            onSkipForward: { clipPlayer.skipForward() },
            errorMessage: isCurrent ? clipPlayer.errorMessage : nil,
            accent: SteelmanTheme.color(for: clip.side),
            badge: clip.containsProfanity ? "Profanity" : nil,
            badgeColor: SteelmanTheme.danger
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemBackground))
        .overlay(alignment: .trailing) { sideRail }
        .overlay(alignment: .bottom) {
            if !clip.answerText.isEmpty {
                Text(clip.answerText)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .lineLimit(4)
                    .padding(.horizontal, 20)
                    .padding(.bottom, 28)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    /// Right-edge meta (replaces keepMovin's Add Episode / Add Show glass buttons).
    private var sideRail: some View {
        VStack(spacing: 14) {
            metaPill(
                systemImage: clip.side == .a ? "a.circle.fill" : "b.circle.fill",
                label: clip.side.displayName,
                tint: SteelmanTheme.color(for: clip.side)
            )
            if clip.leanConfidence > 0 {
                metaPill(
                    systemImage: "chart.bar.fill",
                    label: "\(Int(clip.leanConfidence * 100))%",
                    tint: .secondary
                )
            }
            if clip.audioURL != nil {
                metaPill(systemImage: "waveform", label: "Audio", tint: .secondary)
            } else {
                metaPill(systemImage: "text.alignleft", label: "Text", tint: .secondary)
            }
        }
        .padding(.trailing, 16)
    }

    private func metaPill(systemImage: String, label: String, tint: Color) -> some View {
        VStack(spacing: 4) {
            Image(systemName: systemImage)
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 48, height: 48)
                .background(.ultraThinMaterial, in: Circle())
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(label)
    }
}

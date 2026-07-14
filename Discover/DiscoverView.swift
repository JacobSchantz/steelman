import SwiftUI

/// Discover — **one question at a time**.
///
/// The feed opens on a question card that reads the question out loud, then scrolls
/// through the alternating viewpoints on that question. Reach the end and it rolls
/// straight into the next recommended question, starting with *its* question card. The
/// toolbar names the question you're in and opens a picker to jump to another one.
///
/// Product gates on the feed itself:
/// - No skip-forward and no scrubbing at all — the bar is a playback indicator.
/// - The next page can be peeked at by scrolling, but the feed bounces back with a lock
///   message until the current page — question card or clip — has been heard to the end.
struct DiscoverView: View {
    @ObservedObject var questions: QuestionStore
    @ObservedObject var answers: AnswerStore

    @StateObject private var player = ClipPreviewPlayer()

    /// The question being scrolled through. Nil until the first recommendation lands.
    @State private var selectedQuestionID: UUID?
    /// Clips for the selected question only, in alternating-side order.
    @State private var clips: [ArgumentClip] = []
    @State private var currentPageID: UUID?
    /// Pages heard end-to-end — question cards included. This is what unlocks scrolling.
    @State private var heardPageIDs: Set<UUID> = []
    /// Questions already listened through; the next-question pick prefers fresh ones.
    @State private var completedQuestionIDs: Set<UUID> = []
    @State private var downloadingClips: Set<UUID> = []
    @State private var didInitialLoad = false
    @State private var showingPicker = false
    @State private var showLockMessage = false
    @State private var lockMessageTask: Task<Void, Never>?

    private let deckCache = ArgumentDeckCache.shared
    private let clipDownloadCount = 10
    private let playerPreloadCount = 2

    // MARK: - Pages

    private var currentQuestion: Question? {
        if let selectedQuestionID, let q = questions.question(id: selectedQuestionID) { return q }
        return recommendedQuestions.first ?? questions.questions.first
    }

    /// The feed for the current question: its question card, its clips, and — as the last
    /// page — the *next* question's card. Scrolling onto that last page is what hands the
    /// listener to the next question.
    private var pages: [DiscoverPage] {
        guard let currentQuestion else { return [] }
        var pages: [DiscoverPage] = [.question(currentQuestion)]
        pages += clips.map { .clip($0) }
        if let next = nextQuestion {
            pages.append(.question(next))
        }
        return pages
    }

    private var currentPage: DiscoverPage? {
        if let currentPageID, let page = pages.first(where: { $0.id == currentPageID }) { return page }
        return pages.first
    }

    /// Questions worth sending someone to, best first: ones with both sides represented
    /// beat one-sided ones, then more answers wins. Questions with nothing to hear are
    /// never recommended (they're still reachable from the picker).
    private var recommendedQuestions: [Question] {
        questions.questions
            .map { (question: $0, answers: answers.answers(for: $0.id)) }
            .filter { !$0.answers.isEmpty }
            .sorted { lhs, rhs in
                let lhsBothSides = hasBothSides(lhs.answers)
                let rhsBothSides = hasBothSides(rhs.answers)
                if lhsBothSides != rhsBothSides { return lhsBothSides }
                if lhs.answers.count != rhs.answers.count { return lhs.answers.count > rhs.answers.count }
                return lhs.question.createdAt > rhs.question.createdAt
            }
            .map(\.question)
    }

    private func hasBothSides(_ answers: [Answer]) -> Bool {
        let sides = Set(answers.compactMap(\.resolvedSide))
        return sides.count > 1
    }

    /// Where the listener goes when this question runs out: the best-ranked question they
    /// haven't finished yet, or — once they've heard everything — back around the loop.
    private var nextQuestion: Question? {
        let others = recommendedQuestions.filter { $0.id != currentQuestion?.id }
        return others.first { !completedQuestionIDs.contains($0.id) } ?? others.first
    }

    /// Highest index the listener may land on: everything through the first page they
    /// haven't finished (inclusive). Past that is locked until they listen.
    private var maxAllowedIndex: Int {
        guard !pages.isEmpty else { return 0 }
        for (i, page) in pages.enumerated() where !heardPageIDs.contains(page.id) {
            return i
        }
        return pages.count - 1
    }

    /// Everything earned, plus **one page beyond** — the peek. The peek exists so the
    /// listener can see that something is waiting; landing on it bounces them back.
    private var scrollablePages: [DiscoverPage] {
        guard !pages.isEmpty else { return [] }
        return Array(pages.prefix(min(maxAllowedIndex + 2, pages.count)))
    }

    private func isLocked(_ page: DiscoverPage) -> Bool {
        guard let idx = pages.firstIndex(where: { $0.id == page.id }) else { return false }
        return idx > maxAllowedIndex
    }

    // MARK: - Body

    var body: some View {
        NavigationStack {
            Group {
                if pages.isEmpty {
                    emptyState
                } else {
                    feed
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text(currentQuestion?.prompt ?? "")
                        .font(.footnote.weight(.semibold))
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showingPicker = true } label: {
                        Image(systemName: "text.bubble.fill")
                    }
                    .accessibilityLabel("Choose a question")
                }
            }
            .sheet(isPresented: $showingPicker) {
                QuestionPickerSheet(
                    questions: questions,
                    answers: answers,
                    currentQuestionID: currentQuestion?.id,
                    onSelect: { select(questionID: $0, completingCurrent: false) }
                )
            }
            .task(id: currentPageID) { await prepareAndPlayCurrent() }
            .onAppear {
                if !didInitialLoad {
                    didInitialLoad = true
                    restore()
                }
            }
            .onChange(of: answers.answers) { _, _ in rebuildClips() }
            .onChange(of: questions.questions) { _, _ in rebuildClips() }
            .onChange(of: player.finishedItemID) { _, finished in
                guard let finished else { return }
                heardPageIDs.insert(finished)
                persist()
                advanceIfQuestionFinished(afterHearing: finished)
            }
            .onChange(of: currentPageID) { _, newID in handleLanding(on: newID) }
            .onDisappear { lockMessageTask?.cancel() }
        }
    }

    private var feed: some View {
        ScrollView(.vertical) {
            LazyVStack(spacing: 0) {
                ForEach(scrollablePages) { page in
                    pageView(page)
                        .containerRelativeFrame([.horizontal, .vertical])
                        .id(page.id)
                }
            }
            .scrollTargetLayout()
        }
        .scrollTargetBehavior(.viewAligned(limitBehavior: .always))
        .scrollIndicators(.hidden)
        .scrollPosition(id: $currentPageID, anchor: .top)
        .overlay(alignment: .top) { lockMessage }
    }

    @ViewBuilder
    private func pageView(_ page: DiscoverPage) -> some View {
        let locked = isLocked(page)
        let isCurrent = !locked && page.id == currentPage?.id

        switch page {
        case .question(let question):
            QuestionIntroCard(
                question: question,
                answerCount: answers.answers(for: question.id).count,
                isCurrent: isCurrent,
                isLocked: locked,
                player: player
            )
        case .clip(let clip):
            ArgumentFeedCard(
                clip: clip,
                isCurrent: isCurrent,
                isLocked: locked,
                player: player
            )
        }
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
            Label("Nothing to argue about yet", systemImage: "bubble.left.and.bubble.right")
        } description: {
            Text("Add a question, then answers on both sides of it. Discover reads you the question, then alternates the viewpoints.")
        }
    }

    // MARK: - Moving between pages and questions

    /// The listener scrolled somewhere. Either they've reached the next question's card
    /// (hand them over), or they've jumped ahead of what they've earned (bounce them back).
    private func handleLanding(on pageID: UUID?) {
        guard let pageID, let idx = pages.firstIndex(where: { $0.id == pageID }) else { return }

        if idx > maxAllowedIndex {
            bounceBackToCurrent()
            return
        }
        // The only question card that isn't the one we're on is the trailing one — the
        // next question. Landing on it is the handoff.
        if case .question(let question) = pages[idx], question.id != currentQuestion?.id {
            select(questionID: question.id, completingCurrent: true)
        }
    }

    /// Last clip of the question just played out — roll into the next question's card so
    /// the feed keeps going without the listener having to do anything.
    private func advanceIfQuestionFinished(afterHearing pageID: UUID) {
        guard currentPageID == pageID,
              let idx = pages.firstIndex(where: { $0.id == pageID }),
              case .clip = pages[idx],
              idx == pages.count - 2,
              case .question = pages[pages.count - 1] else { return }

        withAnimation(.snappy) {
            currentPageID = pages[pages.count - 1].id
        }
    }

    private func select(questionID: UUID, completingCurrent: Bool) {
        if completingCurrent, let current = currentQuestion?.id {
            completedQuestionIDs.insert(current)
        }
        selectedQuestionID = questionID
        rebuildClips()
        // The question's card is page 0, and it carries the question's id — so when this
        // came from scrolling onto the trailing card, the listener is already on it.
        currentPageID = questionID
        persist()
    }

    /// The listener scrolled onto the locked peek page. Let them see it, then bounce them
    /// back to the page they still owe a listen to, and say why.
    private func bounceBackToCurrent() {
        guard !pages.isEmpty else { return }
        let allowedID = pages[maxAllowedIndex].id
        withAnimation(.snappy) {
            showLockMessage = true
            if currentPageID != allowedID {
                currentPageID = allowedID
            }
        }
        lockMessageTask?.cancel()
        lockMessageTask = Task {
            try? await Task.sleep(for: .seconds(2.5))
            guard !Task.isCancelled else { return }
            withAnimation(.snappy) { showLockMessage = false }
        }
    }

    // MARK: - Deck + playback

    private func restore() {
        let snapshot = deckCache.loadSnapshot()
        if let snapshot {
            heardPageIDs = Set(snapshot.heardPageIDs)
            completedQuestionIDs = Set(snapshot.completedQuestionIDs)
            if let saved = snapshot.selectedQuestionID, questions.question(id: saved) != nil {
                selectedQuestionID = saved
            }
        }
        rebuildClips()
        if let saved = snapshot?.currentPageID, pages.contains(where: { $0.id == saved }) {
            currentPageID = saved
        } else {
            currentPageID = pages.first?.id
        }
    }

    private func rebuildClips() {
        guard let question = currentQuestion else {
            clips = []
            return
        }
        clips = ArgumentDeckBuilder.build(
            questions: [question],
            answers: answers.answers,
            audioURLProvider: { answers.audioURL(for: $0) }
        )
        .map { clip in
            // A clip's downloaded segment is named after the clip, so a rebuilt deck picks
            // up what's already on disk.
            var hydrated = clip
            hydrated.segmentFileName = deckCache.cachedSegmentName(for: clip.id)
            return hydrated
        }

        if let currentPageID, !pages.contains(where: { $0.id == currentPageID }) {
            self.currentPageID = pages.first?.id
        }
    }

    private func persist() {
        deckCache.save(ArgumentDeckCache.Snapshot(
            selectedQuestionID: currentQuestion?.id,
            currentPageID: currentPageID,
            heardPageIDs: Array(heardPageIDs),
            completedQuestionIDs: Array(completedQuestionIDs)
        ))
    }

    private func prepareAndPlayCurrent() async {
        guard let page = currentPage else {
            player.stop()
            return
        }
        // Landed on the locked peek page. Don't play it — the page change already kicked
        // off the bounce back to the page they still owe a listen.
        guard let idx = pages.firstIndex(where: { $0.id == page.id }), idx <= maxAllowedIndex else {
            return
        }

        switch page {
        case .question(let question):
            player.play(.question(question))
        case .clip(let clip):
            prefetchUpcoming(clip)
            player.play(.clip(clip, url: deckCache.localSegmentURL(for: clip)))
            downloadSegment(for: clip)
        }
        persist()
    }

    private func prefetchUpcoming(_ current: ArgumentClip) {
        guard let i = clips.firstIndex(where: { $0.id == current.id }) else { return }
        let upcoming = Array(clips.suffix(from: min(i + 1, clips.count)).prefix(clipDownloadCount))
        for clip in upcoming {
            downloadSegment(for: clip)
        }
        for clip in upcoming.prefix(playerPreloadCount) {
            player.preload(clip: clip)
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
        }
    }
}

// MARK: - Pages

/// A page of the feed: the card that reads a question, or one viewpoint on it.
enum DiscoverPage: Identifiable, Equatable {
    case question(Question)
    case clip(ArgumentClip)

    /// A question card is identified by its question, a clip by its answer — both stable
    /// across deck rebuilds, so "already heard" survives one.
    var id: UUID {
        switch self {
        case .question(let question): return question.id
        case .clip(let clip): return clip.id
        }
    }
}

// MARK: - Feed card

/// Full-bleed page: artwork + side label + transport (play/pause + skip back only).
/// The bar is a read-only indicator — there is no scrubbing and no skip-forward. The
/// question isn't repeated here: it's in the toolbar, and it opened the question.
private struct ArgumentFeedCard: View {
    let clip: ArgumentClip
    let isCurrent: Bool
    /// The peek page: visible so the user knows more is coming, but not yet earned.
    let isLocked: Bool
    @ObservedObject var player: ClipPreviewPlayer

    var body: some View {
        NowPlayingContent(
            artworkURL: nil,
            localArtworkURL: nil,
            title: clip.title,
            subtitle: nil,
            currentTime: isCurrent ? player.progress : 0,
            duration: isCurrent ? player.duration : max(clip.duration, 1),
            bufferedTime: isCurrent ? player.bufferedProgress : 0,
            // Only the active card mirrors real engine state — other pages stay on "play".
            isPlaying: isCurrent && player.isPlaying,
            description: "",
            sliderInteractive: false,
            showSkipBackward: true,
            showDescription: false,
            scrollable: false,
            onSeek: { _ in },
            onSkipBackward: { guard isCurrent else { return }; player.skipBackward() },
            onTogglePlayPause: { guard isCurrent else { return }; player.togglePlayPause() },
            errorMessage: isCurrent ? player.errorMessage : nil,
            accent: SteelmanTheme.color(for: clip.side),
            badge: clip.containsProfanity ? "Profanity" : nil,
            badgeColor: SteelmanTheme.danger
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemBackground))
        .overlay { if isLocked { LockedPeekOverlay() } }
    }
}

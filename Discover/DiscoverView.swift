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
/// - Hearing a page out carries you to the next one on its own (see `advanceToNextPage`),
///   so the feed plays hands-free: put the phone down and it keeps arguing at you.
/// - The next page can be peeked at by scrolling, but the feed bounces back with a lock
///   message until the current page — question card or clip — has been heard to the end.
///   The gate is per pass through a question (see `unlockedIndex`), so coming back around
///   the loop to a question you've heard before makes you listen to it again rather than
///   handing you a feed you can swipe straight through.
struct DiscoverView: View {
    @ObservedObject var questions: QuestionStore
    @ObservedObject var answers: AnswerStore

    @StateObject private var player = ClipPreviewPlayer()
    @StateObject private var speech = KokoroModelStore.shared
    @ObservedObject private var speechSettings = SpeechSettings.shared

    /// The question being scrolled through. Nil until the first recommendation lands.
    @State private var selectedQuestionID: UUID?
    /// Clips for the selected question only, in alternating-side order.
    @State private var clips: [ArgumentClip] = []
    @State private var currentPageID: UUID?
    /// How far into *this* question's feed the listener has earned their way: the highest
    /// index in `pages` they're allowed to land on. It starts at 0 (the question card) every
    /// time a question is entered and only moves when the page it points at is heard out.
    ///
    /// It used to be a set of every page ever heard, which quietly disabled the lock: a
    /// question card's page id is its question's id, and the last page of a question's feed
    /// is the *next* question's card — so one lap around the loop put every page of every
    /// question into the set, every page was "already heard", and the feed unlocked end to
    /// end. An index can't accumulate like that.
    @State private var unlockedIndex = 0
    /// Questions already listened through; the next-question pick prefers fresh ones.
    @State private var completedQuestionIDs: Set<UUID> = []
    @State private var downloadingClips: Set<UUID> = []
    @State private var didInitialLoad = false
    @State private var browsingQuestions = false
    @State private var showingSettings = false
    @State private var showLockMessage = false
    @State private var lockMessageTask: Task<Void, Never>?
    /// Bumped to re-drive the feed's scroll to `currentPageID` when the *value* didn't change
    /// but the layout under it did — see the question handoff in `select`.
    @State private var feedScrollNonce = 0

    private let deckCache = ArgumentDeckCache.shared
    private let clipDownloadCount = 10
    private let playerPreloadCount = 2
    /// How far ahead to synthesize speech. Lower than `clipDownloadCount` because a render
    /// costs CPU, not just bandwidth, and three cards is more than a listener can outrun.
    private let speechRenderAheadCount = 3

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

    /// Highest index the listener may land on. Past that is locked until they listen.
    private var maxAllowedIndex: Int {
        guard !pages.isEmpty else { return 0 }
        return min(unlockedIndex, pages.count - 1)
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
                    VStack(spacing: 0) {
                        questionHeader
                        voiceDownloadNote
                        feed
                    }
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { browsingQuestions = true } label: {
                        Image(systemName: "text.bubble.fill")
                    }
                    .accessibilityLabel("Browse questions")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showingSettings = true } label: {
                        Image(systemName: "gearshape")
                    }
                    .accessibilityLabel("Settings")
                }
            }
            // A page you go to, not a sheet that covers the feed: browsing the library is a
            // place of its own, with room for a search field, the categories, and enough of
            // each question to recognise it.
            .navigationDestination(isPresented: $browsingQuestions) {
                QuestionBrowseView(
                    questions: questions,
                    answers: answers,
                    currentQuestionID: currentQuestion?.id,
                    onSelect: { select(questionID: $0, completingCurrent: false) }
                )
            }
            // Settings is a sheet, not a page: it's a quick knob you flick and dismiss, and
            // keeping it off the navigation stack leaves the feed's own state untouched.
            .sheet(isPresented: $showingSettings) {
                SettingsView(settings: speechSettings)
            }
            .task(id: currentPageID) { await prepareAndPlayCurrent() }
            .onAppear {
                if !didInitialLoad {
                    didInitialLoad = true
                    restore()
                    // Pull the Kokoro weights in the background. Until they land, answers are
                    // read by AVSpeechSynthesizer, so the feed works from the first launch —
                    // it just gets a better voice partway through.
                    speech.ensureDownloaded()
                }
            }
            .onChange(of: answers.answers) { _, _ in rebuildClips() }
            .onChange(of: questions.questions) { _, _ in rebuildClips() }
            .onChange(of: player.finishedItemID) { _, finished in
                guard let finished else { return }
                // Unlock first: the page we're about to move onto has to be earned before
                // landing on it, or `handleLanding` would bounce us straight back off it.
                unlockNextPage(afterHearing: finished)
                advanceToNextPage(afterHearing: finished)
            }
            .onChange(of: currentPageID) { _, newID in handleLanding(on: newID) }
            // A speed change made mid-card should be heard now, not on the next one. New
            // cards read the setting on their own when they start playing.
            .onChange(of: speechSettings.speed) { _, _ in player.updatePlaybackSpeed() }
            .onDisappear { lockMessageTask?.cancel() }
        }
    }

    /// The question being argued, under the toolbar rather than in it. In the toolbar it
    /// was squeezed into the inline title slot — one truncated line, crowded against the
    /// status bar. Here it has the room to be read in full before you hear anyone argue it.
    private var questionHeader: some View {
        Text(currentQuestion?.prompt ?? "")
            .font(.headline)
            .multilineTextAlignment(.center)
            .lineLimit(3)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 20)
            .padding(.top, 8)
            .padding(.bottom, 18)
    }

    /// While the Kokoro weights come down, answers are read by the old system voice. Say so,
    /// otherwise the first launch just sounds like the robotic voice we set out to replace.
    @ViewBuilder
    private var voiceDownloadNote: some View {
        if let progress = speech.progress {
            HStack(spacing: 8) {
                ProgressView(value: progress)
                    .progressViewStyle(.linear)
                    .frame(width: 90)
                Text("Downloading the better voice — \(Int(progress * 100))%")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
            }
            .padding(.bottom, 12)
        }
    }

    private var feed: some View {
        // `.scrollPosition(id:)` reliably *reports* where the listener is, but writing to it
        // is not a reliable way to *move* a `.viewAligned(.always)` feed on its own. Paging
        // settles against a real drag, and a hands-free auto-advance — a card finishing with
        // no finger on the screen — would update the bound id without the feed ever scrolling.
        // So the binding stays for reading the listener's position, and every programmatic
        // move is performed for real through the ScrollViewReader proxy below.
        ScrollViewReader { proxy in
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
            // Drive the actual scroll whenever the target page changes: the feed auto-advancing
            // off a finished card, a bounce back from a locked peek, or a question handoff. When
            // the change came from the listener's own swipe the target is already the settled
            // page, so this is a no-op; when it came from code, this is what moves the feed.
            .onChange(of: currentPageID) { _, target in
                guard let target else { return }
                withAnimation(.snappy) { proxy.scrollTo(target, anchor: .top) }
            }
            // A question handoff sets `currentPageID` to the value it already holds (the
            // trailing next-question card and the incoming question's page 0 share an id), so
            // the change-driven scroll above never fires — yet the feed content was rebuilt
            // under the same scroll offset, drifting the viewport onto the first answer. This
            // re-anchors to the question card for real after that rebuild.
            .onChange(of: feedScrollNonce) { _, _ in
                guard let target = currentPageID else { return }
                withAnimation(.snappy) { proxy.scrollTo(target, anchor: .top) }
            }
        }
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

    /// A page played out. It earns the *next* page only if it was the page the listener was
    /// actually gated on — finishing something behind them (a clip they scrolled back to,
    /// or one that was still playing while they wandered off) opens nothing.
    private func unlockNextPage(afterHearing pageID: UUID) {
        guard pages.indices.contains(maxAllowedIndex),
              pages[maxAllowedIndex].id == pageID,
              unlockedIndex < pages.count - 1 else { return }
        unlockedIndex = maxAllowedIndex + 1
        persist()
    }

    /// A page played out — roll straight onto the next one. Listening is the whole loop, so
    /// hearing something to the end is the listener asking for what comes after it: the
    /// question card hands you the first argument, an argument hands you the next one, and
    /// the last argument of a question hands you the next question's card (where
    /// `handleLanding` completes the handoff into that question). Scrolling still works; it
    /// just isn't the only way forward anymore.
    ///
    /// Only the page the listener is *on* advances. A card that finishes behind them — one
    /// they scrolled back from, or that was still playing when they swiped away — must not
    /// yank the feed somewhere they didn't ask to be.
    private func advanceToNextPage(afterHearing pageID: UUID) {
        guard currentPageID == pageID,
              let idx = pages.firstIndex(where: { $0.id == pageID }),
              pages.indices.contains(idx + 1),
              // Belt and braces: never auto-land on a page the listener hasn't earned. In
              // practice `unlockNextPage` just earned it, but the two rules stay independent.
              idx + 1 <= maxAllowedIndex else { return }

        withAnimation(.snappy) {
            currentPageID = pages[idx + 1].id
        }
    }

    private func select(questionID: UUID, completingCurrent: Bool) {
        if completingCurrent, let current = currentQuestion?.id {
            completedQuestionIDs.insert(current)
        }
        selectedQuestionID = questionID
        // A question is always entered from the top: its card has to be read out before
        // anything behind it opens up, whether this is the first time through or the fifth.
        // Coming back around the loop re-locks the feed — that is the point of the loop.
        unlockedIndex = 0
        rebuildClips()
        // The question's card is page 0, and it carries the question's id — so when this
        // came from scrolling onto the trailing card, the listener is already on it. But that
        // makes the assignment a no-op, and the feed's change-driven scroll won't re-anchor
        // after the deck rebuild above shifts the layout under the preserved scroll offset —
        // leaving the viewport on the first answer. Bump the nonce to scroll back to the card
        // for real, so the question is read before anything auto-advances off it.
        currentPageID = questionID
        feedScrollNonce += 1
        persist()
    }

    /// The listener scrolled onto the locked peek page. Let them see it, then bounce them
    /// back to the page they still owe a listen to, and say why.
    private func bounceBackToCurrent() {
        guard pages.indices.contains(maxAllowedIndex) else { return }
        let allowedID = pages[maxAllowedIndex].id
        // Assigned unconditionally. The old code skipped the write when the state already
        // said `allowedID` — but the scroll view ignores a programmatic position change made
        // while a finger is down, so state and view drift apart exactly when someone is
        // swiping hard, and the skip then made every later bounce a no-op.
        withAnimation(.snappy) {
            showLockMessage = true
            currentPageID = allowedID
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
            completedQuestionIDs = Set(snapshot.completedQuestionIDs)
            if let saved = snapshot.selectedQuestionID, questions.question(id: saved) != nil {
                selectedQuestionID = saved
            }
        }
        rebuildClips()
        // Hand back the place they earned, but never more feed than there is now — the deck
        // is rebuilt from the answers, and those can have changed while the app was away.
        unlockedIndex = min(max(snapshot?.unlockedIndex ?? 0, 0), max(pages.count - 1, 0))
        // And never resume *past* the lock: a saved page beyond what's been unlocked would
        // drop them straight onto a locked page.
        if let saved = snapshot?.currentPageID,
           let idx = pages.firstIndex(where: { $0.id == saved }),
           idx <= maxAllowedIndex {
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
            unlockedIndex: unlockedIndex,
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
        renderSpeechAhead(upcoming)
    }

    /// Synthesize the next few text answers while the current card is playing.
    ///
    /// Kokoro takes seconds on a long argument, so this is what keeps the good voice from
    /// costing a stall: by the time you swipe, the WAV is already on disk and the card
    /// starts instantly. Only the very first card of a session can outrun it. Renders are
    /// cached and de-duplicated inside `SpeechRenderer`, so re-issuing these is cheap.
    private func renderSpeechAhead(_ upcoming: [ArgumentClip]) {
        guard SpeechRenderer.isAvailable else { return }
        let pending = upcoming
            .filter { $0.audioURL == nil }
            .prefix(speechRenderAheadCount)
            .map(\.answerText)
        guard !pending.isEmpty else { return }
        Task.detached(priority: .utility) {
            for text in pending {
                _ = await SpeechRenderer.shared.render(text)
            }
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

/// Full-bleed page: the transcript of what this person said, and the transport that plays
/// it (play/pause + skip back only). No artwork and no title — an argument has neither.
/// The bar is a read-only indicator — there is no scrubbing and no skip-forward. The
/// question isn't repeated here: it's in the header, and it opened the question.
private struct ArgumentFeedCard: View {
    let clip: ArgumentClip
    let isCurrent: Bool
    /// The peek page: visible so the user knows more is coming, but not yet earned.
    let isLocked: Bool
    @ObservedObject var player: ClipPreviewPlayer

    var body: some View {
        // The page is now the full-screen video with the transcript over it. Only the
        // current card decodes frames; the peek/off-screen cards keep the player paused.
        VideoBackdrop(isActive: isCurrent) {
            NowPlayingContent(
                transcript: clip.answerText,
                currentTime: isCurrent ? player.progress : 0,
                duration: isCurrent ? player.duration : max(clip.duration, 1),
                bufferedTime: isCurrent ? player.bufferedProgress : 0,
                // Only the active card mirrors real engine state — other pages stay on "play".
                isPlaying: isCurrent && player.isPlaying,
                // Kokoro is still synthesizing this answer — spin rather than show a play button
                // that would do nothing.
                isLoading: isCurrent && player.isPreparing,
                showSkipBackward: true,
                onSkipBackward: { guard isCurrent else { return }; player.skipBackward() },
                onTogglePlayPause: { guard isCurrent else { return }; player.togglePlayPause() },
                errorMessage: isCurrent ? player.errorMessage : nil,
                accent: SteelmanTheme.color(for: clip.side),
                badge: clip.containsProfanity ? "Profanity" : nil,
                badgeColor: SteelmanTheme.danger
            )
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .overlay { if isLocked { LockedPeekOverlay() } }
    }
}

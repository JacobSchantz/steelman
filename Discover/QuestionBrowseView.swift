import SwiftUI

/// The question library — a page you go to, not a sheet that half-covers the feed.
///
/// It replaced a medium-detent sheet that could show three rows and had nowhere to put a
/// search field. As a page it has the room to be read: each question is a card carrying
/// what's being asked, the two sides it's asked between, and the category it sits in.
///
/// Two ways to narrow it down, and they compose. Typing matches the question, its context,
/// its side labels and its category, so you can find "remote work" by any of the words you
/// actually remember. Tapping a category filters to it, and a search then runs *within* that
/// category. The category row is built from the categories questions actually wear — there
/// is no list to maintain, and a category nothing uses simply isn't there.
struct QuestionBrowseView: View {
    @ObservedObject var questions: QuestionStore
    @ObservedObject var answers: AnswerStore
    let currentQuestionID: UUID?
    let onSelect: (UUID) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var search = ""
    @State private var selectedCategory: String?
    @State private var addingQuestion = false

    /// Every search word has to land somewhere on the question, so extra words narrow rather
    /// than widen — "remote office" finds the question carrying both, not everything
    /// carrying either.
    private var results: [Question] {
        let terms = search
            .lowercased()
            .split(whereSeparator: \.isWhitespace)
            .map(String.init)

        return questions.questions.filter { question in
            if let selectedCategory,
               question.normalizedCategory?.caseInsensitiveCompare(selectedCategory) != .orderedSame {
                return false
            }
            guard !terms.isEmpty else { return true }
            let haystack = question.searchText
            return terms.allSatisfy { haystack.contains($0) }
        }
    }

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 12) {
                ForEach(results) { question in
                    card(for: question)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 24)
        }
        .background(Color(.systemGroupedBackground))
        .overlay { if results.isEmpty { noResults } }
        .safeAreaInset(edge: .top) { categoryBar }
        .safeAreaInset(edge: .bottom) { buildStamp }
        .searchable(
            text: $search,
            placement: .navigationBarDrawer(displayMode: .always),
            prompt: "Search questions"
        )
        .navigationTitle("Questions")
        .navigationBarTitleDisplayMode(.large)
        // `NewQuestionSheet` has been in the project without an entry point since the tabs
        // went away, which left no way to file a question under a category. The library is
        // where you'd look to add one, so that's where the button goes.
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { addingQuestion = true } label: {
                    Image(systemName: "plus")
                }
                .accessibilityLabel("New question")
            }
        }
        .sheet(isPresented: $addingQuestion) {
            NewQuestionSheet(store: questions)
        }
    }

    // MARK: - Cards

    private func card(for question: Question) -> some View {
        let isCurrent = question.id == currentQuestionID

        return Button {
            onSelect(question.id)
            dismiss()
        } label: {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 8) {
                    if let category = question.normalizedCategory {
                        chip(category, color: SteelmanTheme.color(forCategory: category), filled: false)
                    }
                    Spacer(minLength: 0)
                    if isCurrent { nowPlayingTag }
                }

                // The serif the feed's question card reads a question in: the browse page
                // should look like the place it sends you.
                Text(question.prompt)
                    .font(.system(.title3, design: .serif).weight(.semibold))
                    .foregroundStyle(.primary)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)

                if !question.detail.isEmpty {
                    Text(question.detail)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.leading)
                        .lineLimit(2)
                }

                HStack(spacing: 6) {
                    chip(question.sideALabel, color: SteelmanTheme.sideA, filled: true)
                    chip(question.sideBLabel, color: SteelmanTheme.sideB, filled: true)
                }

                Text(answerCountText(for: question))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
            .background {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(Color(.secondarySystemGroupedBackground))
                    .overlay {
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .stroke(isCurrent ? SteelmanTheme.accent : .clear, lineWidth: 2)
                    }
            }
        }
        .buttonStyle(.plain)
        .accessibilityHint(isCurrent ? "Now playing" : "Opens this question in the feed")
    }

    private var nowPlayingTag: some View {
        HStack(spacing: 4) {
            Image(systemName: "waveform")
            Text("Now playing")
        }
        .font(.caption2.weight(.bold))
        .foregroundStyle(SteelmanTheme.accent)
    }

    /// A side label reads as a claim ("Ban cars downtown"), so it's filled. A category is a
    /// label on the question rather than a position in it, so it's outlined.
    private func chip(_ text: String, color: Color, filled: Bool) -> some View {
        Text(text)
            .font(.caption2.weight(.semibold))
            .lineLimit(1)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .foregroundStyle(color)
            .background {
                if filled {
                    Capsule().fill(color.opacity(0.15))
                } else {
                    Capsule().strokeBorder(color.opacity(0.55), lineWidth: 1)
                }
            }
    }

    private func answerCountText(for question: Question) -> String {
        let count = answers.answers(for: question.id).count
        switch count {
        case 0: return "No answers yet"
        case 1: return "1 answer"
        default: return "\(count) answers"
        }
    }

    // MARK: - Categories

    /// Hidden entirely when nothing is categorised — an empty filter row is a row whose only
    /// message is that the feature exists.
    @ViewBuilder
    private var categoryBar: some View {
        let categories = questions.categories
        if !categories.isEmpty {
            ScrollView(.horizontal) {
                HStack(spacing: 8) {
                    categoryButton(title: "All", color: .secondary, isOn: selectedCategory == nil) {
                        selectedCategory = nil
                    }
                    ForEach(categories, id: \.self) { category in
                        categoryButton(
                            title: category,
                            color: SteelmanTheme.color(forCategory: category),
                            isOn: selectedCategory == category
                        ) {
                            // Tapping the category you're already in is how you get back out.
                            selectedCategory = selectedCategory == category ? nil : category
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
            }
            .scrollIndicators(.hidden)
            .background(.bar)
        }
    }

    private func categoryButton(
        title: String,
        color: Color,
        isOn: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .lineLimit(1)
                .padding(.horizontal, 14)
                .padding(.vertical, 7)
                .foregroundStyle(isOn ? Color(.systemBackground) : color)
                .background {
                    Capsule().fill(isOn ? AnyShapeStyle(color) : AnyShapeStyle(color.opacity(0.12)))
                }
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isOn ? [.isButton, .isSelected] : .isButton)
    }

    // MARK: - Empty state + footer

    @ViewBuilder
    private var noResults: some View {
        if !search.isEmpty {
            ContentUnavailableView.search(text: search)
        } else if let selectedCategory {
            ContentUnavailableView {
                Label("Nothing in \(selectedCategory)", systemImage: "tray")
            } description: {
                Text("No questions are filed under this category.")
            }
        } else {
            ContentUnavailableView {
                Label("No questions yet", systemImage: "text.bubble")
            } description: {
                Text("Add a question and it shows up here.")
            }
        }
    }

    /// The build stamp used to live on the Rules tab; the tabs are gone, so it lives here.
    @ViewBuilder
    private var buildStamp: some View {
        if GitInfo.shortHash != "unknown" {
            Text("Build \(GitInfo.shortHash) · \(GitInfo.branch)")
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .background(.bar)
        }
    }
}

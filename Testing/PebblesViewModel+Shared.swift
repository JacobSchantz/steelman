import PebblesKit

extension PebblesViewModel {
    /// App-wide Pebbles overlay model. Reads/writes human-testing items under
    /// `pebbles/` in the GitHub repo, and stamps this build's commit so the
    /// overlay can flag when a fix hasn't landed yet.
    static let shared = PebblesViewModel(config: PebblesConfig(
        githubRepo: "JacobSchantz/steelman",
        patKey: "github_pat_for_steelman_testables",
        pebblesPath: "pebbles",
        currentCommitHash: GitInfo.fullHash,
        currentCommitMessage: GitInfo.lastCommitMessage,
        commitCount: GitInfo.commitCount,
        iconMapping: [
            "discover": "sparkles",
            "question": "text.bubble.fill",
            "answer": "mic.badge.plus",
            "rules": "book.closed.fill",
        ],
        defaultIcon: "shield.lefthalf.filled"
    ))
}

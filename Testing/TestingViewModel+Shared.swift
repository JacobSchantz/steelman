import TestablesKit

extension TestingViewModel {
    /// App-wide Testables overlay model. Reads/writes human-testing items under
    /// `testables/` in the GitHub repo, and stamps this build's commit so the
    /// overlay can flag when a fix hasn't landed yet.
    static let shared = TestingViewModel(config: TestablesConfig(
        githubRepo: "JacobSchantz/steelman",
        patKey: "github_pat_for_steelman_testables",
        testablesPath: "testables",
        currentCommitHash: GitInfo.fullHash,
        currentCommitMessage: GitInfo.lastCommitMessage,
        commitCount: GitInfo.commitCount,
        iconMapping: [
            "rules": "book.closed.fill",
            "session": "bubble.left.and.bubble.right.fill",
            "rebuttal": "arrow.triangle.branch",
        ],
        defaultIcon: "shield.lefthalf.filled"
    ))
}

import Foundation
import TestablesKit

enum SteelmanConfig {
    static let testablesConfig = TestablesConfig(
        githubRepo: "JacobSchantz/steelman",
        githubBranch: "main",
        patKey: "github_pat_for_steelman_testables",
        testablesPath: "testables",
        currentCommitHash: GitInfo.fullHash,
        currentCommitMessage: GitInfo.lastCommitMessage,
        commitCount: GitInfo.commitCount,
        defaultIcon: "shield.lefthalf.filled"
    )
}

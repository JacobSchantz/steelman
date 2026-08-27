import Foundation
import PebblesKit

enum SteelmanConfig {
    static let pebblesConfig = PebblesConfig(
        githubRepo: "JacobSchantz/steelman",
        githubBranch: "main",
        patKey: "github_pat_for_steelman_testables",
        pebblesPath: "pebbles",
        currentCommitHash: GitInfo.fullHash,
        currentCommitMessage: GitInfo.lastCommitMessage,
        commitCount: GitInfo.commitCount,
        defaultIcon: "shield.lefthalf.filled"
    )
}

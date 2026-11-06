// Ported from SwiftCode-Legacy `SwiftCode/Backend/GitHub/GitCommands.swift`
// (Dylan's own code; direct port authorised under MIT).
//
// Legacy `GitCommands` drove whole-project GitHub sync off its `Project`
// model (`githubRepo` URL + `ProjectSessionStore` refresh), which does not
// exist in SwiftCode. Most of its surface is already covered in the
// destination, against a plain directory / owner+repo instead of a
// `Project`:
//
// - `push(project:commitMessage:)` → `GitHubProjectSync.pushDirectory`
// - `pushFile(path:content:commitMessage:project:)` → `GitHubClient.pushFile`
//   (after `GitHubClient.getFileSHA`)
// - `listBranches(for:)` → `GitHubClient.listBranches`
// - `recentCommits(for:branch:count:)` → `GitHubClient.listCommits`
// - `pull(project:branch:)` → `GitHubProjectSync.pullDirectory`
//   (staged alongside this file — see `GitHubProjectSync.swift`).
//
// This file stages the one remaining piece: `GitCommandsError`,
// Legacy's typed errors (`missingRemote` / `pushFailed` / `pullFailed`),
// for callers that drive the sync operations and need to distinguish a
// missing remote from a failed transfer.

import Foundation

/// Typed errors for whole-project GitHub sync (Legacy `GitCommandsError`).
public enum GitCommandsError: LocalizedError, Sendable {
    case missingRemote
    case pushFailed(String)
    case pullFailed(String)

    public var errorDescription: String? {
        switch self {
        case .missingRemote:
            return "No GitHub repository is linked to this project. Please set a repository URL in the GitHub settings."
        case .pushFailed(let reason):
            return "Push Failed: \(reason)"
        case .pullFailed(let reason):
            return "Pull Failed: \(reason)"
        }
    }
}

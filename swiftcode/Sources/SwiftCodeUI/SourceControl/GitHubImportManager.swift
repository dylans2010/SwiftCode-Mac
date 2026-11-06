// Ported from Legacy (Dylan's own SwiftCode code, MIT-authorised direct port):
//   SwiftCode/Core/GitHub/GitHubImportManager.swift — `GitHubImportManager`
//   (Legacy main ab03f681).
//
// Destination: SwiftCodeUI/SourceControl/GitHubImportManager.swift (with
// `GitHubImporter.swift` in the same directory).
//
// Verbatim facade over `GitHubImporter.shared`, adapted `Project` ->
// `SCProject` only. See `GitHubImporter.swift` for why the audit's
// COVERED claim for this file was wrong (no `GitHubImport.swift`,
// `GitHubImporter`, or `GitHubAuth` exists in main) and for the
// adaptation notes.

import Foundation

public final class GitHubImportManager: Sendable {
    public static let shared = GitHubImportManager()
    private init() {}

    // MARK: - Import from URL
    public func importRepository(from urlString: String, branch: String = "main") async throws -> SCProject {
        try await GitHubImporter.shared.importRepository(from: urlString, branch: branch)
    }

    public func importRepository(owner: String, repo: String, branch: String = "main") async throws -> SCProject {
        try await GitHubImporter.shared.importRepository(owner: owner, repo: repo, branch: branch)
    }
}

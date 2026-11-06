// STAGED PORT — SwiftCode-Legacy `SwiftCode/Backend/Assist/Models/AssistSnapshotModels.swift` (main ab03f681; Dylan's own code, direct port authorised under MIT).
// Staged by migration subagent A3 (Assist systems / tools / execution) — NOT yet landed in the repo.
// Target: SwiftCodeAssistant (`swiftcode/Sources/SwiftCodeAssistant/Snapshots/AssistSnapshotModels.swift`).
// Body is Legacy verbatim unless noted under ADAPTATIONS below. No Swift toolchain exists
// in this environment: static checks only — never claim a build passed.
// Audit gap this port closes (claimed-covered-audit):
//   - AssistFileDiff type (path/status/changes vs a snapshot)
//   - listSnapshots() reading AssistSnapshotMetadata
// ADAPTATIONS: none — verbatim body (imports adjusted only as noted).
// UNRESOLVED DEPENDENCIES: none found by static scan (SwiftUI/Foundation/Apple-framework names excluded).
// WIRING / REGISTRATION: None (library type) — consumed by Assist session/agent code and, for tool-adjacent types, by SwiftCodeMCP.

import Foundation

public struct AssistSnapshotMetadata: Codable {
    public let id: String
    public let timestamp: Date
    public let message: String
    public let rootPath: String
}

public struct AssistFileDiff: Codable {
    public let path: String
    public let status: DiffStatus
    public let changes: String // Simplified diff string

    public enum DiffStatus: String, Codable {
        case added
        case modified
        case deleted
    }
}

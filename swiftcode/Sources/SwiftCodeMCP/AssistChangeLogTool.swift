// STAGED PORT — SwiftCode-Legacy `SwiftCode/Backend/Assist/Tools/AssistChangeLogTool.swift` (main ab03f681; Dylan's own code, direct port authorised under MIT).
// Staged by migration subagent A3 (Assist systems / tools / execution) — NOT yet landed in the repo.
// Target: SwiftCodeMCP (`swiftcode/Sources/SwiftCodeMCP/AssistChangeLogTool.swift`).
// Body is Legacy verbatim unless noted under ADAPTATIONS below. No Swift toolchain exists
// in this environment: static checks only — never claim a build passed.
// Audit gap this port closes (claimed-covered-audit):
//   - Snapshot history is never populated: SwiftCode has no AssistSnapshotFunctions equivalent that creates snapshots, so project_changelog always reports 'No snapshot history found.'
// ADAPTATIONS:
//   - Added cross-target import(s): import SwiftCodeAssistant (destination module exists; types resolve as the owning ports land).
// UNRESOLVED DEPENDENCIES (no definition in the destination yet; resolve as the owning ports land):
//   - ToolCapability — A6 (ALL-MISSING) (`SwiftCode/Backend/Assist/AssistToolRouter.swift`)
//   - ToolRiskLevel — A6 (ALL-MISSING) (`SwiftCode/Backend/Assist/AssistToolRouter.swift`)
// WIRING / REGISTRATION: MCP catalogue: swiftcode/Sources/SwiftCodeMCP/SwiftCodeTools+SPMDocs.swift — wire the matching MCP tool handler to this legacy class (or adopt its behaviour); AssistToolRegistry (staged) is the dynamic registry for register/unregister + health + caching once tools land.

import Foundation
import SwiftCodeAssistant

public struct AssistChangeLogTool: AssistTool {
    public let id = "project_changelog"
    public let name = "View Changelog"
    public let description = "Displays the history of project snapshots and changes."

    public init() {}

    public var capability: ToolCapability { .general }
    public var riskLevel: ToolRiskLevel { .safeRead }

    public func execute(input: [String: Any], context: AssistContext) async throws -> AssistToolResult {
        do {
            let snapshots = try AssistSnapshotFunctions.listSnapshots()
            let log = snapshots.map { "[\($0.timestamp)] \($0.message) (ID: \($0.id))" }.joined(separator: "\n")
            return .success("Changelog retrieved successfully.", data: ["log": log.isEmpty ? "No snapshot history found." : log])
        } catch {
            return .failure("Failed to retrieve changelog: \(error.localizedDescription)")
        }
    }
}

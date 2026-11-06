// STAGED PORT — SwiftCode-Legacy `SwiftCode/Backend/Assist/Tools/AssistUndoTool.swift` (main ab03f681; Dylan's own code, direct port authorised under MIT).
// Staged by migration subagent A3 (Assist systems / tools / execution) — NOT yet landed in the repo.
// Target: SwiftCodeMCP (`swiftcode/Sources/SwiftCodeMCP/Tools/Assist/AssistUndoTool.swift`).
// Body is Legacy verbatim unless noted under ADAPTATIONS below. No Swift toolchain exists
// in this environment: static checks only — never claim a build passed.
// Audit gap this port closes (claimed-covered-audit):
//   - Whole-project snapshot-based undo (Legacy required at least two snapshots and restored the previous snapshot state)
// ADAPTATIONS:
//   - Added cross-target import(s): import SwiftCodeAssistant (destination module exists; types resolve as the owning ports land).
// UNRESOLVED DEPENDENCIES (no definition in the destination yet; resolve as the owning ports land):
//   - ToolCapability — A6 (ALL-MISSING) (`SwiftCode/Backend/Assist/AssistToolRouter.swift`)
//   - ToolRiskLevel — A6 (ALL-MISSING) (`SwiftCode/Backend/Assist/AssistToolRouter.swift`)
// WIRING / REGISTRATION: MCP catalogue: swiftcode/Sources/SwiftCodeMCP/Tools/SwiftCodeTools+ReviewDocs.swift — wire the matching MCP tool handler to this legacy class (or adopt its behaviour); AssistToolRegistry (staged) is the dynamic registry for register/unregister + health + caching once tools land.

import Foundation
import SwiftCodeAssistant

public struct AssistUndoTool: AssistTool {
    public let id = "safe_undo"
    public let name = "Undo Last Action"
    public let description = "Reverts the last modification made by the agent."

    public init() {}

    public var capability: ToolCapability { .general }
    public var riskLevel: ToolRiskLevel { .potentiallyDestructive }

    public func execute(input: [String: Any], context: AssistContext) async throws -> AssistToolResult {
        do {
            let snapshots = try AssistSnapshotFunctions.listSnapshots()
            guard snapshots.count >= 2 else {
                return .failure("At least two snapshots are required to undo (current baseline + previous state).")
            }
            let previous = snapshots[1]
            try AssistSnapshotFunctions.restoreSnapshot(id: previous.id, to: context.workspaceRoot)
            return .success("Last action undone by restoring snapshot \(previous.id)", data: ["restored_snapshot": previous.id])
        } catch {
            return .failure("Undo failed: \(error.localizedDescription)")
        }
    }
}

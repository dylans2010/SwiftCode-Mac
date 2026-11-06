// STAGED PORT — SwiftCode-Legacy `SwiftCode/Backend/Assist/Tools/AssistContextSnapshotTool.swift` (main ab03f681; Dylan's own code, direct port authorised under MIT).
// Staged by migration subagent A3 (Assist systems / tools / execution) — NOT yet landed in the repo.
// Target: SwiftCodeMCP (`swiftcode/Sources/SwiftCodeMCP/Tools/Assist/AssistContextSnapshotTool.swift`).
// Body is Legacy verbatim unless noted under ADAPTATIONS below. No Swift toolchain exists
// in this environment: static checks only — never claim a build passed.
// Audit gap this port closes (claimed-covered-audit):
//   - Latest-snapshot lookup: Legacy reported the id of the newest AssistSnapshotFunctions snapshot; destination always reports latest_snapshot 'none' because SwiftCode has no snapshot store.
// ADAPTATIONS:
//   - Added cross-target import(s): import SwiftCodeAssistant (destination module exists; types resolve as the owning ports land).
// UNRESOLVED DEPENDENCIES (no definition in the destination yet; resolve as the owning ports land):
//   - ToolCapability — A6 (ALL-MISSING) (`SwiftCode/Backend/Assist/AssistToolRouter.swift`)
//   - ToolRiskLevel — A6 (ALL-MISSING) (`SwiftCode/Backend/Assist/AssistToolRouter.swift`)
// WIRING / REGISTRATION: MCP catalogue: swiftcode/Sources/SwiftCodeMCP/Tools/SwiftCodeTools+Memory.swift — wire the matching MCP tool handler to this legacy class (or adopt its behaviour); AssistToolRegistry (staged) is the dynamic registry for register/unregister + health + caching once tools land.

import Foundation
import SwiftCodeAssistant

public struct AssistContextSnapshotTool: AssistTool {
    public let id = "mem_context_snapshot"
    public let name = "Context Snapshot"
    public let description = "Captures a snapshot of the current environment and open files for future reference."

    public init() {}

    public var capability: ToolCapability { .memory }
    public var riskLevel: ToolRiskLevel { .safeMutation }

    public func execute(input: [String: Any], context: AssistContext) async throws -> AssistToolResult {
        do {
            let snapshots = try AssistSnapshotFunctions.listSnapshots()
            let latestSnapshot = snapshots.first?.id ?? "none"
            let memoryMarker = UUID().uuidString
            let payload = "session=\(context.sessionId.uuidString)\nworkspace=\(context.workspaceRoot.path)\nlatest_snapshot=\(latestSnapshot)"
            context.memory.store(key: "context_snapshot:\(memoryMarker)", value: payload)
            return .success("Context snapshot captured", data: ["snapshot_key": "context_snapshot:\(memoryMarker)", "latest_snapshot": latestSnapshot])
        } catch {
            return .failure("Failed capturing context snapshot: \(error.localizedDescription)")
        }
    }
}

// STAGED PORT — SwiftCode-Legacy `SwiftCode/Backend/Assist/AssistSession.swift` (main ab03f681; Dylan's own code, direct port authorised under MIT).
// Staged by migration subagent A3 (Assist systems / tools / execution) — NOT yet landed in the repo.
// Target: SwiftCodeAssistant (`swiftcode/Sources/SwiftCodeAssistant/Agents/AssistSession.swift`).
// Body is Legacy verbatim unless noted under ADAPTATIONS below. No Swift toolchain exists
// in this environment: static checks only — never claim a build passed.
// Audit gap this port closes (claimed-covered-audit):
//   - AssistSession type (id/startTime)
//   - plan history array
//   - addPlan / reset
// ADAPTATIONS: none — verbatim body (imports adjusted only as noted).
// UNRESOLVED DEPENDENCIES: none found by static scan (SwiftUI/Foundation/Apple-framework names excluded).
// WIRING / REGISTRATION: None (library type) — consumed by Assist session/agent code and, for tool-adjacent types, by SwiftCodeMCP.

import Foundation
import Observation

@Observable
@MainActor
public final class AssistSession: Sendable {
    public let id: UUID
    public let startTime: Date
    public var currentPlan: AssistExecutionPlan?
    public var history: [AssistExecutionPlan] = []

    public init() {
        self.id = UUID()
        self.startTime = Date()
    }

    public func addPlan(_ plan: AssistExecutionPlan) {
        currentPlan = plan
        history.append(plan)
    }

    public func reset() {
        currentPlan = nil
        history.removeAll()
    }
}

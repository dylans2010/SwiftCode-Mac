// STAGED PORT — SwiftCode-Legacy `SwiftCode/Backend/Assist/API/Internal API/AssistAPI.swift` (main ab03f681; Dylan's own code, direct port authorised under MIT).
// Staged by migration subagent A3 (Assist systems / tools / execution) — NOT yet landed in the repo.
// Target: SwiftCodeAssistant (`swiftcode/Sources/SwiftCodeAssistant/API/AssistAPI.swift`).
// Body is Legacy verbatim unless noted under ADAPTATIONS below. No Swift toolchain exists
// in this environment: static checks only — never claim a build passed.
// Audit gap this port closes (claimed-covered-audit):
//   - AssistAPI singleton entry point
//   - configure(context:) / request(_:) dispatch
// ADAPTATIONS: none — verbatim body (imports adjusted only as noted).
// UNRESOLVED DEPENDENCIES (no definition in the destination yet; resolve as the owning ports land):
//   - AssistAPIRequest — A6 (ALL-MISSING) (`SwiftCode/Backend/Assist/API/Internal API/AssistAPIRequest.swift`)
//   - AssistAPIResponse — UNOWNED (no worklist) (`SwiftCode/Backend/Assist/API/Internal API/AssistAPIResponse.swift`)
// WIRING / REGISTRATION: None (library type) — consumed by Assist session/agent code and, for tool-adjacent types, by SwiftCodeMCP.

import Foundation

@MainActor
public final class AssistAPI {
    public static let shared = AssistAPI()
    private init() {}

    private var router: AssistAPIRouter?

    public func configure(context: AssistContext) {
        self.router = AssistAPIRouter(context: context)
    }

    /// Primary entry point for all Assist backend operations.
    public func request(_ apiRequest: AssistAPIRequest) async -> AssistAPIResponse {
        guard let router = router else {
            return .failure(error: "AssistAPI is not configured. Call configure(context:) first.")
        }
        return await router.route(apiRequest)
    }

    /// Convenience methods for common operations.
    public func plan(intent: String) async -> AssistAPIResponse {
        let request = AssistAPIRequest(route: .plan, payload: ["intent": intent])
        return await self.request(request)
    }

    public func execute(plan: AssistExecutionPlan) async -> AssistAPIResponse {
        do {
            let data = try JSONEncoder().encode(plan)
            let planStr = String(data: data, encoding: .utf8) ?? ""
            let request = AssistAPIRequest(route: .execute, payload: ["plan": planStr])
            return await self.request(request)
        } catch {
            return .failure(error: "Failed to encode plan: \(error.localizedDescription)")
        }
    }

    public func analyze() async -> AssistAPIResponse {
        let request = AssistAPIRequest(route: .analyze, payload: [:])
        return await self.request(request)
    }

    public func createFile(path: String, content: String) async -> AssistAPIResponse {
        let request = AssistAPIRequest(route: .createFile, payload: ["path": path, "content": content])
        return await self.request(request)
    }

    public func modifyFile(path: String, content: String) async -> AssistAPIResponse {
        let request = AssistAPIRequest(route: .modifyFile, payload: ["path": path, "content": content])
        return await self.request(request)
    }

    public func enhancePrompt(userInput: String) async -> AssistAPIResponse {
        let request = AssistAPIRequest(route: .enhancePrompt, payload: ["userInput": userInput])
        return await self.request(request)
    }
}

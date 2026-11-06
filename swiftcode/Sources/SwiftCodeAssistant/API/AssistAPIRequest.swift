// Ported from Legacy `SwiftCode/Backend/Assist/API/Internal API/AssistAPIRequest.swift` (main ab03f681; Dylan's own code, direct port authorised under MIT).
// Staged only — not yet merged into swiftcode/Sources. See staging-wire/missing/DISPOSITIONS.md.
// Verbatim. Self-contained request/route model for the internal Assist API.
// Wiring: the internal API route handlers consume it; no destination caller
// exists yet.

import Foundation

public struct AssistAPIRequest: Codable {
    public let route: AssistAPIRoute
    public let payload: [String: String]
    public let sessionId: String?

    public init(route: AssistAPIRoute, payload: [String: String], sessionId: String? = nil) {
        self.route = route
        self.payload = payload
        self.sessionId = sessionId
    }
}

public enum AssistAPIRoute: String, Codable {
    case plan
    case execute
    case analyze
    case createFile
    case modifyFile
    case enhancePrompt
}

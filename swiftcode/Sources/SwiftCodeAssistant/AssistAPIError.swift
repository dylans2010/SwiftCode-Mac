// Ported from Legacy `SwiftCode/Backend/Assist/API/Internal API/AssistAPIError.swift` (main ab03f681; Dylan's own code, direct port authorised under MIT).
// Staged only — not yet merged into swiftcode/Sources. See staging-wire/missing/DISPOSITIONS.md.
// Verbatim. Self-contained five-case error taxonomy for the internal Assist
// API. Wiring: the internal API route handlers (AssistAPIRequest routes)
// consume it; no destination caller exists yet.

import Foundation

public enum AssistAPIError: LocalizedError {
    case invalidRoute(String)
    case invalidPayload(String)
    case executionFailed(String)
    case fileSystemError(String)
    case authenticationError(String)

    public var errorDescription: String? {
        switch self {
        case .invalidRoute(let route): return "Invalid API Route: \(route)"
        case .invalidPayload(let details): return "Invalid Payload: \(details)"
        case .executionFailed(let error): return "Execution Failed: \(error)"
        case .fileSystemError(let error): return "File System Error: \(error)"
        case .authenticationError(let details): return "Authentication Error: \(details)"
        }
    }
}

import Foundation

// MARK: - SDKAPIKeySessionAuth
//
// Ported from Legacy `SwiftCode/SDK/Host/APIKeys/SDKAPIKeySessionAuth.swift`
// (Dylan's own code; direct port authorised under MIT).
//
// A runtime session may present a developer API key through the
// `SWIFTCODE_API_KEY` environment variable. The secret is toxic: it is
// never persisted or logged, and only the key store may verify it.

public enum SDKAPIKeySessionAuth {
    /// The environment variable carrying a session-presented developer key.
    public static let environmentVariable = "SWIFTCODE_API_KEY"

    /// Reads the presented key from `environment` (defaults to the
    /// process environment). Returns `nil` when absent or blank after
    /// trimming. The returned string is the raw secret — handle it as
    /// toxic: verify it, then drop it.
    public static func presentedKeyFromEnvironment(
        _ environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> String? {
        guard let raw = environment[environmentVariable]?.trimmingCharacters(in: .whitespacesAndNewlines),
              !raw.isEmpty else { return nil }
        return raw
    }
}

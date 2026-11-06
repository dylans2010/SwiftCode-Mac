import Foundation

// MARK: - SDKLogRedaction
//
// Ported from Legacy `SwiftCode/SDK/Runtime/Diagnostics/SDKLogRedaction.swift`
// (Dylan's own code; direct port authorised under MIT).
//
// Pure redaction for anything that reaches a log, a user-facing
// message, or a diagnostic payload. Secrets are replaced, never
// echoed; long opaque tokens are replaced; absolute paths are
// collapsed; stack frames and memory addresses are removed.

public enum SDKLogRedaction {
    /// Redacts secret shapes from free text: PEM blocks, developer
    /// API keys, GitHub tokens, Slack tokens, `sk-` keys, and inline
    /// `client_secret` values.
    public static func redactSecrets(_ text: String) -> String {
        var result = text
        result = replace(pattern: "-----BEGIN [A-Z ]*PRIVATE KEY-----[\\s\\S]*?-----END [A-Z ]*PRIVATE KEY-----", in: result, with: "<redacted-pem>")
        result = replace(pattern: "sc_dev_(live|test)_[A-Za-z0-9_\\-\\.]+", in: result, with: "<redacted-api-key>")
        result = replace(pattern: "gh[pousr]_[A-Za-z0-9_]+", in: result, with: "<redacted-token>")
        result = replace(pattern: "xox[baprs]-[A-Za-z0-9\\-]+", in: result, with: "<redacted-token>")
        result = replace(pattern: "sk-(live|test)-[A-Za-z0-9]+", in: result, with: "<redacted-token>")
        result = replace(pattern: "sk-[A-Za-z0-9]{16,}", in: result, with: "<redacted-token>")
        result = replace(pattern: "(client_secret[\"'\\s:=]+)[^\"'\\s,}]+", in: result, with: "$1<redacted>")
        return result
    }

    /// Sanitizes text for user-facing display: secrets redacted, stack
    /// frames removed, memory addresses collapsed, absolute paths
    /// collapsed, long opaque tokens replaced, empty lines dropped.
    public static func sanitizeForUser(_ text: String) -> String {
        var result = redactSecrets(text)
        // Stack-frame lines (`#0  0x... in ...`, `at ... (...)`).
        result = replace(pattern: "(?m)^\\s*#\\d+\\s+.*$", in: result, with: "")
        result = replace(pattern: "(?m)^\\s*at\\s+\\S+\\s+\\(.*\\)\\s*$", in: result, with: "")
        // Memory addresses.
        result = replace(pattern: "0x[0-9a-fA-F]+", in: result, with: "<address>")
        // Absolute paths.
        result = replace(pattern: "(/Users/|/private/|/var/|/tmp/|~/)[^\\s\"']*", in: result, with: "<path>")
        // Long opaque tokens: ≥24 base64-ish chars, ≥32 hex chars.
        result = replace(pattern: "\\b[A-Za-z0-9+/=]{24,}\\b", in: result, with: "<redacted>")
        result = replace(pattern: "\\b[0-9a-fA-F]{32,}\\b", in: result, with: "<redacted>")
        let lines = result.split(separator: "\n", omittingEmptySubsequences: false)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        return lines.joined(separator: "\n")
    }

    /// Redacts a diagnostic value by key: sensitive keys
    /// (secret/password/passwd/credential/privatekey/bearer/auth/apikey,
    /// and any key that is or ends with `token`) are replaced wholesale
    /// with `<redacted>`; anything else goes through `redactSecrets`.
    public static func redactDiagnosticValue(key: String, value: String) -> String {
        let lowered = key.lowercased()
        let sensitiveKeys = ["secret", "password", "passwd", "credential", "privatekey", "bearer", "auth", "apikey"]
        if sensitiveKeys.contains(where: { lowered.contains($0) }) || lowered == "token" || lowered.hasSuffix("token") {
            return "<redacted>"
        }
        return redactSecrets(value)
    }

    // MARK: - Private

    private static func replace(pattern: String, in text: String, with replacement: String) -> String {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else { return text }
        let range = NSRange(text.startIndex..., in: text)
        return regex.stringByReplacingMatches(in: text, options: [], range: range, withTemplate: replacement)
    }
}

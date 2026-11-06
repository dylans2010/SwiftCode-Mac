import Foundation

// MARK: - SDKLogRedaction
//
// Shared, pure redaction helpers used by BOTH logging pipelines:
//
//   - SDKUserLogger (user-facing, sanitized) uses `sanitizeForUser(_:)`
//   - SDKDeveloperLogger (developer-facing, verbose) uses `redactSecrets(in:)`
//     and `redactDiagnosticValue(key:value:)` so credential values never reach
//     `~/.swiftcode/logs/developer-sdk.log` even though that stream is allowed
//     to carry filesystem paths and IPC payload summaries.
//
// Every function here is a pure function of its input (no I/O, no global
// state beyond precompiled regexes), so this type is directly unit-testable:
// feed hostile strings in, assert the redacted strings out.

public enum SDKLogRedaction {

    // MARK: - Precompiled patterns

    /// PEM-encoded private key blocks, including embedded newlines.
    private static let privateKeyPattern: NSRegularExpression = {
        // swiftlint:disable:next force_try
        try! NSRegularExpression(
            pattern: #"-----BEGIN [A-Z0-9 ]*PRIVATE KEY-----[\s\S]*?-----END [A-Z0-9 ]*PRIVATE KEY-----"#
        )
    }()

    /// Known secret token shapes. The most specific alternatives come first
    /// so `sk-live-…` is not partially consumed by the generic `sk-…` branch.
    private static let secretTokenPattern: NSRegularExpression = {
        // swiftlint:disable:next force_try
        try! NSRegularExpression(
            pattern: #"\b(?:sc_dev_(?:live|test)_[A-Za-z0-9_\-]{16,}|gh[pousr]_[A-Za-z0-9]{16,}|xox[baprs]-[A-Za-z0-9\-]{12,}|sk-(?:live|test)-[A-Za-z0-9]{16,}|sk-[A-Za-z0-9]{24,})\b"#
        )
    }()

    /// Inline `client_secret` assignments in free text / JSON-ish payloads,
    /// e.g. `"client_secret":"abc123"` or `client_secret=abc123`.
    private static let clientSecretInlinePattern: NSRegularExpression = {
        // swiftlint:disable:next force_try
        try! NSRegularExpression(
            pattern: #"(?i)(["']?client_secret["']?\s*[:=]\s*["']?)([^"'`,\s\}]+)"#
        )
    }()

    /// Long opaque runs that look like unrecognized tokens: base64-ish runs
    /// of 24+ characters (with optional padding) or hex runs of 32+.
    /// Applied to USER-facing text only — the developer log keeps digests.
    private static let longOpaqueTokenPattern: NSRegularExpression = {
        // swiftlint:disable:next force_try
        try! NSRegularExpression(
            pattern: #"\b(?:[A-Za-z0-9+/]{24,}={0,2}|[0-9a-fA-F]{32,})\b"#
        )
    }()

    /// Memory addresses such as `0x00007fff2043a1b0`.
    private static let memoryAddressPattern: NSRegularExpression = {
        // swiftlint:disable:next force_try
        try! NSRegularExpression(
            pattern: #"\b0x[0-9a-fA-F]{4,}\b"#
        )
    }()

    /// Absolute filesystem paths identifying the host user/machine:
    /// `/Users/…`, `/private/…`, `/var/…`, `/tmp/…`, and `~/…`.
    private static let absolutePathPattern: NSRegularExpression = {
        // swiftlint:disable:next force_try
        try! NSRegularExpression(
            pattern: #"(?:(?<!\S)~(?:/[^\s"'`)\]]*)?|/(?:Users|private|var|tmp)/[^\s"'`)\]]*)"#
        )
    }()

    /// Lines that look like stack frames, matched per line:
    /// JS/TS `at …`, node/gdb `#12 …`, macOS crash-log `0  libx  0x…`,
    /// bare `0x… symbol …`, and `frame #0 …`.
    private static let stackFramePatterns: [NSRegularExpression] = [
        #"^\s*at\s+\S.*$"#,
        #"^\s*#\d+\b.*$"#,
        #"^\s*\d+\s+\S+\s+0x[0-9a-fA-F]+\b.*$"#,
        #"^\s*0x[0-9a-fA-F]+\s+\S.*$"#,
        #"^\s*frame\s+#\d+.*$"#,
    ].map {
        // swiftlint:disable:next force_try
        try! NSRegularExpression(pattern: $0, options: [.anchorsMatchLines])
    }

    // MARK: - Core redaction

    /// Redacts credential material embedded anywhere in free text: private
    /// key blocks, known secret token shapes, and inline `client_secret`
    /// values. Safe to apply to developer-log payloads (paths are kept).
    public static func redactSecrets(in text: String) -> String {
        var out = text
        out = replace(out, pattern: privateKeyPattern, with: "<redacted:private-key>")
        out = replace(out, pattern: secretTokenPattern, with: "<redacted>")
        out = replace(out, pattern: clientSecretInlinePattern, with: "$1<redacted>")
        return out
    }

    /// Full user-facing sanitization: secret redaction, stack-trace line
    /// removal, memory-address masking, absolute-path masking, and masking
    /// of long opaque token-looking runs.
    public static func sanitizeForUser(_ text: String) -> String {
        var out = redactSecrets(in: text)

        // Drop stack-trace-looking lines entirely.
        let lines = out.components(separatedBy: "\n")
        out = lines.filter { !isStackFrameLine($0) }.joined(separator: "\n")

        out = replace(out, pattern: memoryAddressPattern, with: "<address>")
        out = replace(out, pattern: absolutePathPattern, with: "<path>")
        out = replace(out, pattern: longOpaqueTokenPattern, with: "<redacted>")

        // Tidy up: strip trailing whitespace per line, drop empties left
        // behind by removed stack frames.
        let cleaned = out.components(separatedBy: "\n").map { line in
            line.replacingOccurrences(of: "[ \\t]+$", with: "", options: .regularExpression)
        }.filter {
            !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        return cleaned.joined(separator: "\n")
    }

    /// Redacts a single diagnostics/context key-value pair for the developer
    /// log. Values under secret-suggestive keys (`client_secret`,
    /// `accessToken`, `apiKey`, …) are replaced wholesale; all other values
    /// keep their content with embedded secrets redacted via `redactSecrets`.
    public static func redactDiagnosticValue(key: String, value: String) -> String {
        guard !value.isEmpty else { return value }
        if isSensitiveDiagnosticKey(key) { return "<redacted>" }
        return redactSecrets(in: value)
    }

    // MARK: - Private helpers

    private static func replace(
        _ text: String,
        pattern: NSRegularExpression,
        with template: String
    ) -> String {
        pattern.stringByReplacingMatches(
            in: text,
            options: [],
            range: NSRange(text.startIndex..<text.endIndex, in: text),
            withTemplate: template
        )
    }

    private static func isStackFrameLine(_ line: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return false }
        let range = NSRange(trimmed.startIndex..<trimmed.endIndex, in: trimmed)
        return stackFramePatterns.contains {
            $0.firstMatch(in: trimmed, options: [], range: range) != nil
        }
    }

    /// Heuristic: the key names a credential. Normalizes away `_`, `-`, `.`
    /// so `client_secret`, `clientSecret`, and `client-secret` all match.
    /// A bare `token` fragment only counts when the key IS or ENDS WITH
    /// "token" (`accessToken`, `session_token`), so counters like
    /// `tokenCount` keep their values.
    private static func isSensitiveDiagnosticKey(_ key: String) -> Bool {
        let normalized = key.lowercased()
            .replacingOccurrences(of: "_", with: "")
            .replacingOccurrences(of: "-", with: "")
            .replacingOccurrences(of: ".", with: "")
        guard !normalized.isEmpty else { return false }
        let fragments = [
            "secret", "password", "passwd", "credential",
            "privatekey", "bearer", "auth", "apikey",
        ]
        if fragments.contains(where: { normalized.contains($0) }) { return true }
        if normalized.contains("token") {
            return normalized == "token" || normalized.hasSuffix("token")
        }
        return false
    }
}

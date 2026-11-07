import Foundation

public enum SDKLogRedaction {

    private static let privateKeyPattern: NSRegularExpression = {
        try! NSRegularExpression(
            pattern: #"-----BEGIN [A-Z0-9 ]*PRIVATE KEY-----[\s\S]*?-----END [A-Z0-9 ]*PRIVATE KEY-----"#
        )
    }()

    private static let secretTokenPattern: NSRegularExpression = {
        try! NSRegularExpression(
            pattern: #"\b(?:sc_dev_(?:live|test)_[A-Za-z0-9_\-]{16,}|gh[pousr]_[A-Za-z0-9]{16,}|xox[baprs]-[A-Za-z0-9\-]{12,}|sk-(?:live|test)-[A-Za-z0-9]{16,}|sk-[A-Za-z0-9]{24,})\b"#
        )
    }()

    private static let clientSecretInlinePattern: NSRegularExpression = {
        try! NSRegularExpression(
            pattern: #"(?i)(["']?client_secret["']?\s*[:=]\s*["']?)([^"'`,\s\}]+)"#
        )
    }()

    private static let longOpaqueTokenPattern: NSRegularExpression = {
        try! NSRegularExpression(
            pattern: #"\b(?:[A-Za-z0-9+/]{24,}={0,2}|[0-9a-fA-F]{32,})\b"#
        )
    }()

    private static let memoryAddressPattern: NSRegularExpression = {
        try! NSRegularExpression(
            pattern: #"\b0x[0-9a-fA-F]{4,}\b"#
        )
    }()

    private static let absolutePathPattern: NSRegularExpression = {
        try! NSRegularExpression(
            pattern: #"(?:(?<!\S)~(?:/[^\s"'`)\]]*)?|/(?:Users|private|var|tmp)/[^\s"'`)\]]*)"#
        )
    }()

    private static let stackFramePatterns: [NSRegularExpression] = [
        #"^\s*at\s+\S.*$"#,
        #"^\s*#\d+\b.*$"#,
        #"^\s*\d+\s+\S+\s+0x[0-9a-fA-F]+\b.*$"#,
        #"^\s*0x[0-9a-fA-F]+\s+\S.*$"#,
        #"^\s*frame\s+#\d+.*$"#,
    ].map {
        try! NSRegularExpression(pattern: $0, options: [.anchorsMatchLines])
    }

    public static func redactSecrets(in text: String) -> String {
        var out = text
        out = replace(out, pattern: privateKeyPattern, with: "<redacted:private-key>")
        out = replace(out, pattern: secretTokenPattern, with: "<redacted>")
        out = replace(out, pattern: clientSecretInlinePattern, with: "$1<redacted>")
        return out
    }

    public static func sanitizeForUser(_ text: String) -> String {
        var out = redactSecrets(in: text)

        let lines = out.components(separatedBy: "\n")
        out = lines.filter { !isStackFrameLine($0) }.joined(separator: "\n")

        out = replace(out, pattern: memoryAddressPattern, with: "<address>")
        out = replace(out, pattern: absolutePathPattern, with: "<path>")
        out = replace(out, pattern: longOpaqueTokenPattern, with: "<redacted>")

        let cleaned = out.components(separatedBy: "\n").map { line in
            line.replacingOccurrences(of: "[ \\t]+$", with: "", options: .regularExpression)
        }.filter {
            !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        return cleaned.joined(separator: "\n")
    }

    public static func redactDiagnosticValue(key: String, value: String) -> String {
        guard !value.isEmpty else { return value }
        if isSensitiveDiagnosticKey(key) { return "<redacted>" }
        return redactSecrets(in: value)
    }

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

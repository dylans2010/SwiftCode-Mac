import Foundation

public enum SDKLogRedaction {
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

    public static func sanitizeForUser(_ text: String) -> String {
        var result = redactSecrets(text)
        result = replace(pattern: "(?m)^\\s*#\\d+\\s+.*$", in: result, with: "")
        result = replace(pattern: "(?m)^\\s*at\\s+\\S+\\s+\\(.*\\)\\s*$", in: result, with: "")
        result = replace(pattern: "0x[0-9a-fA-F]+", in: result, with: "<address>")
        result = replace(pattern: "(/Users/|/private/|/var/|/tmp/|~/)[^\\s\"']*", in: result, with: "<path>")
        result = replace(pattern: "\\b[A-Za-z0-9+/=]{24,}\\b", in: result, with: "<redacted>")
        result = replace(pattern: "\\b[0-9a-fA-F]{32,}\\b", in: result, with: "<redacted>")
        let lines = result.split(separator: "\n", omittingEmptySubsequences: false)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        return lines.joined(separator: "\n")
    }

    public static func redactDiagnosticValue(key: String, value: String) -> String {
        let lowered = key.lowercased()
        let sensitiveKeys = ["secret", "password", "passwd", "credential", "privatekey", "bearer", "auth", "apikey"]
        if sensitiveKeys.contains(where: { lowered.contains($0) }) || lowered == "token" || lowered.hasSuffix("token") {
            return "<redacted>"
        }
        return redactSecrets(value)
    }

    private static func replace(pattern: String, in text: String, with replacement: String) -> String {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else { return text }
        let range = NSRange(text.startIndex..., in: text)
        return regex.stringByReplacingMatches(in: text, options: [], range: range, withTemplate: replacement)
    }
}

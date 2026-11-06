import Foundation

/// Classifies provider authentication/authorization failures so the
/// UI can explain the actual cause instead of collapsing everything
/// into a generic "Authentication error" that prompts a useless
/// re-authentication loop.
///
/// Ported verbatim in semantics from Legacy's
/// `GoogleAuthErrorClassification` (same kinds, same matching order,
/// same diagnostic fields). One deliberate change: Legacy's
/// `classify(_:)` convenience read the granted scopes straight out
/// of its Keychain service; this port has no such global, so the
/// caller passes the stored scopes in — the service reads them from
/// its injected secret store. The testable entry point
/// `classify(_:storedScopes:)` is unchanged.
///
/// The classification preserves the original diagnostic fields
/// (HTTP status, RPC status, reason, service, method) and
/// distinguishes, at minimum: insufficient OAuth scopes,
/// invalid/expired credentials, invalid API keys, quota/rate limits,
/// a missing OAuth client secret, and non-auth provider errors.
public struct GoogleAuthErrorClassification: Sendable, Equatable {
    public enum Kind: Sendable, Equatable {
        /// 403 with ACCESS_TOKEN_SCOPE_INSUFFICIENT (or equivalent
        /// wording). Carries the scopes recorded for the current
        /// session, if any, so the caller can tell "token was minted
        /// before the required scope existed" (fixable by re-auth)
        /// from "scopes present but endpoint rejected it" (a real
        /// restriction: re-auth would loop forever).
        case scopeInsufficient(storedScopes: String?)
        case invalidOrExpiredCredential
        case apiKeyInvalid
        case quotaOrRateLimit
        /// Google's token endpoint refused the exchange because the
        /// OAuth client's secret was not sent (400 invalid_request:
        /// "client_secret is missing."). The browser authorization
        /// step succeeds; the failure happens at the token exchange.
        /// Fixable by configuring the client's secret.
        case missingClientSecret
        case notAuthError
    }

    public let kind: Kind
    /// HTTP status parsed from the error text, when present (e.g. 401, 403, 429).
    public let httpStatus: Int?
    /// Google RPC reason parsed from the error text (e.g. ACCESS_TOKEN_SCOPE_INSUFFICIENT).
    public let reason: String?
    /// Service parsed from the error text (e.g. generativelanguage.googleapis.com).
    public let service: String?
    /// Method parsed from the error text (e.g. ...GenerativeService.StreamGenerateContent).
    public let method: String?

    /// Testable entry point: `storedScopes` is the scope string
    /// recorded for the current session (nil when unknown).
    public static func classify(_ errorText: String, storedScopes: String?) -> GoogleAuthErrorClassification {
        let text = errorText
        let lower = text.lowercased()

        let httpStatus = firstHTTPStatus(in: text)
        // Prefer the most specific known RPC reason; fall back to the first
        // auth-related all-caps token in the text.
        let knownReasons = [
            "ACCESS_TOKEN_SCOPE_INSUFFICIENT",
            "PERMISSION_DENIED",
            "UNAUTHENTICATED",
            "RESOURCE_EXHAUSTED",
            "API_KEY_INVALID",
        ]
        let reason: String? = knownReasons.first(where: { text.contains($0) })
            ?? firstMatch(in: text, pattern: "[A-Z][A-Z0-9_]{5,}").flatMap { candidate in
                let relevant = candidate.contains("SCOPE") || candidate.contains("PERMISSION")
                    || candidate.contains("AUTH") || candidate.contains("QUOTA") || candidate.contains("RATE")
                return relevant ? candidate : nil
            }
        // Prefer the actual API service over incidental matches such as the
        // "type.googleapis.com/..." prefix in RPC detail payloads.
        let knownServices = [
            "generativelanguage.googleapis.com",
            "aiplatform.googleapis.com",
        ]
        let service: String? = knownServices.first(where: { text.contains($0) })
            ?? firstMatch(in: text, pattern: "[a-z0-9-]+\\.googleapis\\.com")
        let method = firstMatch(in: text, pattern: "[A-Za-z0-9_.]+\\.StreamGenerateContent|[A-Za-z0-9_.]+\\.GenerateContent")

        let mentionsScopeProblem =
            text.contains("ACCESS_TOKEN_SCOPE_INSUFFICIENT") ||
            (text.contains("403") && lower.contains("insufficient authentication scopes")) ||
            (text.contains("PERMISSION_DENIED") && lower.contains("scope"))

        if mentionsScopeProblem {
            return GoogleAuthErrorClassification(
                kind: .scopeInsufficient(storedScopes: storedScopes),
                httpStatus: httpStatus, reason: reason, service: service, method: method)
        }

        // The token endpoint explicitly reports a missing client secret.
        // This is distinct from invalid/expired credentials: the user
        // authorized successfully, but the code exchange needs the OAuth
        // client's secret (Google: 400 invalid_request "client_secret is
        // missing."). Check before the generic credential branch so the
        // remediation ("configure the client secret") is specific.
        let mentionsMissingSecret =
            lower.contains("client_secret is missing") ||
            lower.contains("client secret is missing") ||
            lower.contains("client_secret\" is missing")
        if mentionsMissingSecret {
            return GoogleAuthErrorClassification(
                kind: .missingClientSecret,
                httpStatus: httpStatus, reason: reason, service: service, method: method)
        }

        let isQuota = lower.contains("rate limit") || lower.contains("rate_limit") ||
            lower.contains("quota") || lower.contains("429") ||
            lower.contains("resource_exhausted")
        if isQuota {
            return GoogleAuthErrorClassification(
                kind: .quotaOrRateLimit,
                httpStatus: httpStatus, reason: reason, service: service, method: method)
        }

        let mentionsKeyProblem =
            text.contains("API_KEY_INVALID") || lower.contains("invalid api key") ||
            lower.contains("api key not valid")
        if mentionsKeyProblem {
            return GoogleAuthErrorClassification(
                kind: .apiKeyInvalid,
                httpStatus: httpStatus, reason: reason, service: service, method: method)
        }

        let mentionsCredentialProblem =
            text.contains("401") || lower.contains("unauthorized") ||
            lower.contains("invalid credentials") || lower.contains("invalid_grant") ||
            text.contains("UNAUTHENTICATED")
        if mentionsCredentialProblem {
            return GoogleAuthErrorClassification(
                kind: .invalidOrExpiredCredential,
                httpStatus: httpStatus, reason: reason, service: service, method: method)
        }

        return GoogleAuthErrorClassification(
            kind: .notAuthError,
            httpStatus: httpStatus, reason: reason, service: service, method: method)
    }

    /// One-line diagnostic summary preserving the original failure details.
    public var diagnosticSummary: String {
        var parts: [String] = []
        if let httpStatus { parts.append("HTTP \(httpStatus)") }
        if let reason { parts.append(reason) }
        if let service { parts.append(service) }
        if let method { parts.append(method) }
        return parts.isEmpty ? "no provider details captured" : parts.joined(separator: " | ")
    }

    private static func firstHTTPStatus(in text: String) -> Int? {
        // Matches "Error 403", "status 403", "HTTP 403", "code 403".
        guard let regex = try? NSRegularExpression(pattern: "(?:Error|error|status|HTTP|code)\\s*[:=]?\\s*(401|403|404|429|500|502|503)") else { return nil }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        guard let match = regex.firstMatch(in: text, range: range),
              let statusRange = Range(match.range(at: 1), in: text) else { return nil }
        return Int(text[statusRange])
    }

    private static func firstMatch(in text: String, pattern: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        guard let match = regex.firstMatch(in: text, range: range),
              let matchRange = Range(match.range(at: 0), in: text) else { return nil }
        return String(text[matchRange])
    }
}

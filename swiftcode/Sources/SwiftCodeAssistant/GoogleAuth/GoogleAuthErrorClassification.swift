import Foundation

public struct GoogleAuthErrorClassification: Sendable, Equatable {
    public enum Kind: Sendable, Equatable {
        case scopeInsufficient(storedScopes: String?)
        case invalidOrExpiredCredential
        case apiKeyInvalid
        case quotaOrRateLimit
        case missingClientSecret
        case notAuthError
    }

    public let kind: Kind
    public let httpStatus: Int?
    public let reason: String?
    public let service: String?
    public let method: String?

    public static func classify(_ errorText: String, storedScopes: String?) -> GoogleAuthErrorClassification {
        let text = errorText
        let lower = text.lowercased()

        let httpStatus = firstHTTPStatus(in: text)
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

    public var diagnosticSummary: String {
        var parts: [String] = []
        if let httpStatus { parts.append("HTTP \(httpStatus)") }
        if let reason { parts.append(reason) }
        if let service { parts.append(service) }
        if let method { parts.append(method) }
        return parts.isEmpty ? "no provider details captured" : parts.joined(separator: " | ")
    }

    private static func firstHTTPStatus(in text: String) -> Int? {
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

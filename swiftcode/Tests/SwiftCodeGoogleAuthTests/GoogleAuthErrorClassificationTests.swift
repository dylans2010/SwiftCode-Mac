import Foundation
import Testing
@testable import YcodeAssistant

struct GoogleAuthErrorClassificationTests {

    @Test("ACCESS_TOKEN_SCOPE_INSUFFICIENT classifies as scopeInsufficient and keeps the stored scopes")
    func scopeInsufficient() {
        let classification = GoogleAuthErrorClassification.classify(
            "Request had insufficient authentication scopes. 403 ACCESS_TOKEN_SCOPE_INSUFFICIENT on generativelanguage.googleapis.com",
            storedScopes: "openid https://www.googleapis.com/auth/userinfo.email")
        guard case .scopeInsufficient(let stored) = classification.kind else {
            Issue.record("Expected .scopeInsufficient, got \(classification.kind)")
            return
        }
        #expect(stored == "openid https://www.googleapis.com/auth/userinfo.email")
        #expect(classification.httpStatus == 403)
        #expect(classification.reason == "ACCESS_TOKEN_SCOPE_INSUFFICIENT")
        #expect(classification.service == "generativelanguage.googleapis.com")
    }

    @Test("A 403 PERMISSION_DENIED mentioning scope classifies as scopeInsufficient")
    func permissionDeniedScope() {
        let classification = GoogleAuthErrorClassification.classify(
            "PERMISSION_DENIED: the request lacks the required scope", storedScopes: nil)
        guard case .scopeInsufficient = classification.kind else {
            Issue.record("Expected .scopeInsufficient, got \(classification.kind)")
            return
        }
    }

    @Test("client_secret is missing classifies as missingClientSecret, before the generic credential branch")
    func missingClientSecret() {
        let classification = GoogleAuthErrorClassification.classify(
            "400 invalid_request: client_secret is missing.", storedScopes: nil)
        #expect(classification.kind == .missingClientSecret)
        #expect(classification.httpStatus == 400)
    }

    @Test("Quota and rate-limit signals classify as quotaOrRateLimit")
    func quotaOrRateLimit() {
        #expect(GoogleAuthErrorClassification.classify(
            "429 RESOURCE_EXHAUSTED: quota exceeded", storedScopes: nil).kind == .quotaOrRateLimit)
        #expect(GoogleAuthErrorClassification.classify(
            "Rate limit exceeded for this project", storedScopes: nil).kind == .quotaOrRateLimit)
    }

    @Test("API_KEY_INVALID classifies as apiKeyInvalid")
    func apiKeyInvalid() {
        let classification = GoogleAuthErrorClassification.classify(
            "API_KEY_INVALID: API key not valid. Please pass a valid API key.", storedScopes: nil)
        #expect(classification.kind == .apiKeyInvalid)
        #expect(classification.reason == "API_KEY_INVALID")
    }

    @Test("401, invalid_grant and UNAUTHENTICATED classify as invalidOrExpiredCredential")
    func invalidOrExpiredCredential() {
        #expect(GoogleAuthErrorClassification.classify(
            "401 Unauthorized", storedScopes: nil).kind == .invalidOrExpiredCredential)
        #expect(GoogleAuthErrorClassification.classify(
            "400 invalid_grant: Token has been expired or revoked.", storedScopes: nil).kind == .invalidOrExpiredCredential)
        #expect(GoogleAuthErrorClassification.classify(
            "UNAUTHENTICATED: Request is missing required authentication credential.",
            storedScopes: nil).kind == .invalidOrExpiredCredential)
    }

    @Test("An unrelated provider error classifies as notAuthError")
    func notAuthError() {
        let classification = GoogleAuthErrorClassification.classify(
            "The model is overloaded. Please try again later.", storedScopes: nil)
        #expect(classification.kind == .notAuthError)
        #expect(classification.diagnosticSummary == "no provider details captured")
    }

    @Test("The diagnostic summary preserves status, reason, service and method")
    func diagnosticSummary() {
        let classification = GoogleAuthErrorClassification.classify(
            "Error 403 ACCESS_TOKEN_SCOPE_INSUFFICIENT on generativelanguage.googleapis.com "
                + "in v1.GenerateService.StreamGenerateContent",
            storedScopes: nil)
        #expect(classification.diagnosticSummary.contains("HTTP 403"))
        #expect(classification.diagnosticSummary.contains("ACCESS_TOKEN_SCOPE_INSUFFICIENT"))
        #expect(classification.diagnosticSummary.contains("generativelanguage.googleapis.com"))
    }

    @Test("The missing-secret error maps to the actionable remediation, not Google's terse text")
    func actionableSignInError() {
        let message = GoogleAuthError.actionableSignInError(
            for: GoogleAuthError.http(status: 400, message: "client_secret is missing."))
        #expect(message.contains("Settings → Accounts → Google Account"))
        #expect(message.contains("Google Cloud Console"))
        #expect(message.contains("Keychain"))
    }

    @Test("Other sign-in failures pass through unchanged")
    func actionableSignInErrorPassthrough() {
        let message = GoogleAuthError.actionableSignInError(
            for: GoogleAuthError.http(status: 400, message: "invalid_grant: Token has been expired or revoked."))
        #expect(message == "invalid_grant: Token has been expired or revoked.")
    }

    @Test("A network failure maps to the connection message")
    func userFacingNetworkMessage() {
        #expect(GoogleAuthError.network("The Internet connection appears to be offline.").userFacingMessage
            == "Unable to connect to Google. Please check your network connection.")
    }
}

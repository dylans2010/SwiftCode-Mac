import Foundation
import Testing
@testable import SwiftCodeGoogleAuth

// The token-endpoint client: request building, tolerant token
// parsing, error mapping, userinfo, and tokeninfo. No live network:
// every test runs through StubURLProtocol.

struct GoogleTokenClientTests {

    @Test("The code exchange posts the PKCE form body and decodes the tokens")
    func exchangeCode() async throws {
        let client = stubTokenClient { request in
            if request.url?.host == "oauth2.googleapis.com" {
                return ok(stubTokensJSON)
            }
            return (404, [:], json("{}"))
        }
        let tokens = try await client.exchangeCode(
            code: "auth-code-123", verifier: "test-verifier",
            redirectURI: "http://127.0.0.1:8085",
            clientID: GoogleOAuthConfiguration.defaultClientID,
            clientSecret: "fixture-secret")
        #expect(tokens.accessToken == "stub-access-token")
        #expect(tokens.expiresIn == 3600)
        #expect(tokens.refreshToken == "stub-refresh-token")
        #expect(tokens.tokenType == "Bearer")

        let request = StubURLProtocol.requests.first
        #expect(request?.httpMethod == "POST")
        #expect(request?.url?.absoluteString == "https://oauth2.googleapis.com/token")
        #expect(request?.value(forHTTPHeaderField: "Content-Type") == "application/x-www-form-urlencoded")
        let body = formBodyPairs(of: request!)
        #expect(body["client_id"] == GoogleOAuthConfiguration.defaultClientID)
        #expect(body["code"] == "auth-code-123")
        #expect(body["code_verifier"] == "test-verifier")
        #expect(body["grant_type"] == "authorization_code")
        #expect(body["redirect_uri"] == "http://127.0.0.1:8085")
        #expect(body["client_secret"] == "fixture-secret")
    }

    @Test("The code exchange omits client_secret when none is configured")
    func exchangeCodeWithoutSecret() async throws {
        let client = stubTokenClient { _ in ok(stubTokensJSON) }
        _ = try await client.exchangeCode(
            code: "auth-code-123", verifier: "test-verifier",
            redirectURI: "http://127.0.0.1:8085",
            clientID: GoogleOAuthConfiguration.defaultClientID,
            clientSecret: nil)
        let body = formBodyPairs(of: StubURLProtocol.requests.first!)
        #expect(body["client_secret"] == nil)
    }

    @Test("A missing client secret surfaces as .missingClientSecret, not a generic HTTP error")
    func exchangeMissingClientSecret() async {
        let client = stubTokenClient { _ in
            tokenError(400, error: "invalid_request", description: "client_secret is missing.")
        }
        await #expect(throws: GoogleAuthError.missingClientSecret) {
            try await client.exchangeCode(
                code: "auth-code-123", verifier: "test-verifier",
                redirectURI: "http://127.0.0.1:8085",
                clientID: GoogleOAuthConfiguration.defaultClientID,
                clientSecret: nil)
        }
    }

    @Test("Other token-endpoint failures surface as .http with the server's message")
    func exchangeHTTPError() async {
        let client = stubTokenClient { _ in
            tokenError(400, error: "invalid_grant", description: "Bad Request")
        }
        await #expect(throws: GoogleAuthError.http(status: 400, message: "Bad Request")) {
            try await client.exchangeCode(
                code: "stale-code", verifier: "test-verifier",
                redirectURI: "http://127.0.0.1:8085",
                clientID: GoogleOAuthConfiguration.defaultClientID,
                clientSecret: "fixture-secret")
        }
    }

    @Test("The refresh grant posts grant_type=refresh_token and keeps the old refresh token when Google sends none")
    func refreshTokenKeepsOldRefreshToken() async throws {
        let client = stubTokenClient { request in
            if request.url?.host == "oauth2.googleapis.com" {
                return ok(stubTokensStringExpiryJSON)
            }
            return (404, [:], json("{}"))
        }
        let tokens = try await client.refreshToken(
            "old-refresh-token",
            clientID: GoogleOAuthConfiguration.defaultClientID,
            clientSecret: "fixture-secret")
        #expect(tokens.accessToken == "stub-refreshed-token")
        #expect(tokens.expiresIn == 3600)
        #expect(tokens.refreshToken == "old-refresh-token")
        let body = formBodyPairs(of: StubURLProtocol.requests.first!)
        #expect(body["grant_type"] == "refresh_token")
        #expect(body["refresh_token"] == "old-refresh-token")
    }

    @Test("Token parsing tolerates expires_in as a double and as a string")
    func tokenExpiryTolerance() async throws {
        let doubleClient = stubTokenClient { _ in ok(stubTokensDoubleExpiryJSON) }
        let doubleTokens = try await doubleClient.exchangeCode(
            code: "c", verifier: "v", redirectURI: "http://127.0.0.1:8085",
            clientID: GoogleOAuthConfiguration.defaultClientID, clientSecret: nil)
        #expect(doubleTokens.expiresIn == 3600)

        let stringClient = stubTokenClient { _ in ok(stubTokensStringExpiryJSON) }
        let stringTokens = try await stringClient.exchangeCode(
            code: "c", verifier: "v", redirectURI: "http://127.0.0.1:8085",
            clientID: GoogleOAuthConfiguration.defaultClientID, clientSecret: nil)
        #expect(stringTokens.expiresIn == 3600)
    }

    @Test("A 2xx token response that does not decode throws .decoding")
    func exchangeUndecodableBody() async {
        let client = stubTokenClient { _ in ok("{\"no_access_token_here\":true}") }
        await #expect(throws: GoogleAuthError.decoding("Unable to parse Google OAuth token response.")) {
            try await client.exchangeCode(
                code: "c", verifier: "v", redirectURI: "http://127.0.0.1:8085",
                clientID: GoogleOAuthConfiguration.defaultClientID, clientSecret: nil)
        }
    }

    @Test("fetchUserEmail returns the email on 200 and nil on a rejected token")
    func fetchUserEmail() async {
        let okClient = stubTokenClient { _ in ok(stubUserinfoJSON) }
        #expect(await okClient.fetchUserEmail(accessToken: "stub-access-token") == "dylan@example.com")

        let deniedClient = stubTokenClient { _ in (401, [:], json("{}")) }
        #expect(await deniedClient.fetchUserEmail(accessToken: "dead-token") == nil)
    }

    @Test("fetchUserEmail sends the Bearer token to the userinfo endpoint")
    func fetchUserEmailRequest() async {
        let client = stubTokenClient { _ in ok(stubUserinfoJSON) }
        _ = await client.fetchUserEmail(accessToken: "stub-access-token")
        let request = StubURLProtocol.requests.first
        #expect(request?.url?.absoluteString == "https://www.googleapis.com/oauth2/v2/userinfo")
        #expect(request?.value(forHTTPHeaderField: "Authorization") == "Bearer stub-access-token")
    }

    @Test("tokeninfoStatus returns the status Google answers with")
    func tokeninfoStatus() async {
        let okClient = stubTokenClient { _ in ok("{}") }
        #expect(await okClient.tokeninfoStatus(accessToken: "stub-access-token") == 200)
        let rejectedClient = stubTokenClient { _ in (401, [:], json("{}")) }
        #expect(await rejectedClient.tokeninfoStatus(accessToken: "dead-token") == 401)
    }
}

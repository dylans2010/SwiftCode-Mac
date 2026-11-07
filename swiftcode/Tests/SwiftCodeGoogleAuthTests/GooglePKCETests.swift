import Foundation
import Testing
@testable import SwiftCodeGoogleAuth

struct GooglePKCETests {

    @Test("The RFC 7636 Appendix B vector: verifier dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk challenges to E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM")
    func rfc7636AppendixBVector() {
        let verifier = "dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk"
        #expect(GooglePKCE.generateCodeChallenge(for: verifier) == "E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM")
    }

    @Test("A generated verifier is 86 base64url characters (64 random bytes) and two verifiers differ")
    func generatedVerifierShape() {
        let first = GooglePKCE.generateCodeVerifier()
        let second = GooglePKCE.generateCodeVerifier()
        #expect(first.count == 86)
        #expect(first.allSatisfy { $0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" })
        #expect(first != second)
    }

    @Test("The challenge is base64url(SHA-256(verifier)): the well-known SHA-256(\"abc\") vector")
    func challengeKnownVector() {
        #expect(GooglePKCE.generateCodeChallenge(for: "abc") == "ungWv48Bz-pBQUDeXa4iI7ADYaOWF3qctBD_YfIAFa0")
    }

    @Test("Base64url encoding strips padding and replaces + and /")
    func base64URLEncoding() {
        #expect(GooglePKCE.base64URLEncode(Data([0xfb, 0xff, 0xfe])) == "-__-")
        #expect(GooglePKCE.base64URLEncode(Data("abc".utf8)) == "YWJj")
    }

    @Test("The authorize URL carries the client, redirect, code response, scopes, S256 challenge, state, offline access and consent prompt")
    func authorizationURLParameters() {
        let configuration = GoogleOAuthConfiguration()
        let url = GooglePKCE.authorizationURL(
            configuration: configuration,
            challenge: "test-challenge",
            state: "test-state",
            redirectURI: "http://127.0.0.1:8085"
        )
        #expect(url != nil)
        let components = URLComponents(url: url!, resolvingAgainstBaseURL: false)
        #expect(components?.host == "accounts.google.com")
        #expect(components?.path == "/o/oauth2/v2/auth")
        let items = Dictionary(uniqueKeysWithValues: (components?.queryItems ?? []).map { ($0.name, $0.value ?? "") })
        #expect(items["client_id"] == GoogleOAuthConfiguration.defaultClientID)
        #expect(items["redirect_uri"] == "http://127.0.0.1:8085")
        #expect(items["response_type"] == "code")
        #expect(items["scope"]?.contains("https://www.googleapis.com/auth/generative-language.retriever") == true)
        #expect(items["scope"]?.contains("https://www.googleapis.com/auth/cloud-platform") == true)
        #expect(items["scope"]?.contains("openid") == true)
        #expect(items["code_challenge"] == "test-challenge")
        #expect(items["code_challenge_method"] == "S256")
        #expect(items["state"] == "test-state")
        #expect(items["access_type"] == "offline")
        #expect(items["prompt"] == "consent")
    }

    @Test("The redirect URI for port 65000 uses localhost with /auth/callback; other ports use 127.0.0.1 with no path")
    func redirectURIForPort() {
        #expect(GoogleOAuthConfiguration.redirectURI(forLoopbackPort: 65000) == "http://localhost:65000/auth/callback")
        #expect(GoogleOAuthConfiguration.redirectURI(forLoopbackPort: 8085) == "http://127.0.0.1:8085")
        #expect(GoogleOAuthConfiguration.redirectURI(forLoopbackPort: 8099) == "http://127.0.0.1:8099")
    }

    @Test("Callback parsing returns the code when the state matches")
    func parseCallbackSuccess() throws {
        let url = URL(string: "http://127.0.0.1:8085/?code=auth-code-123&state=test-state&scope=openid")!
        #expect(try GooglePKCE.parseCallback(url, expectedState: "test-state") == "auth-code-123")
    }

    @Test("Callback parsing throws authorizationDenied when Google reports an error")
    func parseCallbackAuthorizationError() {
        let url = URL(string: "http://127.0.0.1:8085/?error=access_denied&state=test-state")!
        #expect(throws: GoogleAuthError.authorizationDenied("access_denied")) {
            try GooglePKCE.parseCallback(url, expectedState: "test-state")
        }
    }

    @Test("Callback parsing throws stateMismatch when the state differs")
    func parseCallbackStateMismatch() {
        let url = URL(string: "http://127.0.0.1:8085/?code=auth-code-123&state=other-state")!
        #expect(throws: GoogleAuthError.stateMismatch) {
            try GooglePKCE.parseCallback(url, expectedState: "test-state")
        }
    }

    @Test("Callback parsing throws missingAuthorizationCode when no code is present")
    func parseCallbackMissingCode() {
        let url = URL(string: "http://127.0.0.1:8085/?state=test-state")!
        #expect(throws: GoogleAuthError.missingAuthorizationCode) {
            try GooglePKCE.parseCallback(url, expectedState: "test-state")
        }
    }

    @Test("The email is extracted from a JWT id token payload; malformed tokens yield nil")
    func extractEmailFromIDToken() {
        let payload = Data("{\"email\":\"dylan@example.com\",\"sub\":\"123\"}".utf8).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
        let token = "eyJhbGciOiJSUzI1NiJ9.\(payload).signature"
        #expect(GooglePKCE.extractEmailFromIDToken(token) == "dylan@example.com")
        #expect(GooglePKCE.extractEmailFromIDToken("not-a-token") == nil)
        #expect(GooglePKCE.extractEmailFromIDToken("a.b") == nil)
        let noEmailPayload = Data("{\"sub\":\"123\"}".utf8).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
        #expect(GooglePKCE.extractEmailFromIDToken("h.\(noEmailPayload).s") == nil)
    }
}

struct GoogleLoopbackTests {

    @Test("The request line parses to the loopback callback URL: localhost for 65000, 127.0.0.1 otherwise")
    func callbackURLFromRequestLine() {
        let url65000 = GoogleLoopbackServer.callbackURL(
            fromRequestLine: "GET /auth/callback?code=abc&state=s HTTP/1.1", port: 65000)
        #expect(url65000?.absoluteString == "http://localhost:65000/auth/callback?code=abc&state=s")
        let url8085 = GoogleLoopbackServer.callbackURL(
            fromRequestLine: "GET /?code=abc&state=s HTTP/1.1", port: 8085)
        #expect(url8085?.absoluteString == "http://127.0.0.1:8085/?code=abc&state=s")
        #expect(GoogleLoopbackServer.callbackURL(fromRequestLine: "GARBAGE", port: 8085) == nil)
    }

    @Test("The success page names the swiftcode callback scheme and the successful sign-in")
    func successPageContent() {
        #expect(GoogleLoopbackServer.successPage.contains("swiftcode://oauth-callback"))
        #expect(GoogleLoopbackServer.successPage.contains("Authentication Successful"))
    }

    @Test("The preferred loopback ports start with 65000, then 8085 through 8099")
    func preferredLoopbackPorts() {
        #expect(GoogleOAuthConfiguration.preferredLoopbackPorts.first == 65000)
        #expect(GoogleOAuthConfiguration.preferredLoopbackPorts.dropFirst().map(Int.init) == Array(8085...8099))
    }
}

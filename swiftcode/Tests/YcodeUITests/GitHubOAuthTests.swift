import Foundation
import Testing
@testable import YcodeUI

@Suite struct GitHubOAuthTests {
    @Test func dotEnvParsingSkipsCommentsAndStripsQuotes() {
        let parsed = DotEnvLoader.parse(contents: """
        # a comment
        GITHUB_CLIENT_ID=abc123
        CLIENT_SECRET="secret value"
        SINGLE='quoted'
        EMPTY=
        SPACED =  padded
        """)
        #expect(parsed["GITHUB_CLIENT_ID"] == "abc123")
        #expect(parsed["CLIENT_SECRET"] == "secret value")
        #expect(parsed["SINGLE"] == "quoted")
        #expect(parsed["EMPTY"] == nil)
        #expect(parsed["SPACED"] == "padded")
        #expect(parsed["# a comment"] == nil)
    }

    @Test func callbackMatchingRequiresSchemeHostAndPath() {
        let config = GitHubOAuthConfig(clientID: "id", clientSecret: "secret", redirectURI: "swiftcode://oauth/callback")
        #expect(GitHubOAuth.isOAuthCallback(URL(string: "swiftcode://oauth/callback?code=x&state=y")!, config: config))
        #expect(!GitHubOAuth.isOAuthCallback(URL(string: "swiftcode://oauth/other?code=x")!, config: config))
        #expect(!GitHubOAuth.isOAuthCallback(URL(string: "https://github.com/login/oauth/authorize")!, config: config))
        #expect(!GitHubOAuth.isOAuthCallback(URL(string: "swiftcode://other/callback")!, config: config))
    }

    @Test func oauthErrorsDescribeThemselves() {
        #expect(GitHubOAuthError.invalidState.errorDescription?.contains("state validation failed") == true)
        #expect(GitHubOAuthError.userCancelled.errorDescription?.contains("cancelled") == true)
        #expect(GitHubOAuthError.tokenExchangeFailed.errorDescription?.contains("exchange") == true)
        #expect(GitHubOAuthError.invalidResponse("denied").errorDescription?.contains("denied") == true)
    }
}

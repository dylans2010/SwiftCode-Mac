import Foundation
import Testing
import YcodeAssistant
@testable import YcodeGoogleAuth

// Antigravity credential parsing and ADC file discovery. The
// parsing tests are pure; the discovery tests use fixture files in
// a temp home directory and a stub token endpoint — never the real
// home directory, keychain, or network.

struct GoogleAntigravityParsingTests {

    @Test("The nested token shape parses: refresh token, cached access token, client id, scopes")
    func nestedTokenShape() {
        let json: [String: Any] = [
            "client_id": "fixture-client.apps.googleusercontent.com",
            "client_secret": "fixture-secret",
            "scopes": ["https://www.googleapis.com/auth/cloud-platform"],
            "token": ["refresh_token": "fixture-refresh", "access_token": "fixture-access"],
        ]
        let creds = GoogleAmbientCredentials.parseAntigravityJSON(json)
        #expect(creds?.clientID == "fixture-client.apps.googleusercontent.com")
        #expect(creds?.clientSecret == "fixture-secret")
        #expect(creds?.refreshToken == "fixture-refresh")
        #expect(creds?.accessToken == "fixture-access")
        #expect(creds?.scopes == ["https://www.googleapis.com/auth/cloud-platform"])
    }

    @Test("The flat shape parses, and a missing client_id falls back to Ycode's own client id")
    func flatShape() {
        let json: [String: Any] = ["refresh_token": "fixture-refresh", "access_token": "fixture-access"]
        let creds = GoogleAmbientCredentials.parseAntigravityJSON(json)
        #expect(creds?.clientID == GoogleOAuthConfiguration.defaultClientID)
        #expect(creds?.refreshToken == "fixture-refresh")
        #expect(creds?.accessToken == "fixture-access")
        #expect(creds?.scopes == [])
    }

    @Test("The go-keyring-base64: wrapper decodes before parsing")
    func goKeyringBase64Wrapper() {
        let inner = "{\"refresh_token\":\"fixture-refresh\",\"client_id\":\"fixture-client\"}"
        let wrapped = "go-keyring-base64:" + Data(inner.utf8).base64EncodedString()
        let creds = GoogleAmbientCredentials.parseAntigravityString(wrapped)
        #expect(creds?.refreshToken == "fixture-refresh")
        #expect(creds?.clientID == "fixture-client")
    }

    @Test("Garbage and token-less JSON parse to nil; scopes are never fabricated")
    func garbageParsesToNil() {
        #expect(GoogleAmbientCredentials.parseAntigravityString("not json at all") == nil)
        #expect(GoogleAmbientCredentials.parseAntigravityJSON(["unrelated": "keys"]) == nil)
        #expect(GoogleAmbientCredentials.parseAntigravityJSON(["token": ["access_token": ""]]) == nil)
        let json: [String: Any] = ["refresh_token": "fixture-refresh"]
        #expect(GoogleAmbientCredentials.parseAntigravityJSON(json)?.scopes == [])
    }

    @Test("Raw keychain data parses as direct JSON")
    func rawDataParsing() {
        let data = Data("{\"refresh_token\":\"fixture-refresh\"}".utf8)
        #expect(GoogleAmbientCredentials.parseAntigravityCredentials(from: data)?.refreshToken == "fixture-refresh")
        #expect(GoogleAmbientCredentials.parseAntigravityCredentials(from: Data("garbage".utf8)) == nil)
    }
}

@MainActor
struct GoogleADCFileTests {

    /// An authorized_user ADC fixture. Placeholder values only.
    private let authorizedUserFixture = """
        {"client_id":"fixture-adc-client.apps.googleusercontent.com",\
        "client_secret":"fixture-adc-secret","refresh_token":"fixture-adc-refresh",\
        "type":"authorized_user"}
        """

    @Test("ADC file parsing: authorized_user, bare access_token, and garbage")
    func parseADCFile() {
        let authorized = GoogleAmbientCredentials.parseADCFile(Data(authorizedUserFixture.utf8))
        guard case .authorizedUser(let clientID, let refreshToken, let secret) = authorized else {
            Issue.record("Expected .authorizedUser, got \(authorized)")
            return
        }
        #expect(clientID == "fixture-adc-client.apps.googleusercontent.com")
        #expect(refreshToken == "fixture-adc-refresh")
        #expect(secret == "fixture-adc-secret")

        #expect(GoogleAmbientCredentials.parseADCFile(Data("{\"access_token\":\"fixture-token\"}".utf8))
            == .accessToken("fixture-token"))
        #expect(GoogleAmbientCredentials.parseADCFile(Data("garbage".utf8)) == .none)
        #expect(GoogleAmbientCredentials.parseADCFile(Data("{\"type\":\"service_account\"}".utf8)) == .none)
    }

    @Test("ADC paths try GOOGLE_APPLICATION_CREDENTIALS first, then the standard location")
    func adcFilePaths() {
        let home = URL(fileURLWithPath: "/Users/user")
        let paths = GoogleAmbientCredentials.adcFilePaths(
            environment: ["GOOGLE_APPLICATION_CREDENTIALS": "/tmp/fixture-adc.json"], homeDirectory: home)
        #expect(paths.count == 2)
        #expect(paths[0].path == "/tmp/fixture-adc.json")
        #expect(paths[1].path == "/Users/user/.config/gcloud/application_default_credentials.json")
        let defaultOnly = GoogleAmbientCredentials.adcFilePaths(environment: [:], homeDirectory: home)
        #expect(defaultOnly.count == 1)
    }

    @Test("The gcloud config account line parses; other lines are ignored")
    func gcloudConfigAccount() {
        let content = "[core]\nproject = fixture-project\naccount = dylan@example.com\n"
        #expect(GoogleAmbientCredentials.gcloudConfigAccount(from: content) == "dylan@example.com")
        #expect(GoogleAmbientCredentials.gcloudConfigAccount(from: "[core]\nproject = x\n") == nil)
    }

    @Test("The agy CLI candidates list AGY_PATH first, then the standard locations")
    func agyCLICandidates() {
        let home = URL(fileURLWithPath: "/Users/user")
        let candidates = GoogleAmbientCredentials.agyCLICandidates(
            environment: ["AGY_PATH": "/opt/custom/agy"], homeDirectory: home)
        #expect(candidates.first == "/opt/custom/agy")
        #expect(candidates.contains("/Users/user/.local/bin/agy"))
        #expect(candidates.contains("/usr/local/bin/agy"))
    }

    @Test("An authorized_user ADC file refreshes into an access token under the file's own client id")
    func adcFileRefresh() async throws {
        let home = try makeTempHome()
        defer { try? FileManager.default.removeItem(at: home) }
        try writeFixture(authorizedUserFixture, relativePath: ".config/gcloud/application_default_credentials.json", home: home)
        let (defaults, _) = makeTestDefaults()
        let service = makeTestService(handler: { _ in ok(stubTokensStringExpiryJSON) }, home: home, defaults: defaults)

        let token = await service.checkAmbientADC()
        #expect(token == "stub-refreshed-token")
        let body = formBodyPairs(of: StubURLProtocol.requests.first!)
        #expect(body["client_id"] == "fixture-adc-client.apps.googleusercontent.com")
        #expect(body["refresh_token"] == "fixture-adc-refresh")
        #expect(body["client_secret"] == "fixture-adc-secret")
        #expect(body["grant_type"] == "refresh_token")
    }

    @Test("A bare access_token ADC file returns the token with no token-endpoint call")
    func adcFileAccessToken() async throws {
        let home = try makeTempHome()
        defer { try? FileManager.default.removeItem(at: home) }
        try writeFixture("{\"access_token\":\"fixture-adc-token\"}",
                         relativePath: ".config/gcloud/application_default_credentials.json", home: home)
        let (defaults, _) = makeTestDefaults()
        let service = makeTestService(handler: { _ in ok(stubTokensJSON) }, home: home, defaults: defaults)

        #expect(await service.checkAmbientADC() == "fixture-adc-token")
        #expect(StubURLProtocol.requests.isEmpty)
    }

    @Test("GOOGLE_APPLICATION_CREDENTIALS points at the ADC file to use")
    func adcFileFromEnvironment() async throws {
        let home = try makeTempHome()
        defer { try? FileManager.default.removeItem(at: home) }
        let custom = home.appendingPathComponent("custom-adc.json")
        try authorizedUserFixture.write(to: custom, atomically: true, encoding: .utf8)
        let (defaults, _) = makeTestDefaults()
        let service = makeTestService(
            handler: { _ in ok(stubTokensStringExpiryJSON) }, home: home, defaults: defaults,
            environment: ["GOOGLE_APPLICATION_CREDENTIALS": custom.path])

        #expect(await service.checkAmbientADC() == "stub-refreshed-token")
    }

    @Test("An explicit sign-out blocks ambient ADC: no file is read, no token returns")
    func explicitSignOutBlocksADC() async throws {
        let home = try makeTempHome()
        defer { try? FileManager.default.removeItem(at: home) }
        try writeFixture("{\"access_token\":\"fixture-adc-token\"}",
                         relativePath: ".config/gcloud/application_default_credentials.json", home: home)
        let (defaults, _) = makeTestDefaults()
        defaults.set(true, forKey: GoogleDefaultsKey.explicitlySignedOut)
        let service = makeTestService(handler: { _ in ok(stubTokensJSON) }, home: home, defaults: defaults)

        #expect(await service.checkAmbientADC() == nil)
        #expect(StubURLProtocol.requests.isEmpty)
    }

    @Test("ambientADCEmail reads client_email from the ADC file, else the gcloud config account")
    func ambientADCEmail() throws {
        let home = try makeTempHome()
        defer { try? FileManager.default.removeItem(at: home) }
        let (defaults, _) = makeTestDefaults()
        let service = makeTestService(handler: { _ in ok("{}") }, home: home, defaults: defaults)

        #expect(service.ambientADCEmail() == nil)
        try writeFixture("{\"client_email\":\"service@example.com\"}",
                         relativePath: ".config/gcloud/application_default_credentials.json", home: home)
        #expect(service.ambientADCEmail() == "service@example.com")

        try FileManager.default.removeItem(at: home.appendingPathComponent(".config/gcloud/application_default_credentials.json"))
        try writeFixture("[core]\naccount = dylan@example.com\n",
                         relativePath: ".config/gcloud/configurations/config_default", home: home)
        #expect(service.ambientADCEmail() == "dylan@example.com")
    }
}

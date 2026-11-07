import Foundation
import Testing
import SwiftCodeAssistant
@testable import SwiftCodeGoogleAuth

final class StubURLProtocol: URLProtocol {
    nonisolated(unsafe) static var handler: ((URLRequest) -> (status: Int, headers: [String: String], body: Data))?
    nonisolated(unsafe) static var requests: [URLRequest] = []

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        Self.requests.append(request)
        guard let handler = Self.handler else {
            client?.urlProtocol(self, didFailWithError: URLError(.unknown))
            return
        }
        let (status, headers, body) = handler(request)
        let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: "HTTP/1.1", headerFields: headers)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: body)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

func stubSession() -> URLSession {
    let config = URLSessionConfiguration.ephemeral
    config.protocolClasses = [StubURLProtocol.self]
    return URLSession(configuration: config)
}

func stubTokenClient(
    handler: @escaping @Sendable (URLRequest) -> (status: Int, headers: [String: String], body: Data)
) -> GoogleTokenClient {
    StubURLProtocol.requests = []
    StubURLProtocol.handler = handler
    return GoogleTokenClient(session: stubSession())
}

func json(_ string: String) -> Data { Data(string.utf8) }

func ok(_ body: String, headers: [String: String] = [:]) -> (status: Int, headers: [String: String], body: Data) {
    (200, headers, json(body))
}

func tokenError(_ status: Int, error: String, description: String) -> (status: Int, headers: [String: String], body: Data) {
    (status, [:], json("{\"error\":\"\(error)\",\"error_description\":\"\(description)\"}"))
}

func formBodyPairs(of request: URLRequest) -> [String: String] {
    guard let data = request.httpBody, let string = String(data: data, encoding: .utf8) else { return [:] }
    var pairs: [String: String] = [:]
    for part in string.components(separatedBy: "&") {
        let kv = part.components(separatedBy: "=")
        if kv.count == 2 {
            pairs[kv[0]] = kv[1].removingPercentEncoding ?? kv[1]
        }
    }
    return pairs
}

let stubTokensJSON = """
    {"access_token":"stub-access-token","expires_in":3600,"refresh_token":"stub-refresh-token",\
    "scope":"https://www.googleapis.com/auth/cloud-platform openid","token_type":"Bearer",\
    "id_token":"stub-id-token"}
    """

let stubTokensDoubleExpiryJSON = """
    {"access_token":"stub-access-token","expires_in":3600.0,"refresh_token":"stub-refresh-token",\
    "token_type":"Bearer"}
    """

let stubTokensStringExpiryJSON = """
    {"access_token":"stub-refreshed-token","expires_in":"3600","token_type":"Bearer"}
    """

let stubUserinfoJSON = "{\"email\":\"dylan@example.com\",\"verified_email\":true}"

func makeTempHome() throws -> URL {
    let home = FileManager.default.temporaryDirectory
        .appendingPathComponent("SwiftCodeGoogleAuthTests-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
    return home
}

func makeTestDefaults() -> (UserDefaults, String) {
    let name = "SwiftCodeGoogleAuthTests-\(UUID().uuidString)"
    return (UserDefaults(suiteName: name) ?? .standard, name)
}

@MainActor
func makeTestService(
    store: MemorySecretStore = MemorySecretStore(),
    handler: @escaping @Sendable (URLRequest) -> (status: Int, headers: [String: String], body: Data),
    home: URL,
    defaults: UserDefaults,
    environment: [String: String] = [:],
    restoreSession: Bool = false
) -> GoogleAccountAuthService {
    GoogleAccountAuthService(
        store: store,
        session: stubSession(),
        tokenClient: stubTokenClient(handler: handler),
        environment: environment,
        homeDirectory: home,
        userDefaults: defaults,
        antigravityFetcher: { nil },
        gcloudTokenProvider: { _ in nil },
        restoreSession: restoreSession
    )
}

func writeFixture(_ content: String, relativePath: String, home: URL) throws {
    let url = home.appendingPathComponent(relativePath)
    try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    try content.write(to: url, atomically: true, encoding: .utf8)
}

func storeSession(
    in store: MemorySecretStore,
    accessToken: String = "stub-access-token",
    expiresAt: TimeInterval = Date().addingTimeInterval(3600).timeIntervalSince1970,
    refreshToken: String? = "stub-refresh-token",
    scope: String? = "https://www.googleapis.com/auth/cloud-platform",
    email: String? = "dylan@example.com"
) {
    try? store.write(Data(accessToken.utf8), for: GoogleSecretAccount.accessToken)
    try? store.write(Data(String(expiresAt).utf8), for: GoogleSecretAccount.expiresAt)
    if let refreshToken { try? store.write(Data(refreshToken.utf8), for: GoogleSecretAccount.refreshToken) }
    if let scope { try? store.write(Data(scope.utf8), for: GoogleSecretAccount.scope) }
    if let email { try? store.write(Data(email.utf8), for: GoogleSecretAccount.userEmail) }
}

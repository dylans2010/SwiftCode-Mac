import Foundation
import Testing
@testable import SwiftCodeCloud

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

func stubClient(
    initialSessionSecret: String? = nil,
    handler: @escaping @Sendable (URLRequest) -> (status: Int, headers: [String: String], body: Data)
) -> AppwriteAccountClient {
    StubURLProtocol.requests = []
    StubURLProtocol.handler = handler
    return AppwriteAccountClient(session: stubSession(), initialSessionSecret: initialSessionSecret)
}

func json(_ string: String) -> Data { Data(string.utf8) }

func ok(_ body: String, headers: [String: String] = [:]) -> (status: Int, headers: [String: String], body: Data) {
    (200, headers, json(body))
}

func appwriteError(_ status: Int, code: Int, type: String, message: String) -> (status: Int, headers: [String: String], body: Data) {
    (status, [:], json("{\"message\":\"\(message)\",\"code\":\(code),\"type\":\"\(type)\",\"version\":\"1.7.0\"}"))
}

func queryItems(of request: URLRequest) -> [String: String] {
    guard let url = request.url,
          let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
          let items = components.queryItems else { return [:] }
    return Dictionary(uniqueKeysWithValues: items.map { ($0.name, $0.value ?? "") })
}

func jsonBody(of request: URLRequest) -> [String: Any] {
    guard let data = request.httpBody,
          let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return [:] }
    return object
}

let sessionJSON = """
{"$id":"sess_1","userId":"user_1","expire":"2027-01-15T10:30:00.000+00:00","provider":"email","current":true}
"""

let userJSON = """
{"$id":"user_1","$createdAt":"2026-01-01T00:00:00.000+00:00","$updatedAt":"2026-01-15T10:30:00.000+00:00","name":"Dylan","email":"dylan@example.com","emailVerification":true,"phoneVerification":false,"status":true,"prefs":{"swiftcode_id":"sc_id=ABCDEF0123456789ABCDEF0123456789"}}
"""

let userWithoutSwiftCodeIDJSON = """
{"$id":"user_1","$createdAt":"2026-01-01T00:00:00.000+00:00","$updatedAt":"2026-01-15T10:30:00.000+00:00","name":"Dylan","email":"dylan@example.com","emailVerification":false,"phoneVerification":false,"status":true,"prefs":{}}
"""

let filesJSON = """
{"total":2,"files":[{"$id":"file_a","bucketId":"backups","name":"backup-a.zip","mimeType":"application/zip","sizeOriginal":123},{"$id":"file_b","bucketId":"backups","name":"backup-b.zip","mimeType":"application/zip","sizeOriginal":456}]}
"""

let sessionCookieHeader = ["Set-Cookie": "a_session_6a670d0b0022e5f964b4=stub-secret-123; Path=/; HttpOnly"]

func authHappyPath(_ request: URLRequest) -> (status: Int, headers: [String: String], body: Data) {
    switch request.url?.path {
    case "/v1/account/sessions/email":
        return ok(sessionJSON, headers: sessionCookieHeader)
    case "/v1/account":
        return ok(userJSON)
    default:
        return ok("{}")
    }
}

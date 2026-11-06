import Foundation
import SwiftCodeAssistant
@testable import SwiftCodeMCP

/// The `swiftcode/` folder of this checkout.
let swiftcodeFolder = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()

/// A copy of `Samples/AgentSamples/Greeter` in a temporary folder (tests
/// build and edit the copy, never the sample).
struct TempSample {
    let root: URL
    let url: URL

    init(_ name: String = "Greeter", breaking: Bool = false) throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("swiftcode-mcp-\(UUID().uuidString)")
        url = root.appendingPathComponent(name)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try FileManager.default.copyItem(at: swiftcodeFolder.appendingPathComponent("Samples/AgentSamples/\(name)"), to: url)
        if breaking { try breakIt() }
    }

    /// Introduces a compile error: `salutation` misspelt in the greeting.
    func breakIt() throws {
        let f = path("Sources/Greeter/Greeter.swift")
        let t = try String(contentsOfFile: f, encoding: .utf8)
        try t.replacingOccurrences(of: "\"\\(salutation), \\(name)!\"", with: "\"\\(salutaton), \\(name)!\"").write(toFile: f, atomically: true, encoding: .utf8)
    }

    func path(_ rel: String) -> String { url.appendingPathComponent(rel).path }
    func read(_ rel: String) -> String { (try? String(contentsOfFile: path(rel), encoding: .utf8)) ?? "" }
    func remove() { try? FileManager.default.removeItem(at: root) }
}

/// `_meta` of a modern (2026-07-28) request.
let modernMeta: AnyJSON = [MCPServer.protocolVersionKey: .string(MCPServer.modernVersion), MCPServer.clientCapabilitiesKey: [:],
                           MCPServer.clientInfoKey: ["name": "tests", "version": "1"]]

extension MCPServer {
    /// Calls a tool as a legacy client would; the `CallToolResult`.
    func callTool(_ name: String, _ arguments: [String: AnyJSON] = [:], progress: MCPProgress = .none) async throws -> AnyJSON {
        try await handle(method: "tools/call", params: ["name": .string(name), "arguments": .object(arguments)], connection: Connection(), progress: progress)
    }
}

extension AnyJSON {
    /// The text of every text block of a tool result.
    var resultText: String { (self["content"]?.array ?? []).compactMap { $0["text"]?.string }.joined(separator: "\n") }
    /// The first text block of a tool result. `MCPToolResult.structured(_:summary:)`
    /// emits two blocks (the summary, then the JSON mirror), so an exact
    /// comparison against the human-readable message must use this, not
    /// `resultText` (which joins both blocks). For single-block `.text` /
    /// `.error` results the two are identical.
    var firstText: String { (self["content"]?.array ?? []).compactMap { $0["text"]?.string }.first ?? "" }
    var isToolError: Bool { self["isError"]?.bool == true }
    var structured: AnyJSON? { self["structuredContent"] }
}

/// Collects progress notifications.
final class ProgressLog: @unchecked Sendable {
    private let lock = NSLock()
    private var items: [(Double, Double?, String?)] = []
    var progress: MCPProgress { MCPProgress { [self] p, t, m in lock.withLock { items.append((p, t, m)) } } }
    var messages: [String] { lock.withLock { items.compactMap(\.2) } }
    var count: Int { lock.withLock { items.count } }
}

/// Whether a `swift` toolchain can build packages here.
let canBuildPackages: Bool = {
    let p = Process()
    p.executableURL = URL(fileURLWithPath: "/usr/bin/env")
    p.arguments = ["swift", "--version"]
    p.standardOutput = FileHandle.nullDevice
    p.standardError = FileHandle.nullDevice
    do { try p.run() } catch { return false }
    p.waitUntilExit()
    return p.terminationStatus == 0
}()

/// The `swiftcode` executable of this build.
let swiftcodeExecutable: String? = {
    let p = swiftcodeFolder.appendingPathComponent(".build/debug/swiftcode").path
    return FileManager.default.isExecutableFile(atPath: p) ? p : nil
}()

// MARK: - GitHub API stub (Wave 10, slice B)

/// A URLProtocol stub for GitHub API tests (same shape as the
/// `SwiftCodeGitHubTests` stub): the handler answers every request from
/// canned data, and every request the client made is recorded for
/// assertions. No live network.
final class StubGitHubProtocol: URLProtocol {
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

/// Points the MCP host's GitHub client at a stub-backed session and
/// installs `handler` as the stub. Callers reset the seams in
/// `defer` with `resetGitHubStub()`.
@MainActor
func stubGitHub(_ handler: @escaping @Sendable (URLRequest) -> (status: Int, headers: [String: String], body: Data)) {
    StubGitHubProtocol.requests = []
    StubGitHubProtocol.handler = handler
    let config = URLSessionConfiguration.ephemeral
    config.protocolClasses = [StubGitHubProtocol.self]
    SwiftCodeMCPHost.gitHubTestSession = URLSession(configuration: config)
}

/// Installs the stub transport plus a token store for the GitHub
/// tools: `token` nil installs an empty store (no token anywhere,
/// and no real keychain or config file is read). Reset with
/// `resetGitHubStub()` in `defer`.
@MainActor
func installGitHubStub(token: String? = "test-token",
                       handler: @escaping @Sendable (URLRequest) -> (status: Int, headers: [String: String], body: Data)) {
    stubGitHub(handler)
    SwiftCodeMCPHost.gitHubTestSecretStore = MemorySecretStore()
    if let token {
        try? SwiftCodeMCPHost.gitHubTestSecretStore?.write(Data(token.utf8), for: SecretAccount.githubToken)
    }
}

/// Clears the stub transport, the recorded requests, and both GitHub
/// test seams.
@MainActor
func resetGitHubStub() {
    StubGitHubProtocol.handler = nil
    StubGitHubProtocol.requests = []
    SwiftCodeMCPHost.gitHubTestSession = nil
    SwiftCodeMCPHost.gitHubTestSecretStore = nil
}

/// A 200 stub response with a JSON body.
func gitHubStubOK(_ body: String) -> (status: Int, headers: [String: String], body: Data) {
    (200, [:], Data(body.utf8))
}

/// A GitHub error stub response: `{"message": ...}`.
func gitHubStubError(_ status: Int, _ message: String) -> (status: Int, headers: [String: String], body: Data) {
    (status, [:], Data("{\"message\":\"\(message)\",\"documentation_url\":\"https://docs.github.com\"}".utf8))
}

/// The query items of a recorded request, by name.
func requestQueryItems(of request: URLRequest) -> [String: String] {
    guard let url = request.url,
          let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
          let items = components.queryItems else { return [:] }
    return Dictionary(uniqueKeysWithValues: items.map { ($0.name, $0.value ?? "") })
}

/// The decoded JSON body of a recorded request ({} when it has none).
func requestJSONBody(of request: URLRequest) -> [String: Any] {
    guard let data = request.httpBody,
          let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return [:] }
}

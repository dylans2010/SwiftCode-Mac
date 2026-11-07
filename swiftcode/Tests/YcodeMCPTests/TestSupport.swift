import Foundation
import YcodeAssistant
@testable import YcodeMCP

let swiftcodeFolder = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()

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

    func breakIt() throws {
        let f = path("Sources/Greeter/Greeter.swift")
        let t = try String(contentsOfFile: f, encoding: .utf8)
        try t.replacingOccurrences(of: "\"\\(salutation), \\(name)!\"", with: "\"\\(salutaton), \\(name)!\"").write(toFile: f, atomically: true, encoding: .utf8)
    }

    func path(_ rel: String) -> String { url.appendingPathComponent(rel).path }
    func read(_ rel: String) -> String { (try? String(contentsOfFile: path(rel), encoding: .utf8)) ?? "" }
    func remove() { try? FileManager.default.removeItem(at: root) }
}

let modernMeta: AnyJSON = [MCPServer.protocolVersionKey: .string(MCPServer.modernVersion), MCPServer.clientCapabilitiesKey: [:],
                           MCPServer.clientInfoKey: ["name": "tests", "version": "1"]]

extension MCPServer {
    func callTool(_ name: String, _ arguments: [String: AnyJSON] = [:], progress: MCPProgress = .none) async throws -> AnyJSON {
        try await handle(method: "tools/call", params: ["name": .string(name), "arguments": .object(arguments)], connection: Connection(), progress: progress)
    }
}

extension AnyJSON {
    var resultText: String { (self["content"]?.array ?? []).compactMap { $0["text"]?.string }.joined(separator: "\n") }
    var firstText: String { (self["content"]?.array ?? []).compactMap { $0["text"]?.string }.first ?? "" }
    var isToolError: Bool { self["isError"]?.bool == true }
    var structured: AnyJSON? { self["structuredContent"] }
}

final class ProgressLog: @unchecked Sendable {
    private let lock = NSLock()
    private var items: [(Double, Double?, String?)] = []
    var progress: MCPProgress { MCPProgress { [self] p, t, m in lock.withLock { items.append((p, t, m)) } } }
    var messages: [String] { lock.withLock { items.compactMap(\.2) } }
    var count: Int { lock.withLock { items.count } }
}

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

let swiftcodeExecutable: String? = {
    let p = swiftcodeFolder.appendingPathComponent(".build/debug/swiftcode").path
    return FileManager.default.isExecutableFile(atPath: p) ? p : nil
}()

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

@MainActor
func stubGitHub(_ handler: @escaping @Sendable (URLRequest) -> (status: Int, headers: [String: String], body: Data)) {
    StubGitHubProtocol.requests = []
    StubGitHubProtocol.handler = handler
    let config = URLSessionConfiguration.ephemeral
    config.protocolClasses = [StubGitHubProtocol.self]
    SwiftCodeMCPHost.gitHubTestSession = URLSession(configuration: config)
}

@MainActor
func installGitHubStub(token: String? = "test-token",
                       handler: @escaping @Sendable (URLRequest) -> (status: Int, headers: [String: String], body: Data)) {
    stubGitHub(handler)
    SwiftCodeMCPHost.gitHubTestSecretStore = MemorySecretStore()
    if let token {
        try? SwiftCodeMCPHost.gitHubTestSecretStore?.write(Data(token.utf8), for: SecretAccount.githubToken)
    }
}

@MainActor
func resetGitHubStub() {
    StubGitHubProtocol.handler = nil
    StubGitHubProtocol.requests = []
    SwiftCodeMCPHost.gitHubTestSession = nil
    SwiftCodeMCPHost.gitHubTestSecretStore = nil
}

func gitHubStubOK(_ body: String) -> (status: Int, headers: [String: String], body: Data) {
    (200, [:], Data(body.utf8))
}

func gitHubStubError(_ status: Int, _ message: String) -> (status: Int, headers: [String: String], body: Data) {
    (status, [:], Data("{\"message\":\"\(message)\",\"documentation_url\":\"https://docs.github.com\"}".utf8))
}

func requestQueryItems(of request: URLRequest) -> [String: String] {
    guard let url = request.url,
          let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
          let items = components.queryItems else { return [:] }
    return Dictionary(uniqueKeysWithValues: items.map { ($0.name, $0.value ?? "") })
}

func requestJSONBody(of request: URLRequest) -> [String: Any] {
    guard let data = request.httpBody,
          let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return [:] }
}

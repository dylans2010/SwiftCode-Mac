import Foundation
import Testing
@testable import SwiftCodeGitHub

private func syncClient() -> GitHubClient {
    let config = URLSessionConfiguration.ephemeral
    config.protocolClasses = [StubURLProtocol.self]
    return GitHubClient(session: URLSession(configuration: config), tokenProvider: { "stub-token" })
}

private func contentsResponseJSON(path: String, base64Content: String) -> Data {
    let json: [String: Any] = ["content": [
        "name": (path as NSString).lastPathComponent,
        "path": path,
        "sha": "abc123",
        "size": 5,
        "content": base64Content,
        "encoding": "base64"
    ]]
    return try! JSONSerialization.data(withJSONObject: json)
}

private func fixtureDirectory() throws -> URL {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent("GitHubProjectSyncTests-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    try "print(\"hi\")\n".write(to: dir.appendingPathComponent("a.swift"), atomically: true, encoding: .utf8)
    try FileManager.default.createDirectory(at: dir.appendingPathComponent("Sources"), withIntermediateDirectories: true)
    try "struct B {}\n".write(to: dir.appendingPathComponent("Sources/b.swift"), atomically: true, encoding: .utf8)
    try Data([0x89, 0x50, 0x4E, 0x47]).write(to: dir.appendingPathComponent("image.png"))
    return dir
}

@Suite(.serialized)
struct GitHubProjectSyncTests {
    @Test func textFilesSkipsBinaries() throws {
        let dir = try fixtureDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let sync = GitHubProjectSync(client: syncClient())
        let files = sync.textFiles(in: dir)
        #expect(files.sorted() == ["Sources/b.swift", "a.swift"])
    }

    @Test func pushDirectoryCreatesMissingFiles() async throws {
        let dir = try fixtureDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        var putPaths: [String] = []
        var putBodies: [[String: Any]] = []
        StubURLProtocol.requests = []
        StubURLProtocol.handler = { request in
            if request.httpMethod == "PUT" {
                putPaths.append(request.url?.path ?? "")
                if let body = request.httpBody,
                   let json = try? JSONSerialization.jsonObject(with: body) as? [String: Any] {
                    putBodies.append(json)
                }
                return (200, ["Content-Type": "application/json"], contentsResponseJSON(path: "a.swift", base64Content: "cHJpbnQoImhpIikK"))
            }
            return (404, ["Content-Type": "application/json"], Data(#"{"message":"Not Found"}"#.utf8))
        }
        defer { StubURLProtocol.handler = nil }
        let sync = GitHubProjectSync(client: syncClient())
        let pushed = try await sync.pushDirectory(dir, owner: "octo", repo: "hello", commitMessage: "sync")
        #expect(pushed == 2)
        #expect(putPaths.count == 2)
        #expect(putPaths.allSatisfy { $0.contains("/contents/") })
        #expect(putBodies.allSatisfy { $0["message"] as? String == "sync" })
        #expect(putBodies.allSatisfy { ($0["content"] as? String)?.isEmpty == false })
    }

    @Test func pullFileWritesDecodedText() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("GitHubProjectSyncTests-pull-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        StubURLProtocol.handler = { _ in
            (200, ["Content-Type": "application/json"], contentsResponseJSON(path: "README.md", base64Content: "aGVsbG8K"))
        }
        defer { StubURLProtocol.handler = nil }
        let sync = GitHubProjectSync(client: syncClient())
        let written = try await sync.pullFile(owner: "octo", repo: "hello", path: "README.md", into: dir)
        #expect(written.lastPathComponent == "README.md")
        #expect(try String(contentsOf: written, encoding: .utf8) == "hello\n")
    }
}

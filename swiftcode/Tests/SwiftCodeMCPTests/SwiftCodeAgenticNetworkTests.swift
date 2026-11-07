import Foundation
import Testing
import SwiftCodeAssistant
@testable import SwiftCodeMCP

@MainActor
@Suite(.serialized) struct SwiftCodeAgenticNetworkTests {
    static let agenticNetworkIDs = ["fetch_url", "download_file", "upload_file", "http_request",
                                    "web_search", "documentation_search", "api_reference_search", "package_search",
                                    "dependency_audit", "install_dependencies", "update_dependencies",
                                    "remove_dependencies", "create_pull_request", "review_pull_request",
                                    "read_pull_request", "read_issues", "create_issue", "update_issue",
                                    "search_issues"]

    func opened(_ sample: TempSample, policy: MCPWritePolicy = .allow) async throws -> SwiftCodeMCPHost {
        let host = SwiftCodeMCPHost()
        host.server.writePolicy = policy
        let ported = Set(host.agenticNetworkTools.map(\.name))
        host.server.tools = host.server.tools.filter { !ported.contains($0.name) } + host.agenticNetworkTools
        let r = try await host.server.callTool("workspace_open", ["path": .string(sample.url.path)])
        #expect(!r.isToolError, "\(r.resultText)")
        return host
    }

    func writeFixture(_ sample: TempSample, _ rel: String, _ content: String) throws {
        let url = URL(fileURLWithPath: sample.path(rel))
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try content.write(to: url, atomically: true, encoding: .utf8)
    }

    func bareHost() -> SwiftCodeMCPHost {
        let host = SwiftCodeMCPHost()
        let ported = Set(host.agenticNetworkTools.map(\.name))
        host.server.tools = host.server.tools.filter { !ported.contains($0.name) } + host.agenticNetworkTools
        return host
    }

    @Test func toolsAreRegisteredWithLegacySchemas() async throws {
        let host = SwiftCodeMCPHost()
        let tools = host.agenticNetworkTools
        #expect(tools.map(\.name) == Self.agenticNetworkIDs)
        #expect(Set(tools.map(\.name)).count == tools.count, "tool IDs must be unique")
        let expectedDescriptions: [String: String] = [
            "fetch_url": "Fetches the content of a URL.",
            "download_file": "Downloads a file from a URL.",
            "upload_file": "Uploads a file to a URL.",
            "http_request": "Performs an HTTP request.",
            "web_search": "Performs a web search.",
            "documentation_search": "Searches for documentation.",
            "api_reference_search": "Searches for API references.",
            "package_search": "Searches for packages.",
            "dependency_audit": "Audits project dependencies for vulnerabilities.",
            "install_dependencies": "Installs project dependencies.",
            "update_dependencies": "Updates project dependencies.",
            "remove_dependencies": "Removes a package dependency from the project.",
            "create_pull_request": "Creates a pull request.",
            "review_pull_request": "Reviews a pull request.",
            "read_pull_request": "Reads content of a pull request.",
            "read_issues": "Reads issues for a repository.",
            "create_issue": "Creates an issue.",
            "update_issue": "Updates an issue.",
            "search_issues": "Searches for issues.",
        ]
        let expectedRequired: [String: [String]] = [
            "fetch_url": ["url"],
            "download_file": ["url", "destinationPath"],
            "upload_file": ["path", "url"],
            "http_request": ["url", "method"],
            "web_search": ["query"],
            "documentation_search": ["query"],
            "api_reference_search": ["query"],
            "package_search": ["query"],
            "dependency_audit": ["projectPath"],
            "install_dependencies": ["projectPath"],
            "update_dependencies": ["projectPath"],
            "remove_dependencies": ["projectPath", "packageName"],
            "create_pull_request": ["title", "body", "head", "base"],
            "review_pull_request": ["prNumber"],
            "read_pull_request": ["prNumber"],
            "read_issues": ["repository"],
            "create_issue": ["title", "body"],
            "update_issue": ["issueNumber"],
            "search_issues": ["query"],
        ]
        for tool in tools {
            #expect(tool.description == expectedDescriptions[tool.name], "\(tool.name) description: \(tool.description)")
            #expect(tool.inputSchema["properties"]?["workspace"] != nil, "\(tool.name) is missing the workspace parameter")
            let required = tool.inputSchema["required"]?.array?.compactMap(\.string) ?? []
            #expect(required == expectedRequired[tool.name], "\(tool.name) required: \(required)")
        }
        #expect(tools.first { $0.name == "fetch_url" }?.annotations.readOnly == true)
        #expect(tools.first { $0.name == "fetch_url" }?.annotations.openWorld == true)
        for name in ["download_file", "upload_file", "http_request", "install_dependencies",
                     "update_dependencies", "remove_dependencies",
                     "create_pull_request", "create_issue", "update_issue"] {
            let tool = tools.first { $0.name == name }
            #expect(tool?.writes == true, "\(name) must be a gated write/execution tool")
            #expect(tool?.annotations.readOnly == false, "\(name) must not be read-only")
        }
        for name in ["web_search", "documentation_search", "api_reference_search", "package_search",
                     "dependency_audit", "review_pull_request", "read_pull_request",
                     "read_issues", "search_issues"] {
            #expect(tools.first { $0.name == name }?.annotations.readOnly == true, "\(name) is a read-only tool")
        }
        for name in ["create_pull_request", "review_pull_request", "read_pull_request",
                     "create_issue", "update_issue", "search_issues"] {
            #expect(tools.first { $0.name == name }?.inputSchema["properties"]?["repository"] != nil,
                    "\(name) must offer the optional repository parameter")
        }
    }

    @Test func fetchURLRequiresURL() async throws {
        let host = bareHost()
        let r = try await host.server.callTool("fetch_url", [:])
        #expect(r.isToolError)
        #expect(r.firstText.contains("Missing url"))
    }

    @Test func fetchURLRejectsNonHTTPS() async throws {
        let host = bareHost()
        let r = try await host.server.callTool("fetch_url", ["url": .string("http://example.com/index.html")])
        #expect(r.isToolError)
        #expect(r.firstText.contains("Only HTTPS URLs with a host are allowed"))
    }

    @Test func fetchURLRejectsFileScheme() async throws {
        let host = bareHost()
        let r = try await host.server.callTool("fetch_url", ["url": .string("file:///etc/passwd")])
        #expect(r.isToolError)
        #expect(r.firstText.contains("Only HTTPS URLs with a host are allowed"))
    }

    @Test func downloadFileRequiresArguments() async throws {
        let host = bareHost()
        let missingBoth = try await host.server.callTool("download_file", [:])
        #expect(missingBoth.isToolError)
        #expect(missingBoth.firstText.contains("Missing url"))
        let missingDestination = try await host.server.callTool("download_file", ["url": .string("https://example.com/f.bin")])
        #expect(missingDestination.isToolError)
        #expect(missingDestination.firstText.contains("Missing url or destinationPath"))
    }

    @Test func downloadFileRejectsNonHTTPS() async throws {
        let host = bareHost()
        let r = try await host.server.callTool("download_file", [
            "url": .string("http://example.com/f.bin"),
            "destinationPath": .string("f.bin"),
        ])
        #expect(r.isToolError)
        #expect(r.firstText.contains("Only HTTPS URLs with a host are allowed"))
    }

    @Test func downloadFileRefusesPathsOutsideWorkspace() async throws {
        let sample = try TempSample()
        defer { sample.remove() }
        let host = try await opened(sample)
        let absolute = try await host.server.callTool("download_file", [
            "url": .string("https://example.com/f.bin"),
            "destinationPath": .string("/tmp/agentic-network-evil.bin"),
        ])
        #expect(absolute.isToolError)
        #expect(absolute.firstText.contains("must be inside the workspace"))
        let dotdot = try await host.server.callTool("download_file", [
            "url": .string("https://example.com/f.bin"),
            "destinationPath": .string("../outside.bin"),
        ])
        #expect(dotdot.isToolError)
        #expect(dotdot.firstText.contains("must be inside the workspace"))
        #expect(!FileManager.default.fileExists(atPath: "/tmp/agentic-network-evil.bin"))
    }

    @Test func uploadFileRequiresArguments() async throws {
        let host = bareHost()
        let r = try await host.server.callTool("upload_file", [:])
        #expect(r.isToolError)
        #expect(r.firstText.contains("Missing path or url"))
    }

    @Test func uploadFileRejectsNonHTTPS() async throws {
        let host = bareHost()
        let r = try await host.server.callTool("upload_file", [
            "path": .string("Sources/Greeter/Greeter.swift"),
            "url": .string("http://example.com/upload"),
        ])
        #expect(r.isToolError)
        #expect(r.firstText.contains("Only HTTPS URLs with a host are allowed"))
    }

    @Test func uploadFileReportsMissingFile() async throws {
        let sample = try TempSample()
        defer { sample.remove() }
        let host = try await opened(sample)
        let r = try await host.server.callTool("upload_file", [
            "path": .string("Sources/Greeter/NoSuchFile.swift"),
            "url": .string("https://example.com/upload"),
        ])
        #expect(r.isToolError)
        #expect(r.firstText.contains("File not found at 'Sources/Greeter/NoSuchFile.swift'"))
    }

    @Test func uploadFileRefusesPathsOutsideWorkspace() async throws {
        let sample = try TempSample()
        defer { sample.remove() }
        let host = try await opened(sample)
        let r = try await host.server.callTool("upload_file", [
            "path": .string("../secret.txt"),
            "url": .string("https://example.com/upload"),
        ])
        #expect(r.isToolError)
        #expect(r.firstText.contains("must be inside the workspace"))
    }

    @Test func httpRequestRequiresArguments() async throws {
        let host = bareHost()
        let missingBoth = try await host.server.callTool("http_request", [:])
        #expect(missingBoth.isToolError)
        #expect(missingBoth.firstText.contains("Missing url or method"))
        let missingMethod = try await host.server.callTool("http_request", ["url": .string("https://example.com/")])
        #expect(missingMethod.isToolError)
        #expect(missingMethod.firstText.contains("Missing url or method"))
    }

    @Test func httpRequestRejectsUnknownMethod() async throws {
        let host = bareHost()
        let r = try await host.server.callTool("http_request", [
            "url": .string("https://example.com/"),
            "method": .string("FETCH"),
        ])
        #expect(r.isToolError)
        #expect(r.firstText.contains("Unsupported HTTP method 'FETCH'"))
    }

    @Test func httpRequestRejectsNonHTTPS() async throws {
        let host = bareHost()
        let r = try await host.server.callTool("http_request", [
            "url": .string("http://example.com/"),
            "method": .string("GET"),
        ])
        #expect(r.isToolError)
        #expect(r.firstText.contains("Only HTTPS URLs with a host are allowed"))
    }

    @Test func httpRequestRejectsNonStringHeader() async throws {
        let host = bareHost()
        let r = try await host.server.callTool("http_request", [
            "url": .string("https://example.com/"),
            "method": .string("GET"),
            "headers": .object(["X-Count": .int(3)]),
        ])
        #expect(r.isToolError)
        #expect(r.firstText.contains("Header 'X-Count' must be a string."))
    }

    @Test func webSearchFailsHonestly() async throws {
        let host = bareHost()
        let missing = try await host.server.callTool("web_search", [:])
        #expect(missing.isToolError)
        #expect(missing.firstText.contains("Missing query"))
        let r = try await host.server.callTool("web_search", ["query": .string("swift package index")])
        #expect(r.isToolError)
        #expect(r.firstText.contains("web_search needs a web search provider"))
        #expect(r.firstText.contains("no results were invented"))
    }

    @Test func documentationSearchFailsHonestly() async throws {
        let host = bareHost()
        let missing = try await host.server.callTool("documentation_search", [:])
        #expect(missing.isToolError)
        #expect(missing.firstText.contains("Missing query"))
        let r = try await host.server.callTool("documentation_search", ["query": .string("URLSession")])
        #expect(r.isToolError)
        #expect(r.firstText.contains("documentation_search needs a documentation search backend"))
        #expect(r.firstText.contains("no results were invented"))
    }

    @Test func apiReferenceSearchFailsHonestly() async throws {
        let host = bareHost()
        let missing = try await host.server.callTool("api_reference_search", [:])
        #expect(missing.isToolError)
        #expect(missing.firstText.contains("Missing query"))
        let r = try await host.server.callTool("api_reference_search", ["query": .string("URLSession")])
        #expect(r.isToolError)
        #expect(r.firstText.contains("api_reference_search needs a documentation search backend"))
        #expect(r.firstText.contains("no results were invented"))
    }

    @Test func packageSearchFailsHonestly() async throws {
        let host = bareHost()
        let missing = try await host.server.callTool("package_search", [:])
        #expect(missing.isToolError)
        #expect(missing.firstText.contains("Missing query"))
        let r = try await host.server.callTool("package_search", ["query": .string("alamofire")])
        #expect(r.isToolError)
        #expect(r.firstText.contains("package_search needs a package-index search backend"))
        #expect(r.firstText.contains("no results were invented"))
    }

    @Test func dependencyAuditFailsHonestly() async throws {
        let host = bareHost()
        let missing = try await host.server.callTool("dependency_audit", [:])
        #expect(missing.isToolError)
        #expect(missing.firstText.contains("Missing projectPath"))
        let r = try await host.server.callTool("dependency_audit", ["projectPath": .string(".")])
        #expect(r.isToolError)
        #expect(r.firstText.contains("dependency_audit needs a vulnerability/advisory data source"))
        #expect(r.firstText.contains("no clean bill of health was invented"))
    }

    @Test func installDependenciesValidates() async throws {
        let sample = try TempSample()
        defer { sample.remove() }
        let host = try await opened(sample)
        let missing = try await host.server.callTool("install_dependencies", [:])
        #expect(missing.isToolError)
        #expect(missing.firstText.contains("Missing projectPath"))
        let outside = try await host.server.callTool("install_dependencies", ["projectPath": .string("../outside")])
        #expect(outside.isToolError)
        #expect(outside.firstText.contains("must be inside the workspace"))
        try writeFixture(sample, "Empty/README.txt", "no manifest here\n")
        let noManifest = try await host.server.callTool("install_dependencies", ["projectPath": .string("Empty")])
        #expect(noManifest.isToolError)
        #expect(noManifest.firstText.contains("Package.swift not found"))
    }

    @Test func updateDependenciesValidates() async throws {
        let sample = try TempSample()
        defer { sample.remove() }
        let host = try await opened(sample)
        let missing = try await host.server.callTool("update_dependencies", [:])
        #expect(missing.isToolError)
        #expect(missing.firstText.contains("Missing projectPath"))
        let outside = try await host.server.callTool("update_dependencies", ["projectPath": .string("../outside")])
        #expect(outside.isToolError)
        #expect(outside.firstText.contains("must be inside the workspace"))
        try writeFixture(sample, "Empty/README.txt", "no manifest here\n")
        let noManifest = try await host.server.callTool("update_dependencies", ["projectPath": .string("Empty")])
        #expect(noManifest.isToolError)
        #expect(noManifest.firstText.contains("Package.swift not found"))
    }

    @Test func installDependenciesNeedsSwiftToolchain() async throws {
        guard !FileManager.default.fileExists(atPath: "/usr/bin/swift") else { return }
        let sample = try TempSample()
        defer { sample.remove() }
        let host = try await opened(sample)
        let r = try await host.server.callTool("install_dependencies", ["projectPath": .string(".")])
        #expect(r.isToolError)
        #expect(r.firstText.contains("Swift not found at /usr/bin/swift."))
    }

    @Test func updateDependenciesNeedsSwiftToolchain() async throws {
        guard !FileManager.default.fileExists(atPath: "/usr/bin/swift") else { return }
        let sample = try TempSample()
        defer { sample.remove() }
        let host = try await opened(sample)
        let r = try await host.server.callTool("update_dependencies", ["projectPath": .string(".")])
        #expect(r.isToolError)
        #expect(r.firstText.contains("Swift not found at /usr/bin/swift."))
    }

    static let fixtureManifest = """
        // swift-tools-version: 5.9
        import PackageDescription

        let package = Package(
            name: "FixturePkg",
            dependencies: [
                .package(url: "https://github.com/Alamofire/Alamofire.git", from: "5.0.0"),
                .package(url: "https://github.com/apple/swift-argument-parser.git", from: "1.0.0"),
                .package(name: "LocalThing", path: "./LocalThing")
            ],
            targets: [
                .target(
                    name: "FixturePkg",
                    dependencies: [
                        .product(name: "Alamofire", package: "Alamofire"),
                        "ArgumentParser",
                        .product(name: "LocalThing", package: "LocalThing")
                    ]),
                .testTarget(
                    name: "FixturePkgTests",
                    dependencies: ["FixturePkg"])
            ]
        )
        """

    @Test func removeDependenciesValidates() async throws {
        let sample = try TempSample()
        defer { sample.remove() }
        let host = try await opened(sample)
        let missing = try await host.server.callTool("remove_dependencies", [:])
        #expect(missing.isToolError)
        #expect(missing.firstText.contains("Missing projectPath or packageName"))
        let missingName = try await host.server.callTool("remove_dependencies", ["projectPath": .string(".")])
        #expect(missingName.isToolError)
        #expect(missingName.firstText.contains("Missing projectPath or packageName"))
        let badName = try await host.server.callTool("remove_dependencies", [
            "projectPath": .string("."), "packageName": .string("Alamofire Alamofire"),
        ])
        #expect(badName.isToolError)
        #expect(badName.firstText.contains("Invalid packageName"))
    }

    @Test func removeDependenciesReportsUnknownPackage() async throws {
        let sample = try TempSample()
        defer { sample.remove() }
        let host = try await opened(sample)
        try writeFixture(sample, "FixturePkg/Package.swift", Self.fixtureManifest)
        let r = try await host.server.callTool("remove_dependencies", [
            "projectPath": .string("FixturePkg"), "packageName": .string("NoSuchPackage"),
        ])
        #expect(r.isToolError)
        #expect(r.firstText.contains("Package 'NoSuchPackage' not found in Package.swift"))
        #expect(sample.read("FixturePkg/Package.swift") == Self.fixtureManifest)
    }

    @Test func removeDependenciesRemovesURLMatchedPackage() async throws {
        let sample = try TempSample()
        defer { sample.remove() }
        let host = try await opened(sample)
        try writeFixture(sample, "FixturePkg/Package.swift", Self.fixtureManifest)
        let r = try await host.server.callTool("remove_dependencies", [
            "projectPath": .string("FixturePkg"), "packageName": .string("Alamofire"),
        ])
        #expect(!r.isToolError, "\(r.resultText)")
        #expect(r.firstText.contains("Package Alamofire removed from Package.swift at FixturePkg"))
        #expect(r.structured?["packageName"]?.string == "Alamofire")
        let after = sample.read("FixturePkg/Package.swift")
        #expect(!after.contains("Alamofire"))
        #expect(after.contains("swift-argument-parser"))
        #expect(after.contains("LocalThing"))
        #expect(after.contains("\"ArgumentParser\""))
        #expect(!after.contains(".product(name: \"Alamofire\""))
    }

    @Test func removeDependenciesRemovesNameMatchedPackage() async throws {
        let sample = try TempSample()
        defer { sample.remove() }
        let host = try await opened(sample)
        try writeFixture(sample, "FixturePkg/Package.swift", Self.fixtureManifest)
        let r = try await host.server.callTool("remove_dependencies", [
            "projectPath": .string("FixturePkg"), "packageName": .string("LocalThing"),
        ])
        #expect(!r.isToolError, "\(r.resultText)")
        let after = sample.read("FixturePkg/Package.swift")
        #expect(!after.contains("LocalThing"))
        #expect(after.contains("Alamofire"))
        #expect(after.contains("swift-argument-parser"))
        #expect(after.contains("\"ArgumentParser\""))
    }

    @Test func removeDependenciesHandlesLastEntry() async throws {
        var manifest = Self.fixtureManifest
        #expect(SwiftCodeMCPHost.agenticNetworkRemovePackage(named: "Alamofire", from: &manifest))
        #expect(SwiftCodeMCPHost.agenticNetworkRemovePackage(named: "ArgumentParser", from: &manifest) == false,
                "ArgumentParser is a product name, not a package entry")
        #expect(SwiftCodeMCPHost.agenticNetworkRemovePackage(named: "LocalThing", from: &manifest))
        #expect(!manifest.contains("Alamofire"))
        #expect(!manifest.contains("LocalThing"))
        #expect(manifest.contains("swift-argument-parser"))
        #expect(!manifest.contains(",,"), "no dangling double comma: \(manifest)")
    }

    @Test func removePackageHandlesSingleEntryManifest() {
        var manifest = """
            let package = Package(
                name: "Solo",
                dependencies: [
                    .package(url: "https://github.com/a/b.git", from: "1.0.0")
                ],
                targets: [
                    .target(name: "Solo", dependencies: ["b"])
                ]
            )
            """
        #expect(SwiftCodeMCPHost.agenticNetworkRemovePackage(named: "b", from: &manifest))
        #expect(!manifest.contains("https://github.com/a/b.git"))
        #expect(!manifest.contains("\"b\""))
        #expect(!manifest.contains(",,"), "no dangling double comma: \(manifest)")
        #expect(SwiftCodeMCPHost.agenticNetworkRemovePackage(named: "b", from: &manifest) == false)
    }

    static let gitHubIssueJSON = """
        {"number":42,"title":"Fix the crash","body":"Steps to reproduce","state":"open","user":{"login":"octocat"},"labels":[],"created_at":"2024-01-15T10:30:00Z","updated_at":"2024-01-16T10:30:00Z","html_url":"https://github.com/octocat/Hello-World/issues/42"}
        """
    static let gitHubIssueListJSON = """
        [{"number":1,"title":"Found a bug","body":"Steps to reproduce","state":"open","user":{"login":"octocat"},"labels":[{"name":"bug"}],"created_at":"2024-01-15T10:30:00Z","updated_at":"2024-01-16T10:30:00Z","html_url":"https://github.com/octocat/Hello-World/issues/1"},
         {"number":2,"title":"Fix the bug","body":null,"state":"open","user":{"login":"hubot"},"labels":[],"created_at":"2024-01-17T10:30:00Z","updated_at":"2024-01-17T10:30:00Z","html_url":"https://github.com/octocat/Hello-World/pull/2","pull_request":{"url":"https://api.github.com/repos/octocat/Hello-World/pulls/2"}}]
        """
    static let gitHubPullRequestJSON = """
        {"number":2,"title":"Fix the bug","body":"This fixes it","state":"open","head":{"ref":"fix-bug","sha":"abc123"},"base":{"ref":"main","sha":"def456"},"user":{"login":"hubot"},"draft":false,"merged":false,"html_url":"https://github.com/octocat/Hello-World/pull/2","created_at":"2024-01-17T10:30:00Z","updated_at":"2024-01-18T10:30:00Z"}
        """
    static let gitHubPullRequestFilesJSON = """
        [{"filename":"Sources/main.swift","status":"modified","additions":10,"deletions":2,"changes":12},
         {"filename":"README.md","status":"modified","additions":1,"deletions":0,"changes":1}]
        """
    static let gitHubPullRequestReviewsJSON = """
        [{"id":1,"user":{"login":"octocat"},"state":"APPROVED","body":"Looks good","submitted_at":"2024-01-18T10:30:00Z"},
         {"id":2,"user":{"login":"hubot"},"state":"COMMENTED","body":"One nit","submitted_at":"2024-01-18T11:00:00Z"}]
        """
    static let gitHubSearchIssuesJSON = """
        {"total_count":1,"incomplete_results":false,"items":[{"number":1,"title":"Found a bug","body":"Steps","state":"open","user":{"login":"octocat"},"labels":[],"created_at":"2024-01-15T10:30:00Z","updated_at":"2024-01-16T10:30:00Z","html_url":"https://github.com/octocat/Hello-World/issues/1"}]}
        """

    nonisolated static func gitHubPullRequestStub(_ request: URLRequest) -> (status: Int, headers: [String: String], body: Data) {
        switch request.url?.path {
        case "/repos/octocat/Hello-World/pulls/2": return gitHubStubOK(gitHubPullRequestJSON)
        case "/repos/octocat/Hello-World/pulls/2/files": return gitHubStubOK(gitHubPullRequestFilesJSON)
        case "/repos/octocat/Hello-World/pulls/2/reviews": return gitHubStubOK(gitHubPullRequestReviewsJSON)
        default: return gitHubStubError(404, "Not Found")
        }
    }

    func makeGitHubRepo(origin: String) throws -> URL {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("swiftcode-github-\(UUID().uuidString)")
        let sources = dir.appendingPathComponent("Sources/App")
        try FileManager.default.createDirectory(at: sources, withIntermediateDirectories: true)
        try "// swift-tools-version: 5.9\nimport PackageDescription\nlet package = Package(name: \"App\", targets: [.executableTarget(name: \"App\")])\n"
            .write(to: dir.appendingPathComponent("Package.swift"), atomically: true, encoding: .utf8)
        try "print(\"hi\")\n".write(to: sources.appendingPathComponent("main.swift"), atomically: true, encoding: .utf8)
        for args in [["init", "-q", "-b", "main"], ["remote", "add", "origin", origin]] {
            let p = Process()
            p.executableURL = URL(fileURLWithPath: "/usr/bin/git")
            p.arguments = ["-C", dir.path] + args
            p.standardOutput = FileHandle.nullDevice
            p.standardError = FileHandle.nullDevice
            try p.run()
            p.waitUntilExit()
            #expect(p.terminationStatus == 0, "git \(args.joined(separator: " ")) failed")
        }
        return dir
    }

    func openGitHubDir(_ dir: URL, policy: MCPWritePolicy = .allow) async throws -> SwiftCodeMCPHost {
        let host = SwiftCodeMCPHost()
        host.server.writePolicy = policy
        let ported = Set(host.agenticNetworkTools.map(\.name))
        host.server.tools = host.server.tools.filter { !ported.contains($0.name) } + host.agenticNetworkTools
        let r = try await host.server.callTool("workspace_open", ["path": .string(dir.path)])
        #expect(!r.isToolError, "\(r.resultText)")
        return host
    }

    @Test func gitHubCreateIssueCreatesViaStubClient() async throws {
        let sample = try TempSample()
        defer { sample.remove(); resetGitHubStub() }
        let host = try await opened(sample)
        installGitHubStub { request in
            guard request.url?.path == "/repos/octocat/Hello-World/issues", request.httpMethod == "POST" else {
                return gitHubStubError(404, "Not Found")
            }
            return gitHubStubOK(Self.gitHubIssueJSON)
        }
        let r = try await host.server.callTool("create_issue", [
            "repository": .string("octocat/Hello-World"),
            "title": .string("Fix the crash"), "body": .string("Steps to reproduce"),
        ])
        #expect(!r.isToolError, "\(r.resultText)")
        #expect(r.firstText.contains("Issue #42 created: Fix the crash"))
        #expect(r.structured?["number"]?.int == 42)
        #expect(r.structured?["htmlUrl"]?.string == "https://github.com/octocat/Hello-World/issues/42")
        let request = try #require(StubGitHubProtocol.requests.first)
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer test-token")
        let body = requestJSONBody(of: request)
        #expect(body["title"] as? String == "Fix the crash")
        #expect(body["labels"] as? [String] == [])
    }

    @Test func gitHubCreateIssueRefusesWithoutApproval() async throws {
        let sample = try TempSample()
        defer { sample.remove(); resetGitHubStub() }
        let host = try await opened(sample, policy: .review { _ in false })
        installGitHubStub { _ in gitHubStubOK(Self.gitHubIssueJSON) }
        let r = try await host.server.callTool("create_issue", [
            "repository": .string("octocat/Hello-World"),
            "title": .string("Fix the crash"), "body": .string("Steps"),
        ])
        #expect(r.isToolError)
        #expect(r.firstText.contains(MCPServer.rejectedMessage))
        #expect(StubGitHubProtocol.requests.isEmpty, "a refused write must not reach GitHub")
    }

    @Test func gitHubCreateIssueNeedsToken() async throws {
        let sample = try TempSample()
        defer { sample.remove(); resetGitHubStub() }
        let host = try await opened(sample)
        installGitHubStub(token: nil) { _ in gitHubStubOK(Self.gitHubIssueJSON) }
        let r = try await host.server.callTool("create_issue", [
            "repository": .string("octocat/Hello-World"),
            "title": .string("Fix the crash"), "body": .string("Steps"),
        ])
        #expect(r.isToolError)
        #expect(r.firstText.contains("No GitHub token saved"))
        #expect(StubGitHubProtocol.requests.isEmpty, "a token-less write must not reach GitHub")
    }

    @Test func gitHubCreatePullRequestCreatesViaStubClient() async throws {
        let sample = try TempSample()
        defer { sample.remove(); resetGitHubStub() }
        let host = try await opened(sample)
        installGitHubStub { request in
            guard request.url?.path == "/repos/octocat/Hello-World/pulls", request.httpMethod == "POST" else {
                return gitHubStubError(404, "Not Found")
            }
            return gitHubStubOK(Self.gitHubPullRequestJSON)
        }
        let r = try await host.server.callTool("create_pull_request", [
            "repository": .string("octocat/Hello-World"),
            "title": .string("Fix the bug"), "body": .string("This fixes it"),
            "head": .string("fix-bug"), "base": .string("main"),
        ])
        #expect(!r.isToolError, "\(r.resultText)")
        #expect(r.firstText.contains("Pull request #2 created: Fix the bug"))
        #expect(r.structured?["number"]?.int == 2)
        let request = try #require(StubGitHubProtocol.requests.first)
        #expect(request.httpMethod == "POST")
        let body = requestJSONBody(of: request)
        #expect(body["head"] as? String == "fix-bug")
        #expect(body["base"] as? String == "main")
        #expect(body["draft"] as? Bool == false)
    }

    @Test func gitHubUpdateIssueSendsOnlySuppliedFields() async throws {
        let sample = try TempSample()
        defer { sample.remove(); resetGitHubStub() }
        let host = try await opened(sample)
        installGitHubStub { request in
            guard request.url?.path == "/repos/octocat/Hello-World/issues/42", request.httpMethod == "PATCH" else {
                return gitHubStubError(404, "Not Found")
            }
            return gitHubStubOK(Self.gitHubIssueJSON)
        }
        let r = try await host.server.callTool("update_issue", [
            "repository": .string("octocat/Hello-World"),
            "issueNumber": .int(42), "title": .string("Fix the crash"),
        ])
        #expect(!r.isToolError, "\(r.resultText)")
        #expect(r.firstText.contains("Issue #42 updated: Fix the crash"))
        let request = try #require(StubGitHubProtocol.requests.first)
        #expect(request.httpMethod == "PATCH")
        let body = requestJSONBody(of: request)
        #expect(body["title"] as? String == "Fix the crash")
        #expect(body["body"] == nil, "only the supplied fields are sent")
        #expect(body["state"] == nil, "state is not in the tool's schema and is never sent")
    }

    @Test func gitHubUpdateIssueNeedsAField() async throws {
        let host = bareHost()
        let r = try await host.server.callTool("update_issue", ["issueNumber": .int(42)])
        #expect(r.isToolError)
        #expect(r.firstText.contains("Nothing to update"))
    }

    @Test func gitHubReadIssuesListsViaStubClient() async throws {
        let sample = try TempSample()
        defer { sample.remove(); resetGitHubStub() }
        let host = try await opened(sample)
        installGitHubStub(token: nil) { request in
            guard request.url?.path == "/repos/octocat/Hello-World/issues" else {
                return gitHubStubError(404, "Not Found")
            }
            return gitHubStubOK(Self.gitHubIssueListJSON)
        }
        let r = try await host.server.callTool("read_issues", ["repository": .string("octocat/Hello-World")])
        #expect(!r.isToolError, "\(r.resultText)")
        #expect(r.firstText.contains("Open issues in octocat/Hello-World (2):"))
        #expect(r.firstText.contains("#1: Found a bug"))
        #expect(r.structured?["count"]?.int == 2)
        let request = try #require(StubGitHubProtocol.requests.first)
        #expect(request.value(forHTTPHeaderField: "Authorization") == nil, "a public read sends no token")
    }

    @Test func gitHubReadIssuesReportsNotFound() async throws {
        let sample = try TempSample()
        defer { sample.remove(); resetGitHubStub() }
        let host = try await opened(sample)
        installGitHubStub(token: nil) { _ in gitHubStubError(404, "Not Found") }
        let r = try await host.server.callTool("read_issues", ["repository": .string("octocat/NoSuchRepo")])
        #expect(r.isToolError)
        #expect(r.firstText.contains("Not found on GitHub"))
    }

    @Test func gitHubReadIssuesRejectsInvalidRepository() async throws {
        resetGitHubStub()
        let sample = try TempSample()
        defer { sample.remove(); resetGitHubStub() }
        let host = try await opened(sample)
        let r = try await host.server.callTool("read_issues", ["repository": .string("not-a-repo")])
        #expect(r.isToolError)
        #expect(r.firstText.contains("Invalid repository"))
        #expect(StubGitHubProtocol.requests.isEmpty, "an invalid repository must not reach GitHub")
    }

    @Test func gitHubReadPullRequestSummarisesPR() async throws {
        let sample = try TempSample()
        defer { sample.remove(); resetGitHubStub() }
        let host = try await opened(sample)
        installGitHubStub(token: nil, handler: Self.gitHubPullRequestStub)
        let r = try await host.server.callTool("read_pull_request", [
            "repository": .string("octocat/Hello-World"), "prNumber": .int(2),
        ])
        #expect(!r.isToolError, "\(r.resultText)")
        #expect(r.firstText.contains("Pull request #2: Fix the bug"))
        #expect(r.firstText.contains("State: open — fix-bug → main"))
        #expect(r.firstText.contains("Files changed (2, +11/-2):"))
        #expect(r.firstText.contains("- Sources/main.swift (+10/-2)"))
        #expect(r.firstText.contains("- octocat: APPROVED"))
        #expect(r.structured?["filesChanged"]?.int == 2)
        #expect(r.structured?["additions"]?.int == 11)
        #expect(r.structured?["deletions"]?.int == 2)
        #expect(StubGitHubProtocol.requests.count == 3, "PR + files + reviews")
    }

    @Test func gitHubReadPullRequestDerivesRepoFromRemoteOrigin() async throws {
        let dir = try makeGitHubRepo(origin: "https://github.com/octocat/Hello-World.git")
        defer { try? FileManager.default.removeItem(at: dir); resetGitHubStub() }
        let host = try await openGitHubDir(dir)
        installGitHubStub(token: nil, handler: Self.gitHubPullRequestStub)
        let r = try await host.server.callTool("read_pull_request", ["prNumber": .int(2)])
        #expect(!r.isToolError, "\(r.resultText)")
        #expect(r.firstText.contains("Pull request #2: Fix the bug"))
        #expect(r.firstText.contains("fix-bug → main"))
    }

    @Test func gitHubReviewPullRequestIsReadOnlySummary() async throws {
        let sample = try TempSample()
        defer { sample.remove(); resetGitHubStub() }
        let host = try await opened(sample)
        installGitHubStub(token: nil, handler: Self.gitHubPullRequestStub)
        let r = try await host.server.callTool("review_pull_request", [
            "repository": .string("octocat/Hello-World"), "prNumber": .int(2),
        ])
        #expect(!r.isToolError, "\(r.resultText)")
        #expect(r.firstText.contains("Review of pull request #2: Fix the bug"))
        #expect(r.firstText.contains("no review was posted to GitHub"))
        #expect(StubGitHubProtocol.requests.allSatisfy { $0.httpMethod == "GET" }, "review_pull_request must not POST")
    }

    @Test func gitHubSearchIssuesScopesQueryToRepo() async throws {
        let sample = try TempSample()
        defer { sample.remove(); resetGitHubStub() }
        let host = try await opened(sample)
        installGitHubStub(token: nil) { request in
            guard request.url?.path == "/search/issues" else { return gitHubStubError(404, "Not Found") }
            return gitHubStubOK(Self.gitHubSearchIssuesJSON)
        }
        let r = try await host.server.callTool("search_issues", [
            "repository": .string("octocat/Hello-World"), "query": .string("crash"),
        ])
        #expect(!r.isToolError, "\(r.resultText)")
        #expect(r.firstText.contains("Issues matching \"crash\" (1 total):"))
        #expect(r.firstText.contains("#1: Found a bug"))
        #expect(r.structured?["totalCount"]?.int == 1)
        let request = try #require(StubGitHubProtocol.requests.first)
        #expect(requestQueryItems(of: request)["q"] == "repo:octocat/Hello-World crash")
    }

    @Test func gitHubSearchIssuesRunsUnscopedWithoutRepo() async throws {
        let sample = try TempSample()
        defer { sample.remove(); resetGitHubStub() }
        let host = try await opened(sample)
        installGitHubStub(token: nil) { request in
            guard request.url?.path == "/search/issues" else { return gitHubStubError(404, "Not Found") }
            return gitHubStubOK(Self.gitHubSearchIssuesJSON)
        }
        let r = try await host.server.callTool("search_issues", ["query": .string("crash")])
        #expect(!r.isToolError, "\(r.resultText)")
        let request = try #require(StubGitHubProtocol.requests.first)
        #expect(requestQueryItems(of: request)["q"] == "crash")
    }

    @Test func gitHubToolsValidateArgumentsFirst() async throws {
        let host = bareHost()
        let cases: [(String, [String: AnyJSON], String)] = [
            ("create_pull_request", [:], "Missing title, body, head, or base"),
            ("review_pull_request", [:], "Missing prNumber"),
            ("read_pull_request", [:], "Missing prNumber"),
            ("read_issues", [:], "Missing repository"),
            ("create_issue", ["title": .string("T")], "Missing title or body"),
            ("update_issue", [:], "Missing issueNumber"),
            ("search_issues", [:], "Missing query"),
        ]
        for (name, arguments, message) in cases {
            let r = try await host.server.callTool(name, arguments)
            #expect(r.isToolError)
            #expect(r.firstText.contains(message), "\(name): \(r.firstText)")
        }
    }
}

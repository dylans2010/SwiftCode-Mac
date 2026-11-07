import Foundation
import Testing
import SwiftCodeAssistant
import SwiftCodeIDECore
@testable import SwiftCodeMCP

@MainActor
@Suite(.serialized) struct SwiftCodeAgenticFilesTests {
    static let agenticFilesIDs = ["read_multiple_files", "search_files", "find_text", "replace_text", "grep", "glob_search"]

    func opened(_ sample: TempSample, policy: MCPWritePolicy = .readOnly) async throws -> SwiftCodeMCPHost {
        let host = SwiftCodeMCPHost()
        host.server.writePolicy = policy
        let ported = Set(host.agenticFilesTools.map(\.name))
        host.server.tools = host.server.tools.filter { !ported.contains($0.name) } + host.agenticFilesTools
        let r = try await host.server.callTool("workspace_open", ["path": .string(sample.url.path)])
        #expect(!r.isToolError, "\(r.resultText)")
        return host
    }

    func writeFixture(_ sample: TempSample, _ rel: String, _ content: String) throws {
        let url = URL(fileURLWithPath: sample.path(rel))
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try content.write(to: url, atomically: true, encoding: .utf8)
    }

    @Test func toolsAreRegisteredWithLegacySchemas() async throws {
        let host = SwiftCodeMCPHost()
        let tools = host.agenticFilesTools
        #expect(tools.map(\.name) == Self.agenticFilesIDs)
        let expectedTitles: [String: String] = [
            "read_multiple_files": "Read Multiple Files", "search_files": "Search Files", "find_text": "Find Text",
            "replace_text": "Replace Text", "grep": "Grep", "glob_search": "Glob Search",
        ]
        let expectedDescriptions: [String: String] = [
            "read_multiple_files": "Reads the content of multiple files.",
            "search_files": "Searches for files matching a pattern in a directory.",
            "find_text": "Searches for text in a directory.",
            "replace_text": "Replaces text in a file.",
            "grep": "Searches for a pattern in a directory using grep.",
            "glob_search": "Searches for files matching a glob pattern.",
        ]
        let expectedRequired: [String: [String]] = [
            "read_multiple_files": ["paths"], "search_files": ["directory", "pattern"], "find_text": ["directory", "text"],
            "replace_text": ["path", "target", "replacement"], "grep": ["pattern", "directory"], "glob_search": ["pattern"],
        ]
        let expectedOutputs: [String: [String]] = [
            "read_multiple_files": ["files"], "search_files": ["count", "files"], "find_text": ["results"],
            "replace_text": ["path", "replacementCount"], "grep": ["results"], "glob_search": ["count", "files"],
        ]
        for tool in tools {
            #expect(tool.title == expectedTitles[tool.name])
            #expect(tool.description == expectedDescriptions[tool.name], "\(tool.name) description is not Legacy-verbatim")
            if tool.name == "replace_text" {
                #expect(!tool.annotations.readOnly && tool.annotations.idempotent && !tool.annotations.destructive && tool.writes,
                        "replace_text must be a gated safe-mutation tool")
            } else {
                #expect(tool.annotations.readOnly && tool.annotations.idempotent && !tool.writes, "\(tool.name) must be a read-only tool")
            }
            #expect(tool.inputSchema["properties"]?["workspace"] != nil, "\(tool.name) is missing the workspace parameter")
            let required = tool.inputSchema["required"]?.array?.compactMap(\.string) ?? []
            #expect(required == expectedRequired[tool.name], "\(tool.name) required: \(required)")
            let outputKeys = tool.outputSchema?["properties"]?.object?.keys.sorted() ?? []
            #expect(outputKeys == expectedOutputs[tool.name], "\(tool.name) output keys: \(outputKeys)")
        }
        let installed = Set(host.agenticFilesTools.map(\.name))
        host.server.tools = host.server.tools.filter { !installed.contains($0.name) } + host.agenticFilesTools
        let served = host.server.tools.map(\.name)
        for id in Self.agenticFilesIDs { #expect(served.contains(id), "\(id) is not installed on the server") }
        #expect(Set(served).count == served.count, "duplicate tool names on the server")
    }

    @Test func readMultipleFilesReadsInRequestOrder() async throws {
        let sample = try TempSample()
        defer { sample.remove() }
        let host = try await opened(sample)
        let missing = try await host.server.callTool("read_multiple_files", [:])
        #expect(missing.isToolError && missing.resultText.contains("missing the required argument \"paths\""))
        let found = try await host.server.callTool("read_multiple_files",
                                                   ["paths": .array([.string("Sources/Greeter/Greeter.swift"), .string("Package.swift")])])
        #expect(!found.isToolError, "\(found.resultText)")
        let files = found.structured?["files"]?.array ?? []
        #expect(files.count == 2)
        #expect(files[0]["path"]?.string == "Sources/Greeter/Greeter.swift")
        #expect(files[0]["content"]?.string?.hasPrefix("/// Makes greetings.\npublic struct Greeter {") == true)
        #expect(files[1]["path"]?.string == "Package.swift")
        #expect(files[1]["content"]?.string?.contains("let package = Package(") == true)
        #expect(found.firstText.hasPrefix("--- FILE: Sources/Greeter/Greeter.swift ---\n/// Makes greetings."))
        #expect(found.firstText.contains("--- FILE: Package.swift ---\n// swift-tools-version: 5.9"))
        let gone = try await host.server.callTool("read_multiple_files", ["paths": .array([.string("Sources/Greeter/Greeter.swift"), .string("nope.swift")])])
        #expect(gone.isToolError && gone.resultText.contains("Failed to read file at nope.swift"))
        let blank = try await host.server.callTool("read_multiple_files", ["paths": .array([.string("")])])
        #expect(blank.isToolError && blank.resultText.contains("paths[0] must be a non-empty string path."))
        let outside = try await host.server.callTool("read_multiple_files", ["paths": .array([.string("../escape.txt")])])
        #expect(outside.isToolError && outside.resultText.contains("is outside the workspace folder"))
    }

    @Test func searchFilesFindsByFileNameSubstring() async throws {
        let sample = try TempSample()
        defer { sample.remove() }
        let host = try await opened(sample)
        let found = try await host.server.callTool("search_files", ["directory": .string("."), "pattern": .string("Greeter")])
        #expect(!found.isToolError, "\(found.resultText)")
        #expect(found.structured?["files"]?.array?.compactMap(\.string) == ["Sources/Greeter/Greeter.swift", "Tests/GreeterTests/GreeterTests.swift"])
        #expect(found.structured?["count"]?.int == 2)
        #expect(found.firstText == "Found 2 file(s) matching 'Greeter' in .")
        let lower = try await host.server.callTool("search_files", ["directory": .string("."), "pattern": .string("greeter")])
        #expect(!lower.isToolError && lower.structured?["files"]?.array?.isEmpty == true && lower.structured?["count"]?.int == 0)
        #expect(lower.firstText == "No files matching 'greeter' found in .")
        let scoped = try await host.server.callTool("search_files", ["directory": .string("Tests"), "pattern": .string("Greeter")])
        #expect(scoped.structured?["files"]?.array?.compactMap(\.string) == ["Tests/GreeterTests/GreeterTests.swift"])
        let gone = try await host.server.callTool("search_files", ["directory": .string("Nope"), "pattern": .string("x")])
        #expect(gone.isToolError && gone.resultText.contains("Directory not found: Nope"))
        let file = try await host.server.callTool("search_files", ["directory": .string("Package.swift"), "pattern": .string("x")])
        #expect(file.isToolError && file.resultText.contains("Not a directory: Package.swift"))
        let outside = try await host.server.callTool("search_files", ["directory": .string(".."), "pattern": .string("x")])
        #expect(outside.isToolError && outside.resultText.contains("is outside the workspace folder"))
    }

    @Test func findTextIsCaseSensitiveLiteral() async throws {
        let sample = try TempSample()
        defer { sample.remove() }
        let host = try await opened(sample)
        let found = try await host.server.callTool("find_text", ["directory": .string("."), "text": .string("salutation")])
        #expect(!found.isToolError, "\(found.resultText)")
        #expect(found.structured?["results"]?.string == "Sources/Greeter/Greeter.swift: 4, 6, 7, 12\nTests/GreeterTests/GreeterTests.swift: 10")
        #expect(found.firstText == "Text search results for 'salutation' in .:")
        let upper = try await host.server.callTool("find_text", ["directory": .string("."), "text": .string("SALUTATION")])
        #expect(!upper.isToolError && upper.structured?["results"]?.string == "")
        #expect(upper.firstText == "No matches found.")
        let capital = try await host.server.callTool("find_text", ["directory": .string("."), "text": .string("Salutation")])
        #expect(capital.structured?["results"]?.string == "Tests/GreeterTests/GreeterTests.swift: 9")
        let scoped = try await host.server.callTool("find_text", ["directory": .string("Sources"), "text": .string("salutation")])
        #expect(scoped.structured?["results"]?.string == "Sources/Greeter/Greeter.swift: 4, 6, 7, 12")
        let gone = try await host.server.callTool("find_text", ["directory": .string("Nope"), "text": .string("x")])
        #expect(gone.isToolError && gone.resultText.contains("Directory not found: Nope"))
    }

    @Test func replaceTextReplacesAllOccurrences() async throws {
        let sample = try TempSample()
        defer { sample.remove() }
        try writeFixture(sample, "notes.txt", "foo bar foo\nfoo\n")
        let host = try await opened(sample, policy: .allow)
        let replaced = try await host.server.callTool("replace_text",
                                                      ["path": .string("notes.txt"), "target": .string("foo"), "replacement": .string("baz")])
        #expect(!replaced.isToolError, "\(replaced.resultText)")
        #expect(replaced.structured?["replacementCount"]?.int == 3)
        #expect(replaced.structured?["path"]?.string == "notes.txt")
        #expect(replaced.firstText == "Successfully replaced text in notes.txt")
        #expect(sample.read("notes.txt") == "baz bar baz\nbaz\n")
        let absent = try await host.server.callTool("replace_text",
                                                    ["path": .string("notes.txt"), "target": .string("zzz"), "replacement": .string("q")])
        #expect(!absent.isToolError && absent.structured?["replacementCount"]?.int == 0)
        #expect(sample.read("notes.txt") == "baz bar baz\nbaz\n")
        let empty = try await host.server.callTool("replace_text",
                                                   ["path": .string("notes.txt"), "target": .string(""), "replacement": .string("q")])
        #expect(empty.isToolError && empty.resultText.contains("Target must not be empty."))
        let gone = try await host.server.callTool("replace_text",
                                                  ["path": .string("nope.txt"), "target": .string("a"), "replacement": .string("b")])
        #expect(gone.isToolError && gone.resultText.contains("Failed to read file at nope.txt"))
    }

    @Test func replaceTextApprovalRefusalLeavesFileUnchanged() async throws {
        let sample = try TempSample()
        defer { sample.remove() }
        try writeFixture(sample, "notes.txt", "foo bar foo\n")
        let host = try await opened(sample, policy: .review { _ in false })
        let refused = try await host.server.callTool("replace_text",
                                                     ["path": .string("notes.txt"), "target": .string("foo"), "replacement": .string("baz")])
        #expect(refused.isToolError && refused.firstText == MCPServer.rejectedMessage)
        #expect(sample.read("notes.txt") == "foo bar foo\n")
        let readOnlyHost = try await opened(sample)
        let blocked = try await readOnlyHost.server.callTool("replace_text",
                                                             ["path": .string("notes.txt"), "target": .string("foo"), "replacement": .string("baz")])
        #expect(blocked.isToolError && blocked.resultText.contains("replace_text changes files, and this SwiftCode MCP server is read-only."))
        #expect(sample.read("notes.txt") == "foo bar foo\n")
    }

    @Test func replaceTextRejectsOutsideWorkspace() async throws {
        let sample = try TempSample()
        defer { sample.remove() }
        try writeFixture(sample, "notes.txt", "foo\n")
        let host = try await opened(sample, policy: .allow)
        let outside = try await host.server.callTool("replace_text",
                                                     ["path": .string("../escape.txt"), "target": .string("a"), "replacement": .string("b")])
        #expect(outside.isToolError && outside.resultText.contains("is outside the workspace folder"))
        let inside = try await host.server.callTool("replace_text",
                                                    ["path": .string("Sources/../notes.txt"), "target": .string("foo"), "replacement": .string("baz")])
        #expect(!inside.isToolError, "\(inside.resultText)")
        #expect(sample.read("notes.txt") == "baz\n")
    }

    @Test func grepSearchesDirectoryWithRegex() async throws {
        let sample = try TempSample()
        defer { sample.remove() }
        let host = try await opened(sample)
        let found = try await host.server.callTool("grep", ["pattern": .string(#"greeting\(for"#), "directory": .string(".")])
        #expect(!found.isToolError, "\(found.resultText)")
        #expect(found.structured?["results"]?.string == """
            Sources/Greeter/Greeter.swift:11:     public func greeting(for name: String) -> String {
            Sources/greet/main.swift:4: print(Greeter().greeting(for: name))
            Tests/GreeterTests/GreeterTests.swift:6:         XCTAssertEqual(Greeter().greeting(for: "Ada"), "Hello, Ada!")
            Tests/GreeterTests/GreeterTests.swift:10:         XCTAssertEqual(Greeter(salutation: "Hi").greeting(for: "Bo"), "Hi, Bo!")
            """)
        #expect(found.firstText == #"Grep search completed for 'greeting\(for'"#)
        let upper = try await host.server.callTool("grep", ["pattern": .string("SALUTATION"), "directory": .string(".")])
        #expect(!upper.isToolError && upper.structured?["results"]?.string == "")
        let scoped = try await host.server.callTool("grep", ["pattern": .string(#"greeting\(for"#), "directory": .string("Tests")])
        #expect(scoped.structured?["results"]?.string == """
            Tests/GreeterTests/GreeterTests.swift:6:         XCTAssertEqual(Greeter().greeting(for: "Ada"), "Hello, Ada!")
            Tests/GreeterTests/GreeterTests.swift:10:         XCTAssertEqual(Greeter(salutation: "Hi").greeting(for: "Bo"), "Hi, Bo!")
            """)
        let invalid = try await host.server.callTool("grep", ["pattern": .string("["), "directory": .string(".")])
        #expect(invalid.isToolError && invalid.resultText.contains("Regex search failed:"))
        let gone = try await host.server.callTool("grep", ["pattern": .string("x"), "directory": .string("Nope")])
        #expect(gone.isToolError && gone.resultText.contains("Directory not found: Nope"))
    }

    @Test func globSearchMatchesFileNames() async throws {
        let sample = try TempSample()
        defer { sample.remove() }
        let host = try await opened(sample)
        let all = try await host.server.callTool("glob_search", ["pattern": .string("*.swift")])
        #expect(!all.isToolError, "\(all.resultText)")
        #expect(all.structured?["files"]?.array?.compactMap(\.string) == ["Package.swift", "Previews/GreetingView.swift",
                                                                          "Sources/Greeter/Greeter.swift", "Sources/greet/main.swift",
                                                                          "Tests/GreeterTests/GreeterTests.swift"])
        #expect(all.structured?["count"]?.int == 5)
        #expect(all.firstText == "Found 5 file(s) matching '*.swift'.")
        let greeter = try await host.server.callTool("glob_search", ["pattern": .string("Greeter*.swift")])
        #expect(greeter.structured?["files"]?.array?.compactMap(\.string) == ["Sources/Greeter/Greeter.swift",
                                                                              "Tests/GreeterTests/GreeterTests.swift"])
        let strings = try await host.server.callTool("glob_search", ["pattern": .string("*.xcstrings")])
        #expect(strings.structured?["files"]?.array?.compactMap(\.string) == ["Strings/Localizable.xcstrings"])
        let none = try await host.server.callTool("glob_search", ["pattern": .string("zzz*")])
        #expect(!none.isToolError && none.structured?["files"]?.array?.isEmpty == true && none.structured?["count"]?.int == 0)
        #expect(none.firstText == "No files matching 'zzz*' found.")
        let slashed = try await host.server.callTool("glob_search", ["pattern": .string("Sources/*.swift")])
        #expect(!slashed.isToolError && slashed.structured?["count"]?.int == 0)
    }
}

import Foundation
import Testing
import YcodeAssistant
import YcodeIDECore
@testable import YcodeMCP

@MainActor
@Suite(.serialized) struct SwiftCodeFileReadingTests {
    func opened(_ sample: TempSample) async throws -> SwiftCodeMCPHost {
        let host = SwiftCodeMCPHost()
        let r = try await host.server.callTool("workspace_open", ["path": .string(sample.url.path)])
        #expect(!r.isToolError, "\(r.resultText)")
        return host
    }

    func totalBytes(under url: URL) -> Int {
        var total = 0
        let enumerator = FileManager.default.enumerator(at: url, includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey],
                                                        options: [.skipsHiddenFiles])
        while let file = enumerator?.nextObject() as? URL {
            var isReg: AnyObject?
            try? (file as NSURL).getResourceValue(&isReg, forKey: .isRegularFileKey)
            guard (isReg as? Bool) == true else { continue }
            total += ((try? file.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0)
        }
        return total
    }

    @Test func toolsAreRegisteredWithLegacySchemas() async throws {
        let host = SwiftCodeMCPHost()
        let tools = host.fileReadingTools
        #expect(tools.map(\.name) == ["dir_read", "dir_pwd", "dir_cd", "dir_size_report", "file_metadata", "file_head_preview",
                                      "count_file_lines", "tree_view"])
        let expectedTitles: [String: String] = [
            "dir_read": "Read Directory", "dir_pwd": "Print Working Directory", "dir_cd": "Change Directory",
            "dir_size_report": "Directory Size Report", "file_metadata": "File Metadata", "file_head_preview": "File Head Preview",
            "count_file_lines": "Count File Lines and Code Metrics", "tree_view": "Tree View",
        ]
        let expectedRequired: [String: [String]] = [
            "dir_read": ["path"], "dir_pwd": [], "dir_cd": ["path"], "dir_size_report": [], "file_metadata": ["path"],
            "file_head_preview": ["path"], "count_file_lines": ["path"], "tree_view": [],
        ]
        let expectedOutputs: [String: [String]] = [
            "dir_read": ["contents", "count", "path"], "dir_pwd": ["path"],
            "dir_cd": ["contents", "count", "path", "previousPath"], "dir_size_report": ["entryCount", "totalBytes"],
            "file_metadata": ["creationDate", "extension", "fileName", "fileType", "isDirectory", "modificationDate", "path",
                              "permissions", "permissionsOctal", "size"],
            "file_head_preview": ["encoding", "path", "shownLines", "totalLines", "truncated"],
            "count_file_lines": ["blankLines", "codeLines", "commentLines", "fileCount", "path", "totalBytes", "totalLines"],
            "tree_view": ["entries", "path", "tree", "truncated"],
        ]
        for tool in tools {
            #expect(tool.title == expectedTitles[tool.name])
            #expect(tool.annotations.readOnly && tool.annotations.idempotent && !tool.writes, "\(tool.name) must be a read-only tool")
            #expect(tool.inputSchema["properties"]?["workspace"] != nil, "\(tool.name) is missing the workspace parameter")
            let required = tool.inputSchema["required"]?.array?.compactMap(\.string) ?? []
            #expect(required == expectedRequired[tool.name], "\(tool.name) required: \(required)")
            let outputKeys = tool.outputSchema?["properties"]?.object?.keys.sorted() ?? []
            #expect(outputKeys == expectedOutputs[tool.name], "\(tool.name) output keys: \(outputKeys)")
        }
        let served = host.server.tools.map(\.name)
        for id in expectedTitles.keys { #expect(served.contains(id), "\(id) is not installed on the server") }
    }

    @Test func dirReadListsSortedEntriesWithMarkers() async throws {
        let sample = try TempSample()
        defer { sample.remove() }
        let host = try await opened(sample)
        let empty = try await host.server.callTool("dir_read", ["path": ""])
        #expect(empty.isToolError && empty.resultText.contains("missing the required argument \"path\""))
        let read = try await host.server.callTool("dir_read", ["path": "."])
        #expect(!read.isToolError, "\(read.resultText)")
        #expect(read.structured?["contents"]?.string == "Package.swift\nPreviews/\nSources/\nStrings/\nTests/")
        #expect(read.structured?["count"]?.int == 5)
        #expect(read.structured?["path"] == sample.url.standardizedFileURL.path)
        #expect(read.resultText.hasPrefix("Successfully read directory: . (5 entries)"))

        let sub = try await host.server.callTool("dir_read", ["path": "Sources/Greeter"])
        #expect(sub.structured?["contents"]?.string == "Greeter.swift" && sub.structured?["count"]?.int == 1)

        let missing = try await host.server.callTool("dir_read", ["path": "Nope"])
        #expect(missing.isToolError && missing.resultText.contains("Failed to read directory at Nope"))
        let file = try await host.server.callTool("dir_read", ["path": "Package.swift"])
        #expect(file.isToolError && file.resultText.contains("Failed to read directory at Package.swift"))
        let outside = try await host.server.callTool("dir_read", ["path": "../../etc/hosts"])
        #expect(outside.isToolError && outside.resultText.contains("outside the workspace"))
    }

    @Test func dirPwdDefaultsToRoot() async throws {
        let sample = try TempSample()
        defer { sample.remove() }
        let host = try await opened(sample)
        let pwd = try await host.server.callTool("dir_pwd")
        #expect(!pwd.isToolError, "\(pwd.resultText)")
        #expect(pwd.structured?["path"] == sample.url.standardizedFileURL.path)
        #expect(pwd.resultText.hasPrefix("Working directory: "))
    }

    @Test func dirCdThenPwdRoundTrip() async throws {
        let sample = try TempSample()
        defer { sample.remove() }
        let host = try await opened(sample)
        let root = sample.url.standardizedFileURL.path

        let cd = try await host.server.callTool("dir_cd", ["path": "Sources"])
        #expect(!cd.isToolError, "\(cd.resultText)")
        #expect(cd.structured?["path"] == root + "/Sources" && cd.structured?["previousPath"] == root)
        #expect(cd.structured?["contents"]?.string == "Greeter\ngreet" && cd.structured?["count"]?.int == 2)
        #expect(cd.resultText.hasPrefix("Working directory changed to \(root)/Sources"))

        let pwd = try await host.server.callTool("dir_pwd")
        #expect(pwd.structured?["path"] == root + "/Sources")

        let read = try await host.server.callTool("dir_read", ["path": "."])
        #expect(read.structured?["contents"]?.string == "Greeter/\ngreet/")

        let noop = try await host.server.callTool("dir_cd", ["path": "."])
        #expect(noop.structured?["path"] == root + "/Sources")
        let up = try await host.server.callTool("dir_cd", ["path": ".."])
        #expect(up.structured?["path"] == root && up.structured?["previousPath"] == root + "/Sources")

        let abs = try await host.server.callTool("dir_cd", ["path": "/Tests"])
        #expect(abs.structured?["path"] == root + "/Tests")
        #expect(try await host.server.callTool("dir_pwd").structured?["path"] == root + "/Tests")
    }

    @Test func dirCdPastRootFailsAndKeepsCwd() async throws {
        let sample = try TempSample()
        defer { sample.remove() }
        let host = try await opened(sample)
        let root = sample.url.standardizedFileURL.path
        #expect(try await host.server.callTool("dir_cd", ["path": "Sources"]).structured?["path"] == root + "/Sources")

        let past = try await host.server.callTool("dir_cd", ["path": "../.."])
        #expect(past.isToolError && past.resultText.contains("outside the workspace"))
        #expect(try await host.server.callTool("dir_pwd").structured?["path"] == root + "/Sources")

        let missing = try await host.server.callTool("dir_cd", ["path": "Nope"])
        #expect(missing.isToolError && missing.resultText.contains("Failed to change directory to Nope"))
        #expect(try await host.server.callTool("dir_pwd").structured?["path"] == root + "/Sources")

        let file = try await host.server.callTool("dir_cd", ["path": "Package.swift"])
        #expect(file.isToolError && file.resultText.contains("Failed to change directory to Package.swift"))
        #expect(try await host.server.callTool("dir_pwd").structured?["path"] == root + "/Sources")
    }

    @Test func dirSizeReportLargestFirst() async throws {
        let sample = try TempSample()
        defer { sample.remove() }
        let host = try await opened(sample)
        let report = try await host.server.callTool("dir_size_report")
        #expect(!report.isToolError, "\(report.resultText)")
        #expect(report.structured?["entryCount"]?.int == 5)
        #expect(report.structured?["totalBytes"] == totalBytes(under: sample.url))
        #expect(report.resultText.hasPrefix("Directory sizes under .:"))
        #expect(report.resultText.contains("- Package.swift — 537 bytes (0.00 MB)"))
        let lines = text.components(separatedBy: "\n")
        let packageLine = try #require(lines.firstIndex { $0.hasPrefix("- Package.swift") })
        let sourcesLine = try #require(lines.firstIndex { $0.hasPrefix("- Sources/") })
        #expect(packageLine < sourcesLine)

        let limited = try await host.server.callTool("dir_size_report", ["limit": 1])
        let rows = limited.resultText.components(separatedBy: "\n").filter { $0.hasPrefix("- ") }
        #expect(rows.count == 1 && limited.structured?["entryCount"]?.int == 5 && limited.structured?["totalBytes"]?.int == 2047)

        let sub = try await host.server.callTool("dir_size_report", ["path": "Sources"])
        #expect(sub.structured?["entryCount"]?.int == 2 && sub.structured?["totalBytes"]?.int == 489)
        #expect(sub.resultText.hasPrefix("Directory sizes under Sources:"))

        let notDir = try await host.server.callTool("dir_size_report", ["path": "Package.swift"])
        #expect(notDir.isToolError && notDir.resultText.contains("Not a directory: Package.swift"))
        let outside = try await host.server.callTool("dir_size_report", ["path": "../../etc"])
        #expect(outside.isToolError && outside.resultText.contains("outside the workspace"))
    }

    @Test func fileMetadataForFileAndDirectory() async throws {
        let sample = try TempSample()
        defer { sample.remove() }
        let host = try await opened(sample)
        let meta = try await host.server.callTool("file_metadata", ["path": "Sources/Greeter/Greeter.swift"])
        #expect(!meta.isToolError, "\(meta.resultText)")
        #expect(meta.structured?["path"]?.string == "Sources/Greeter/Greeter.swift")
        #expect(meta.structured?["fileName"]?.string == "Greeter.swift" && meta.structured?["extension"]?.string == "swift")
        #expect(meta.structured?["isDirectory"]?.bool == false && meta.structured?["fileType"]?.string == "regular")
        #expect(meta.structured?["size"]?.int == 374)
        #expect(meta.structured?["permissions"] == meta.structured?["permissionsOctal"])
        let permissions = meta.structured?["permissions"]?.string ?? ""
        #expect(!permissions.isEmpty && permissions.allSatisfy { "01234567".contains($0) })
        #expect(!(meta.structured?["creationDate"]?.string ?? "").isEmpty)
        #expect(!(meta.structured?["modificationDate"]?.string ?? "").isEmpty)
        #expect(meta.resultText.contains("Metadata for Sources/Greeter/Greeter.swift:"))
        #expect(meta.resultText.contains("- Size: 374 bytes"))

        let dir = try await host.server.callTool("file_metadata", ["path": "Sources"])
        #expect(dir.structured?["isDirectory"]?.bool == true && dir.structured?["fileType"]?.string == "directory")
        #expect(dir.structured?["path"]?.string == "Sources" && dir.structured?["extension"]?.string == "")

        let missing = try await host.server.callTool("file_metadata", ["path": "Nope"])
        #expect(missing.isToolError && missing.resultText.contains("No file or directory at path: Nope"))
        let outside = try await host.server.callTool("file_metadata", ["path": "../../etc/hosts"])
        #expect(outside.isToolError && outside.resultText.contains("outside the workspace"))
    }

    @Test func fileHeadPreviewWithTruncation() async throws {
        let sample = try TempSample()
        defer { sample.remove() }
        let host = try await opened(sample)
        let head = try await host.server.callTool("file_head_preview", ["path": "Sources/Greeter/Greeter.swift"])
        #expect(!head.isToolError, "\(head.resultText)")
        #expect(head.structured?["path"]?.string == "Sources/Greeter/Greeter.swift")
        #expect(head.structured?["encoding"]?.string == "utf-8")
        #expect(head.structured?["totalLines"]?.int == 15 && head.structured?["shownLines"]?.int == 15)
        #expect(head.structured?["truncated"]?.bool == false)
        #expect(head.resultText.hasPrefix("Preview of Sources/Greeter/Greeter.swift [utf-8, 15 total lines]:\n1: /// Makes greetings."))

        let three = try await host.server.callTool("file_head_preview", ["path": "Sources/Greeter/Greeter.swift", "lines": 3])
        #expect(three.structured?["shownLines"]?.int == 3 && three.structured?["truncated"]?.bool == true)
        #expect(three.resultText.contains("… [truncated: showing 3 of 15 lines]"))

        let clamped = try await host.server.callTool("file_head_preview", ["path": "Sources/Greeter/Greeter.swift", "lines": 200])
        #expect(clamped.structured?["shownLines"]?.int == 15 && clamped.structured?["truncated"]?.bool == false)

        let missing = try await host.server.callTool("file_head_preview", ["path": "Nope"])
        #expect(missing.isToolError && missing.resultText.contains("Cannot read file: Nope"))
        let outside = try await host.server.callTool("file_head_preview", ["path": "../../etc/hosts"])
        #expect(outside.isToolError && outside.resultText.contains("outside the workspace"))
    }

    @Test func countFileLinesForFileAndDirectory() async throws {
        let sample = try TempSample()
        defer { sample.remove() }
        let host = try await opened(sample)
        let file = try await host.server.callTool("count_file_lines", ["path": "Sources/Greeter/Greeter.swift"])
        #expect(!file.isToolError, "\(file.resultText)")
        #expect(file.structured?["path"]?.string == "Sources/Greeter/Greeter.swift")
        #expect(file.structured?["fileCount"]?.int == 1 && file.structured?["totalLines"]?.int == 15)
        #expect(file.structured?["codeLines"]?.int == 9 && file.structured?["commentLines"]?.int == 3 && file.structured?["blankLines"]?.int == 3)
        #expect(file.structured?["totalBytes"]?.int == 374)
        #expect(file.resultText.hasPrefix("Code Metrics for Sources/Greeter/Greeter.swift (1 file(s)):"))

        let dir = try await host.server.callTool("count_file_lines", ["path": "Sources", "extension": "swift"])
        #expect(dir.structured?["fileCount"]?.int == 2 && dir.structured?["totalLines"]?.int == 20)
        #expect(dir.structured?["codeLines"]?.int == 12 && dir.structured?["commentLines"]?.int == 3 && dir.structured?["blankLines"]?.int == 5)
        #expect(dir.structured?["totalBytes"]?.int == 489)

        let alias = try await host.server.callTool("count_file_lines", ["targetPath": "Sources/Greeter/Greeter.swift", "extension": "md"])
        #expect(alias.structured?["fileCount"]?.int == 1 && alias.structured?["totalLines"]?.int == 15)

        let missing = try await host.server.callTool("count_file_lines", ["path": "Nope"])
        #expect(missing.isToolError && missing.resultText.contains("Path not found: Nope"))
        let outside = try await host.server.callTool("count_file_lines", ["path": "../../etc/hosts"])
        #expect(outside.isToolError && outside.resultText.contains("outside the workspace"))
    }

    @Test func binaryFileHandling() async throws {
        let sample = try TempSample()
        defer { sample.remove() }
        let host = try await opened(sample)
        let binary = Data([0x00, 0xD8, 0xFF])
        try binary.write(to: URL(fileURLWithPath: sample.path("Sources/Binary.dat")))
        let counted = try await host.server.callTool("count_file_lines", ["path": "Sources/Binary.dat"])
        #expect(!counted.isToolError, "\(counted.resultText)")
        #expect(counted.structured?["fileCount"]?.int == 1 && counted.structured?["totalLines"]?.int == 0)
        #expect(counted.structured?["totalBytes"]?.int == 0)
        let head = try await host.server.callTool("file_head_preview", ["path": "Sources/Binary.dat"])
        #expect(!head.isToolError, "\(head.resultText)")
        #expect(head.structured?["encoding"]?.string == "iso-latin-1" && head.structured?["totalLines"]?.int == 1)
    }

    @Test func treeViewDepthClampAndSymlinkLeaf() async throws {
        let sample = try TempSample()
        defer { sample.remove() }
        let host = try await opened(sample)
        let tree = try await host.server.callTool("tree_view")
        #expect(!tree.isToolError, "\(tree.resultText)")
        let text = tree.structured?["tree"]?.string ?? ""
        #expect(text.hasPrefix("📂 Greeter\n"))
        #expect(text.contains("📄 Greeter.swift") && text.contains("📂 Sources"))
        #expect(tree.structured?["entries"]?.int == 13 && tree.structured?["truncated"]?.bool == false)
        #expect(tree.structured?["path"] == sample.url.standardizedFileURL.path)

        let shallow = try await host.server.callTool("tree_view", ["maxDepth": 1])
        let shallowText = shallow.structured?["tree"]?.string ?? ""
        #expect(shallowText.contains("📄 GreetingView.swift"))
        #expect(!shallowText.contains("Greeter.swift") && !shallowText.contains("main.swift"))
        #expect(shallow.structured?["entries"]?.int == 10)

        let wide = try await host.server.callTool("tree_view", ["maxDepth": 99])
        let ten = try await host.server.callTool("tree_view", ["maxDepth": 10])
        #expect(wide.structured?["tree"] == ten.structured?["tree"])
        #expect(wide.structured?["entries"]?.int == 13)

        let zero = try await host.server.callTool("tree_view", ["maxDepth": 0])
        #expect(zero.isToolError && zero.resultText.contains("Invalid maxDepth: must be an integer >= 1 (got '0')."))
        let fractional = try await host.server.callTool("tree_view", ["maxDepth": .double(2.5)])
        #expect(fractional.isToolError && fractional.resultText.contains("must be of type integer"))
        let whole = try await host.server.callTool("tree_view", ["maxDepth": .double(2.0)])
        #expect(!whole.isToolError && whole.structured?["entries"]?.int == 13)

        let missing = try await host.server.callTool("tree_view", ["path": "Nope"])
        #expect(!missing.isToolError && missing.resultText.contains("Project Tree generated"))
        #expect((missing.structured?["tree"]?.string ?? "").contains("⚠️ Error reading directory"))
    }

    @Test func treeViewSymlinksAreLeaves() async throws {
        let sample = try TempSample()
        defer { sample.remove() }
        let host = try await opened(sample)
        try FileManager.default.createSymbolicLink(atPath: sample.path("Sources/Greeter/Link.swift"), withDestinationPath: "Greeter.swift")
        try FileManager.default.createSymbolicLink(atPath: sample.path("Sources/LinkDir"), withDestinationPath: "Greeter")
        let tree = try await host.server.callTool("tree_view")
        #expect(!tree.isToolError, "\(tree.resultText)")
        let text = tree.structured?["tree"]?.string ?? ""
        #expect(text.contains("🔗 Link.swift") && text.contains("🔗 LinkDir"))
        #expect(text.components(separatedBy: "📄 Greeter.swift").count - 1 == 1)
        #expect(tree.structured?["entries"]?.int == 15 && tree.structured?["truncated"]?.bool == false)
    }

    @Test func missingRequiredArgumentsAreRejected() async throws {
        let sample = try TempSample()
        defer { sample.remove() }
        let host = try await opened(sample)
        for id in ["dir_read", "dir_cd", "file_metadata", "file_head_preview", "count_file_lines"] {
            let r = try await host.server.callTool(id, [:])
            #expect(r.isToolError && r.resultText.contains("missing the required argument"), "\(id): \(r.resultText)")
        }
    }
}

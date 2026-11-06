import Foundation
import Testing
import YcodeAssistant
import YcodeIDECore
@testable import YcodeMCP

/// The ported Legacy core file-reading tools against
/// `Samples/AgentSamples/Greeter` (a copy). Fixture facts used below:
/// `Sources/Greeter/Greeter.swift` is 374 bytes with 14 lines plus a
/// trailing newline (15 newline-separated components: 9 code, 3 comment,
/// 3 blank); `Sources/greet/main.swift` is 115 bytes (5 components: 3
/// code, 0 comment, 2 blank). The root's five children total 2047 bytes.
@MainActor
@Suite(.serialized) struct YcodeFileReadingTests {
    func opened(_ sample: TempSample) async throws -> YcodeMCPHost {
        let host = YcodeMCPHost()
        let r = try await host.server.callTool("workspace_open", ["path": .string(sample.url.path)])
        #expect(!r.isToolError, "\(r.resultText)")
        return host
    }

    /// Sums every regular file under `url` (hidden files skipped), the
    /// independent check for `dir_size_report`'s total.
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
        let host = YcodeMCPHost()
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
            // The first input property is the optional `workspace` param,
            // as on every other Ycode tool.
            #expect(tool.inputSchema["properties"]?["workspace"] != nil, "\(tool.name) is missing the workspace parameter")
            let required = tool.inputSchema["required"]?.array?.compactMap(\.string) ?? []
            #expect(required == expectedRequired[tool.name], "\(tool.name) required: \(required)")
            let outputKeys = tool.outputSchema?["properties"]?.object?.keys.sorted() ?? []
            #expect(outputKeys == expectedOutputs[tool.name], "\(tool.name) output keys: \(outputKeys)")
        }
        // The host actually serves them (needs `fileReadingTools` wired
        // into `installTools`).
        let served = host.server.tools.map(\.name)
        for id in expectedTitles.keys { #expect(served.contains(id), "\(id) is not installed on the server") }
    }

    @Test func dirReadListsSortedEntriesWithMarkers() async throws {
        let sample = try TempSample()
        defer { sample.remove() }
        let host = try await opened(sample)
        // An empty path is rejected by the handler as a missing argument.
        let empty = try await host.server.callTool("dir_read", ["path": ""])
        #expect(empty.isToolError && empty.resultText.contains("missing the required argument \"path\""))
        let read = try await host.server.callTool("dir_read", ["path": "."])
        #expect(!read.isToolError, "\(read.resultText)")
        #expect(read.structured?["contents"] == "Package.swift\nPreviews/\nSources/\nStrings/\nTests/")
        #expect(read.structured?["count"] == 5)
        #expect(read.structured?["path"] == sample.url.standardizedFileURL.path)
        #expect(read.resultText.hasPrefix("Successfully read directory: . (5 entries)"))

        let sub = try await host.server.callTool("dir_read", ["path": "Sources/Greeter"])
        #expect(sub.structured?["contents"] == "Greeter.swift" && sub.structured?["count"] == 1)

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
        #expect(cd.structured?["contents"] == "Greeter\ngreet" && cd.structured?["count"] == 2)
        #expect(cd.resultText.hasPrefix("Working directory changed to \(root)/Sources"))

        let pwd = try await host.server.callTool("dir_pwd")
        #expect(pwd.structured?["path"] == root + "/Sources")

        // Plain relative paths now resolve against the new directory.
        let read = try await host.server.callTool("dir_read", ["path": "."])
        #expect(read.structured?["contents"] == "Greeter/\ngreet/")

        // "." is a no-op; ".." moves to the parent.
        let noop = try await host.server.callTool("dir_cd", ["path": "."])
        #expect(noop.structured?["path"] == root + "/Sources")
        let up = try await host.server.callTool("dir_cd", ["path": ".."])
        #expect(up.structured?["path"] == root && up.structured?["previousPath"] == root + "/Sources")

        // A leading "/" is workspace-root-relative.
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

        // ".." past the workspace root is an error, not a clamp.
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
        #expect(report.structured?["entryCount"] == 5)
        #expect(report.structured?["totalBytes"] == totalBytes(under: sample.url))
        #expect(report.resultText.hasPrefix("Directory sizes under .:"))
        #expect(report.resultText.contains("- Package.swift — 537 bytes (0.00 MB)"))
        // Largest first: Package.swift (537) before Sources/ (489).
        let lines = text.components(separatedBy: "\n")
        let packageLine = try #require(lines.firstIndex { $0.hasPrefix("- Package.swift") })
        let sourcesLine = try #require(lines.firstIndex { $0.hasPrefix("- Sources/") })
        #expect(packageLine < sourcesLine)

        let limited = try await host.server.callTool("dir_size_report", ["limit": 1])
        let rows = limited.resultText.components(separatedBy: "\n").filter { $0.hasPrefix("- ") }
        #expect(rows.count == 1 && limited.structured?["entryCount"] == 5 && limited.structured?["totalBytes"] == 2047)

        let sub = try await host.server.callTool("dir_size_report", ["path": "Sources"])
        #expect(sub.structured?["entryCount"] == 2 && sub.structured?["totalBytes"] == 489)
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
        #expect(meta.structured?["path"] == "Sources/Greeter/Greeter.swift")
        #expect(meta.structured?["fileName"] == "Greeter.swift" && meta.structured?["extension"] == "swift")
        #expect(meta.structured?["isDirectory"] == false && meta.structured?["fileType"] == "regular")
        #expect(meta.structured?["size"] == 374)
        #expect(meta.structured?["permissions"] == meta.structured?["permissionsOctal"])
        let permissions = meta.structured?["permissions"]?.string ?? ""
        #expect(!permissions.isEmpty && permissions.allSatisfy { "01234567".contains($0) })
        #expect(!(meta.structured?["creationDate"]?.string ?? "").isEmpty)
        #expect(!(meta.structured?["modificationDate"]?.string ?? "").isEmpty)
        #expect(meta.resultText.contains("Metadata for Sources/Greeter/Greeter.swift:"))
        #expect(meta.resultText.contains("- Size: 374 bytes"))

        let dir = try await host.server.callTool("file_metadata", ["path": "Sources"])
        #expect(dir.structured?["isDirectory"] == true && dir.structured?["fileType"] == "directory")
        #expect(dir.structured?["path"] == "Sources" && dir.structured?["extension"] == "")

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
        #expect(head.structured?["path"] == "Sources/Greeter/Greeter.swift")
        #expect(head.structured?["encoding"] == "utf-8")
        // No phantom trailing line is stripped, so the 14-line file
        // counts 15 lines here (unlike file_read's 14).
        #expect(head.structured?["totalLines"] == 15 && head.structured?["shownLines"] == 15)
        #expect(head.structured?["truncated"] == false)
        #expect(head.resultText.hasPrefix("Preview of Sources/Greeter/Greeter.swift [utf-8, 15 total lines]:\n1: /// Makes greetings."))

        let three = try await host.server.callTool("file_head_preview", ["path": "Sources/Greeter/Greeter.swift", "lines": 3])
        #expect(three.structured?["shownLines"] == 3 && three.structured?["truncated"] == true)
        #expect(three.resultText.contains("… [truncated: showing 3 of 15 lines]"))

        // `lines` clamps to 100; the file still shows only its 15 lines.
        let clamped = try await host.server.callTool("file_head_preview", ["path": "Sources/Greeter/Greeter.swift", "lines": 200])
        #expect(clamped.structured?["shownLines"] == 15 && clamped.structured?["truncated"] == false)

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
        #expect(file.structured?["path"] == "Sources/Greeter/Greeter.swift")
        #expect(file.structured?["fileCount"] == 1 && file.structured?["totalLines"] == 15)
        #expect(file.structured?["codeLines"] == 9 && file.structured?["commentLines"] == 3 && file.structured?["blankLines"] == 3)
        #expect(file.structured?["totalBytes"] == 374)
        #expect(file.resultText.hasPrefix("Code Metrics for Sources/Greeter/Greeter.swift (1 file(s)):"))

        let dir = try await host.server.callTool("count_file_lines", ["path": "Sources", "extension": "swift"])
        #expect(dir.structured?["fileCount"] == 2 && dir.structured?["totalLines"] == 20)
        #expect(dir.structured?["codeLines"] == 12 && dir.structured?["commentLines"] == 3 && dir.structured?["blankLines"] == 5)
        #expect(dir.structured?["totalBytes"] == 489)

        // The `targetPath` alias works, and a single file ignores the
        // extension filter.
        let alias = try await host.server.callTool("count_file_lines", ["targetPath": "Sources/Greeter/Greeter.swift", "extension": "md"])
        #expect(alias.structured?["fileCount"] == 1 && alias.structured?["totalLines"] == 15)

        let missing = try await host.server.callTool("count_file_lines", ["path": "Nope"])
        #expect(missing.isToolError && missing.resultText.contains("Path not found: Nope"))
        let outside = try await host.server.callTool("count_file_lines", ["path": "../../etc/hosts"])
        #expect(outside.isToolError && outside.resultText.contains("outside the workspace"))
    }

    @Test func binaryFileHandling() async throws {
        let sample = try TempSample()
        defer { sample.remove() }
        let host = try await opened(sample)
        // Invalid UTF-8, an odd byte count and a lone surrogate: UTF-8
        // and UTF-16 both refuse it, so only ISO Latin-1 decodes it.
        let binary = Data([0x00, 0xD8, 0xFF])
        try binary.write(to: URL(fileURLWithPath: sample.path("Sources/Binary.dat")))
        // count_file_lines silently skips non-UTF-8 files from the
        // counts, but still counts the file.
        let counted = try await host.server.callTool("count_file_lines", ["path": "Sources/Binary.dat"])
        #expect(!counted.isToolError, "\(counted.resultText)")
        #expect(counted.structured?["fileCount"] == 1 && counted.structured?["totalLines"] == 0)
        #expect(counted.structured?["totalBytes"] == 0)
        // file_head_preview falls through to ISO Latin-1 instead of
        // failing on the binary content.
        let head = try await host.server.callTool("file_head_preview", ["path": "Sources/Binary.dat"])
        #expect(!head.isToolError, "\(head.resultText)")
        #expect(head.structured?["encoding"] == "iso-latin-1" && head.structured?["totalLines"] == 1)
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
        #expect(tree.structured?["entries"] == 13 && tree.structured?["truncated"] == false)
        #expect(tree.structured?["path"] == sample.url.standardizedFileURL.path)

        // maxDepth 1 still lists files directly inside a depth-1
        // directory, but not anything deeper.
        let shallow = try await host.server.callTool("tree_view", ["maxDepth": 1])
        let shallowText = shallow.structured?["tree"]?.string ?? ""
        #expect(shallowText.contains("📄 GreetingView.swift"))
        #expect(!shallowText.contains("Greeter.swift") && !shallowText.contains("main.swift"))
        #expect(shallow.structured?["entries"] == 10)

        // maxDepth clamps to 10: 99 renders exactly like 10.
        let wide = try await host.server.callTool("tree_view", ["maxDepth": 99])
        let ten = try await host.server.callTool("tree_view", ["maxDepth": 10])
        #expect(wide.structured?["tree"] == ten.structured?["tree"])
        #expect(wide.structured?["entries"] == 13)

        let zero = try await host.server.callTool("tree_view", ["maxDepth": 0])
        #expect(zero.isToolError && zero.resultText.contains("Invalid maxDepth: must be an integer >= 1 (got '0')."))
        // A fractional depth never reaches the handler: the server's
        // argument check rejects it as the wrong type first.
        let fractional = try await host.server.callTool("tree_view", ["maxDepth": .double(2.5)])
        #expect(fractional.isToolError && fractional.resultText.contains("must be of type integer"))
        // A whole double is an integer as far as the schema is concerned.
        let whole = try await host.server.callTool("tree_view", ["maxDepth": .double(2.0)])
        #expect(!whole.isToolError && whole.structured?["entries"] == 13)

        let missing = try await host.server.callTool("tree_view", ["path": "Nope"])
        // A missing root still succeeds, with Legacy's warning line.
        #expect(!missing.isToolError && missing.resultText.contains("Project Tree generated"))
        #expect((missing.structured?["tree"]?.string ?? "").contains("⚠️ Error reading directory"))
    }

    @Test func treeViewSymlinksAreLeaves() async throws {
        let sample = try TempSample()
        defer { sample.remove() }
        let host = try await opened(sample)
        try FileManager.default.createSymbolicLink(atPath: sample.path("Sources/Greeter/Link.swift"), withDestinationPath: "Greeter.swift")
        // A symlink to a directory (and a would-be cycle) is a leaf too.
        try FileManager.default.createSymbolicLink(atPath: sample.path("Sources/LinkDir"), withDestinationPath: "Greeter")
        let tree = try await host.server.callTool("tree_view")
        #expect(!tree.isToolError, "\(tree.resultText)")
        let text = tree.structured?["tree"]?.string ?? ""
        #expect(text.contains("🔗 Link.swift") && text.contains("🔗 LinkDir"))
        // The directory symlink is never followed: Greeter.swift is
        // listed exactly once, under its real directory.
        #expect(text.components(separatedBy: "📄 Greeter.swift").count - 1 == 1)
        #expect(tree.structured?["entries"] == 15 && tree.structured?["truncated"] == false)
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

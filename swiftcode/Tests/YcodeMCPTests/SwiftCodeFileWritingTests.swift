import Foundation
import Testing
import YcodeAssistant
@testable import YcodeMCP

@MainActor
@Suite(.serialized) struct SwiftCodeFileWritingTests {
    static let wave2IDs = ["batch_rename_files", "code_format", "code_generate", "code_insert", "code_multi_edit",
                           "code_refactor", "code_replace", "csv_to_json", "dir_create", "dir_delete", "file_append",
                           "file_copy", "file_create", "file_delete", "file_move", "file_rename", "file_write",
                           "format_json_file", "generate_file_checksum", "json_to_csv", "json_to_plist", "plist_edit",
                           "plist_to_json", "regex_replace_in_files"]

    func opened(_ sample: TempSample, policy: MCPWritePolicy = .readOnly, withArtifacts: Bool = false) async throws -> SwiftCodeMCPHost {
        let host = SwiftCodeMCPHost()
        host.server.writePolicy = policy
        let ported = Set(host.fileWritingTools.map(\.name))
        host.server.tools = host.server.tools.filter { !ported.contains($0.name) } + host.fileWritingTools
        if withArtifacts { host.server.tools += host.artifactTools }
        let r = try await host.server.callTool("workspace_open", ["path": .string(sample.url.path)])
        #expect(!r.isToolError, "\(r.resultText)")
        return host
    }

    final class Reviews: @unchecked Sendable {
        var changes: [MCPChange] = []
        var accept = false
    }

    func writeFixture(_ sample: TempSample, _ rel: String, _ content: String) throws {
        let url = URL(fileURLWithPath: sample.path(rel))
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try content.write(to: url, atomically: true, encoding: .utf8)
    }

    func exists(_ sample: TempSample, _ rel: String) -> Bool {
        FileManager.default.fileExists(atPath: sample.path(rel))
    }

    func fileData(_ sample: TempSample, _ rel: String) -> Data? {
        try? Data(contentsOf: URL(fileURLWithPath: sample.path(rel)))
    }

    func jsonObject(_ sample: TempSample, _ rel: String) -> Any? {
        guard let d = fileData(sample, rel) else { return nil }
        return try? JSONSerialization.jsonObject(with: d)
    }

    @Test func toolsAreListedWithLegacySchemas() async throws {
        let host = SwiftCodeMCPHost()
        let tools = host.fileWritingTools
        #expect(tools.count == 23, "expected 23 Wave 2 tools in fileWritingTools, got \(tools.map(\.name))")
        #expect(tools.map(\.name).sorted() == Self.wave2IDs.filter { $0 != "file_write" }.sorted())
        let expectedRequired: [String: [String]] = [
            "batch_rename_files": ["directory", "search", "replacement"], "code_format": [], "code_generate": ["path", "template"],
            "code_insert": ["path", "code"], "code_multi_edit": ["edits"], "code_refactor": ["path", "action"],
            "code_replace": ["path", "target", "replacement"], "csv_to_json": ["path"], "dir_create": ["path"],
            "dir_delete": ["path"], "file_append": ["path", "content"], "file_copy": ["source", "destination"],
            "file_create": ["path"], "file_delete": ["path"], "file_move": ["source", "destination"],
            "file_rename": ["oldPath", "newName"], "format_json_file": ["path"],
            "generate_file_checksum": ["path"], "json_to_csv": ["path"], "json_to_plist": ["path"],
            "plist_edit": ["path", "key"], "plist_to_json": ["path"], "regex_replace_in_files": ["pattern", "replacement"],
        ]
        for tool in tools {
            let required = tool.inputSchema["required"]?.array?.compactMap(\.string) ?? []
            #expect(required == expectedRequired[tool.name], "\(tool.name) required: \(required)")
            #expect(tool.inputSchema["properties"]?["workspace"] != nil, "\(tool.name) is missing the workspace parameter")
            if tool.name == "generate_file_checksum" {
                #expect(tool.annotations.readOnly && !tool.writes, "generate_file_checksum must be read-only")
            } else {
                #expect(!tool.annotations.readOnly && tool.writes, "\(tool.name) must be a write tool")
            }
            if tool.name == "file_delete" || tool.name == "dir_delete" {
                #expect(tool.annotations.destructive, "\(tool.name) must be marked destructive")
            } else {
                #expect(!tool.annotations.destructive, "\(tool.name) must not be marked destructive")
            }
        }
        let sample = try TempSample()
        defer { sample.remove() }
        let servedHost = try await opened(sample)
        let served = servedHost.server.tools.map(\.name)
        for id in Self.wave2IDs { #expect(served.contains(id), "\(id) is not installed on the server") }
        #expect(served.filter { $0 == "file_write" }.count == 1)
        let servedFileWrite = servedHost.server.tools.first { $0.name == "file_write" }
        #expect(servedFileWrite?.inputSchema["required"]?.array?.compactMap(\.string) == ["path", "content"])
    }

    @Test func fileWriteCreatesOverwritesAndCreatesParents() async throws {
        let sample = try TempSample()
        defer { sample.remove() }
        let host = try await opened(sample, policy: .allow)
        let created = try await host.server.callTool("file_write", ["path": .string("WritingTests/hello.txt"),
                                                                    "content": .string("Hello\nWorld\n")])
        #expect(!created.isToolError, "\(created.resultText)")
        #expect(created.firstText == "Created new file: WritingTests/hello.txt (3 lines)")
        #expect(sample.read("WritingTests/hello.txt") == "Hello\nWorld\n")

        let updated = try await host.server.callTool("file_write", ["path": .string("WritingTests/hello.txt"),
                                                                    "content": .string("Hello again\n")])
        #expect(!updated.isToolError, "\(updated.resultText)")
        #expect(updated.firstText == "Updated existing file: WritingTests/hello.txt (2 lines)")
        #expect(sample.read("WritingTests/hello.txt") == "Hello again\n")

        let deep = try await host.server.callTool("file_write", ["path": .string("WritingTests/Deep/Nested/file.txt"),
                                                                 "content": .string("deep\n")])
        #expect(!deep.isToolError, "\(deep.resultText)")
        #expect(sample.read("WritingTests/Deep/Nested/file.txt") == "deep\n")
    }

    @Test func fileCreateRefusesExistingWithoutOverwrite() async throws {
        let sample = try TempSample()
        defer { sample.remove() }
        let host = try await opened(sample, policy: .allow)
        let created = try await host.server.callTool("file_create", ["path": .string("WritingTests/New/Dir/created.txt"),
                                                                     "content": .string("A\nB\n")])
        #expect(!created.isToolError, "\(created.resultText)")
        #expect(created.firstText == "Created file at WritingTests/New/Dir/created.txt (3 lines)")
        #expect(sample.read("WritingTests/New/Dir/created.txt") == "A\nB\n")

        let again = try await host.server.callTool("file_create", ["path": .string("WritingTests/New/Dir/created.txt"),
                                                                   "content": .string("Other\n")])
        #expect(again.isToolError && again.firstText == "File already exists at WritingTests/New/Dir/created.txt. Set overwrite=true to replace it.")
        #expect(sample.read("WritingTests/New/Dir/created.txt") == "A\nB\n")

        let replaced = try await host.server.callTool("file_create", ["path": .string("WritingTests/New/Dir/created.txt"),
                                                                      "content": .string("Replaced\n"), "overwrite": .bool(true)])
        #expect(!replaced.isToolError, "\(replaced.resultText)")
        #expect(sample.read("WritingTests/New/Dir/created.txt") == "Replaced\n")

        let empty = try await host.server.callTool("file_create", ["path": .string("WritingTests/empty.txt")])
        #expect(!empty.isToolError, "\(empty.resultText)")
        #expect(exists(sample, "WritingTests/empty.txt") && sample.read("WritingTests/empty.txt") == "")
    }

    @Test func fileAppendAppendsAndFailsWhenMissing() async throws {
        let sample = try TempSample()
        defer { sample.remove() }
        try writeFixture(sample, "WritingTests/log.txt", "one\n")
        let host = try await opened(sample, policy: .allow)
        let appended = try await host.server.callTool("file_append", ["path": .string("WritingTests/log.txt"),
                                                                      "content": .string("two\n")])
        #expect(!appended.isToolError, "\(appended.resultText)")
        #expect(appended.firstText == "Successfully appended to file: WritingTests/log.txt")
        #expect(sample.read("WritingTests/log.txt") == "one\ntwo\n")

        let missing = try await host.server.callTool("file_append", ["path": .string("WritingTests/ghost.txt"),
                                                                     "content": .string("boo\n")])
        #expect(missing.isToolError && missing.resultText.contains("Failed to append to file at WritingTests/ghost.txt"))
        #expect(!exists(sample, "WritingTests/ghost.txt"))
    }

    @Test func fileDeleteAndDirDelete() async throws {
        let sample = try TempSample()
        defer { sample.remove() }
        try writeFixture(sample, "WritingTests/doomed.txt", "bye\n")
        try writeFixture(sample, "WritingTests/Dir/inner.txt", "inside\n")
        try writeFixture(sample, "WritingTests/Dir/Sub/nested.txt", "nested\n")
        let host = try await opened(sample, policy: .allow)

        let deleted = try await host.server.callTool("file_delete", ["path": .string("WritingTests/doomed.txt")])
        #expect(!deleted.isToolError, "\(deleted.resultText)")
        #expect(deleted.firstText == "Successfully deleted file: WritingTests/doomed.txt")
        #expect(!exists(sample, "WritingTests/doomed.txt"))

        let missing = try await host.server.callTool("file_delete", ["path": .string("WritingTests/doomed.txt")])
        #expect(missing.isToolError && missing.firstText == "No file at WritingTests/doomed.txt — nothing to delete.")

        let dirDeleted = try await host.server.callTool("dir_delete", ["path": .string("WritingTests/Dir")])
        #expect(!dirDeleted.isToolError, "\(dirDeleted.resultText)")
        #expect(dirDeleted.firstText == "Successfully deleted directory: WritingTests/Dir")
        #expect(!exists(sample, "WritingTests/Dir"))

        let dirMissing = try await host.server.callTool("dir_delete", ["path": .string("WritingTests/Dir")])
        #expect(dirMissing.isToolError && dirMissing.firstText == "No directory at WritingTests/Dir — nothing to delete.")
    }

    @Test func dirCreateNestedIsIdempotent() async throws {
        let sample = try TempSample()
        defer { sample.remove() }
        let host = try await opened(sample, policy: .allow)
        let created = try await host.server.callTool("dir_create", ["path": .string("WritingTests/A/B/C")])
        #expect(!created.isToolError, "\(created.resultText)")
        #expect(created.firstText == "Successfully created directory: WritingTests/A/B/C")
        var isDir: ObjCBool = false
        #expect(FileManager.default.fileExists(atPath: sample.path("WritingTests/A/B/C"), isDirectory: &isDir) && isDir.boolValue)
        let again = try await host.server.callTool("dir_create", ["path": .string("WritingTests/A/B/C")])
        #expect(!again.isToolError, "\(again.resultText)")
    }

    @Test func reviewRejectsFileWriteAndFileDelete() async throws {
        let sample = try TempSample()
        defer { sample.remove() }
        let reviews = Reviews()
        let host = try await opened(sample, policy: .review { c in reviews.changes.append(c); return reviews.accept })

        let rejected = try await host.server.callTool("file_write", ["path": .string("WritingTests/reviewed.txt"),
                                                                     "content": .string("Hello review.\n")])
        #expect(rejected.isToolError && rejected.firstText == MCPServer.rejectedMessage)
        #expect(!exists(sample, "WritingTests/reviewed.txt"))
        let change = try #require(reviews.changes.first)
        #expect(change.tool == "file_write" && change.relativePath == "WritingTests/reviewed.txt"
                && change.original == nil && change.proposed == "Hello review.\n")

        reviews.accept = true
        let created = try await host.server.callTool("file_write", ["path": .string("WritingTests/reviewed.txt"),
                                                                    "content": .string("Hello review.\n")])
        #expect(!created.isToolError, "\(created.resultText)")
        #expect(sample.read("WritingTests/reviewed.txt") == "Hello review.\n")

        reviews.accept = false
        let deleteRejected = try await host.server.callTool("file_delete", ["path": .string("WritingTests/reviewed.txt")])
        #expect(deleteRejected.isToolError && deleteRejected.firstText == MCPServer.rejectedMessage)
        #expect(exists(sample, "WritingTests/reviewed.txt"))
        #expect(reviews.changes.last?.tool == "file_delete")
    }

    @Test func readOnlyPolicyRefusesWrites() async throws {
        let sample = try TempSample()
        defer { sample.remove() }
        try writeFixture(sample, "WritingTests/keep.txt", "keep\n")
        let host = try await opened(sample)
        let written = try await host.server.callTool("file_write", ["path": .string("WritingTests/nope.txt"),
                                                                    "content": .string("x\n")])
        #expect(written.isToolError && written.resultText.contains("read-only"))
        #expect(!exists(sample, "WritingTests/nope.txt"))
        let created = try await host.server.callTool("file_create", ["path": .string("WritingTests/nope2.txt"),
                                                                     "content": .string("x\n")])
        #expect(created.isToolError && created.resultText.contains("read-only"))
        #expect(!exists(sample, "WritingTests/nope2.txt"))
        let deleted = try await host.server.callTool("file_delete", ["path": .string("WritingTests/keep.txt")])
        #expect(deleted.isToolError && deleted.resultText.contains("read-only"))
        #expect(exists(sample, "WritingTests/keep.txt"))
        let dirDeleted = try await host.server.callTool("dir_delete", ["path": .string("WritingTests")])
        #expect(dirDeleted.isToolError && dirDeleted.resultText.contains("read-only"))
        #expect(exists(sample, "WritingTests/keep.txt"))
    }

    @Test func fileCopyFileMoveFileRename() async throws {
        let sample = try TempSample()
        defer { sample.remove() }
        try writeFixture(sample, "WritingTests/orig.txt", "original\n")
        try writeFixture(sample, "WritingTests/taken.txt", "taken\n")
        let host = try await opened(sample, policy: .allow)

        let copied = try await host.server.callTool("file_copy", ["source": .string("WritingTests/orig.txt"),
                                                                  "destination": .string("WritingTests/copy.txt")])
        #expect(!copied.isToolError, "\(copied.resultText)")
        #expect(copied.firstText == "Successfully copied file from WritingTests/orig.txt to WritingTests/copy.txt")
        #expect(sample.read("WritingTests/copy.txt") == "original\n")
        #expect(sample.read("WritingTests/orig.txt") == "original\n")

        let copyClash = try await host.server.callTool("file_copy", ["source": .string("WritingTests/orig.txt"),
                                                                     "destination": .string("WritingTests/taken.txt")])
        #expect(copyClash.isToolError && copyClash.resultText.contains("Destination already exists: WritingTests/taken.txt"))
        #expect(sample.read("WritingTests/taken.txt") == "taken\n")

        let moved = try await host.server.callTool("file_move", ["source": .string("WritingTests/copy.txt"),
                                                                 "destination": .string("WritingTests/moved.txt")])
        #expect(!moved.isToolError, "\(moved.resultText)")
        #expect(moved.firstText == "Successfully moved file from WritingTests/copy.txt to WritingTests/moved.txt")
        #expect(!exists(sample, "WritingTests/copy.txt") && sample.read("WritingTests/moved.txt") == "original\n")

        let moveClash = try await host.server.callTool("file_move", ["source": .string("WritingTests/moved.txt"),
                                                                     "destination": .string("WritingTests/taken.txt")])
        #expect(moveClash.isToolError && moveClash.resultText.contains("Destination already exists: WritingTests/taken.txt"))
        #expect(exists(sample, "WritingTests/moved.txt"))

        let renamed = try await host.server.callTool("file_rename", ["oldPath": .string("WritingTests/moved.txt"),
                                                                     "newName": .string("renamed.txt")])
        #expect(!renamed.isToolError, "\(renamed.resultText)")
        #expect(renamed.firstText == "Successfully renamed file to: renamed.txt")
        #expect(!exists(sample, "WritingTests/moved.txt") && sample.read("WritingTests/renamed.txt") == "original\n")

        let badName = try await host.server.callTool("file_rename", ["oldPath": .string("WritingTests/renamed.txt"),
                                                                     "newName": .string("../evil.txt")])
        #expect(badName.isToolError && badName.firstText == "Invalid newName '../evil.txt': must be a single file name, not a path.")
        #expect(exists(sample, "WritingTests/renamed.txt"))

        let noop = try await host.server.callTool("file_rename", ["oldPath": .string("WritingTests/renamed.txt"),
                                                                  "newName": .string("renamed.txt")])
        #expect(noop.isToolError && noop.firstText == "Rename is a no-op: newName matches the current file name.")
    }

    @Test func fileCopyToMissingParentFails() async throws {
        let sample = try TempSample()
        defer { sample.remove() }
        try writeFixture(sample, "WritingTests/orig.txt", "original\n")
        let host = try await opened(sample, policy: .allow)
        let copied = try await host.server.callTool("file_copy", ["source": .string("WritingTests/orig.txt"),
                                                                  "destination": .string("WritingTests/NoSuchDir/dest.txt")])
        #expect(copied.isToolError && copied.resultText.contains("Failed to copy file"))
        #expect(!exists(sample, "WritingTests/NoSuchDir/dest.txt"))
        let missingSource = try await host.server.callTool("file_copy", ["source": .string("WritingTests/ghost.txt"),
                                                                         "destination": .string("WritingTests/dest.txt")])
        #expect(missingSource.isToolError && missingSource.resultText.contains("Failed to copy file"))
    }

    @Test func escapePathsAreRefused() async throws {
        let sample = try TempSample()
        defer { sample.remove() }
        let host = try await opened(sample, policy: .allow)
        let escaped = try await host.server.callTool("file_write", ["path": .string("../escape.txt"),
                                                                    "content": .string("escaped\n")])
        #expect(escaped.isToolError)
        #expect(escaped.resultText.contains("outside the workspace") || escaped.resultText.contains("traversal"))
        #expect(!FileManager.default.fileExists(atPath: sample.root.appendingPathComponent("escape.txt").path))

        let deleteEscape = try await host.server.callTool("file_delete", ["path": .string("../Package.swift")])
        #expect(deleteEscape.isToolError)
        #expect(deleteEscape.resultText.contains("outside the workspace") || deleteEscape.resultText.contains("traversal"))
        #expect(exists(sample, "Package.swift"))
    }

    @Test func codeReplaceExactNotFoundAndMultiple() async throws {
        let sample = try TempSample()
        defer { sample.remove() }
        try writeFixture(sample, "WritingTests/replace.swift", "let x = 1\nlet y = 1\nlet z = 2\n")
        let host = try await opened(sample, policy: .allow)

        let replaced = try await host.server.callTool("code_replace", ["path": .string("WritingTests/replace.swift"),
                                                                       "target": .string("let z = 2"), "replacement": .string("let z = 3")])
        #expect(!replaced.isToolError, "\(replaced.resultText)")
        #expect(replaced.resultText.hasPrefix("Successfully updated WritingTests/replace.swift with targeted replacement."))
        #expect(sample.read("WritingTests/replace.swift") == "let x = 1\nlet y = 1\nlet z = 3\n")

        let missing = try await host.server.callTool("code_replace", ["path": .string("WritingTests/replace.swift"),
                                                                      "target": .string("let q = 9"), "replacement": .string("let q = 0")])
        #expect(missing.isToolError
                && missing.firstText == "Target snippet not found in 'WritingTests/replace.swift'. Please re-read the file with 'file_read' to inspect the exact existing lines before attempting replacement. Target snippet was: 'let q = 9'")
        #expect(sample.read("WritingTests/replace.swift") == "let x = 1\nlet y = 1\nlet z = 3\n")

        let ambiguous = try await host.server.callTool("code_replace", ["path": .string("WritingTests/replace.swift"),
                                                                        "target": .string("1"), "replacement": .string("9")])
        #expect(ambiguous.isToolError
                && ambiguous.firstText == "Target snippet matched 2 times in 'WritingTests/replace.swift'. Provide more surrounding lines to uniquely identify the location, or pass 'allowMultiple: true'. Snippet was: '1'")
        #expect(sample.read("WritingTests/replace.swift") == "let x = 1\nlet y = 1\nlet z = 3\n")

        let multi = try await host.server.callTool("code_replace", ["path": .string("WritingTests/replace.swift"),
                                                                    "target": .string("1"), "replacement": .string("9"),
                                                                    "allowMultiple": .bool(true)])
        #expect(!multi.isToolError, "\(multi.resultText)")
        #expect(sample.read("WritingTests/replace.swift") == "let x = 9\nlet y = 9\nlet z = 3\n")
    }

    @Test func codeInsertLineBeforeAfter() async throws {
        let sample = try TempSample()
        defer { sample.remove() }
        try writeFixture(sample, "WritingTests/insert.swift", "alpha\nbeta\ngamma")
        let host = try await opened(sample, policy: .allow)

        let byLine = try await host.server.callTool("code_insert", ["path": .string("WritingTests/insert.swift"),
                                                                    "code": .string("INSERTED"), "mode": .string("line"),
                                                                    "line": .int(2)])
        #expect(!byLine.isToolError, "\(byLine.resultText)")
        #expect(byLine.firstText == "Code block inserted into WritingTests/insert.swift")
        #expect(sample.read("WritingTests/insert.swift") == "alpha\nINSERTED\nbeta\ngamma")

        let after = try await host.server.callTool("code_insert", ["path": .string("WritingTests/insert.swift"),
                                                                   "code": .string("AFTER"), "mode": .string("after"),
                                                                   "pattern": .string("beta")])
        #expect(!after.isToolError, "\(after.resultText)")
        #expect(sample.read("WritingTests/insert.swift") == "alpha\nINSERTED\nbeta\nAFTER\ngamma")

        let before = try await host.server.callTool("code_insert", ["path": .string("WritingTests/insert.swift"),
                                                                    "code": .string("BEFORE"), "mode": .string("before"),
                                                                    "pattern": .string("gamma")])
        #expect(!before.isToolError, "\(before.resultText)")
        #expect(sample.read("WritingTests/insert.swift") == "alpha\nINSERTED\nbeta\nAFTER\nBEFORE\ngamma")

        let miss = try await host.server.callTool("code_insert", ["path": .string("WritingTests/insert.swift"),
                                                                  "code": .string("NOPE"), "mode": .string("after"),
                                                                  "pattern": .string("missing-pattern")])
        #expect(miss.isToolError && miss.firstText == "Pattern not found in WritingTests/insert.swift: 'missing-pattern'. No changes made.")
        #expect(sample.read("WritingTests/insert.swift") == "alpha\nINSERTED\nbeta\nAFTER\nBEFORE\ngamma")

        let badMode = try await host.server.callTool("code_insert", ["path": .string("WritingTests/insert.swift"),
                                                                     "code": .string("NOPE"), "mode": .string("sideways")])
        #expect(badMode.isToolError && badMode.firstText == "Unknown mode 'sideways': expected 'line', 'before', or 'after'.")
    }

    @Test func codeMultiEditAcrossFiles() async throws {
        let sample = try TempSample()
        defer { sample.remove() }
        try writeFixture(sample, "WritingTests/multi-a.txt", "aaa\n")
        try writeFixture(sample, "WritingTests/multi-b.txt", "old value\n")
        let host = try await opened(sample, policy: .allow)

        let edited = try await host.server.callTool("code_multi_edit", ["edits": .array([
            .object(["path": .string("WritingTests/multi-a.txt"), "content": .string("whole new\n")]),
            .object(["path": .string("WritingTests/multi-b.txt"), "search": .string("old"), "replace": .string("new")]),
        ])])
        #expect(!edited.isToolError, "\(edited.resultText)")
        #expect(edited.firstText == "Multi-file edit completed for 2 files")
        #expect(sample.read("WritingTests/multi-a.txt") == "whole new\n")
        #expect(sample.read("WritingTests/multi-b.txt") == "new value\n")

        let partial = try await host.server.callTool("code_multi_edit", ["edits": .array([
            .object(["path": .string("WritingTests/multi-a.txt"), "content": .string("v2\n")]),
            .object(["path": .string("WritingTests/multi-b.txt"), "search": .string("not-there"), "replace": .string("x")]),
        ])])
        #expect(partial.isToolError
                && partial.firstText == "Search text not found in WritingTests/multi-b.txt. Edits already applied: WritingTests/multi-a.txt.")
        #expect(sample.read("WritingTests/multi-a.txt") == "v2\n")
        #expect(sample.read("WritingTests/multi-b.txt") == "new value\n")
    }

    @Test func generateFileChecksum() async throws {
        let sample = try TempSample()
        defer { sample.remove() }
        try writeFixture(sample, "WritingTests/abc.txt", "abc")
        let host = try await opened(sample)
        let sums = try await host.server.callTool("generate_file_checksum", ["path": .string("WritingTests/abc.txt")])
        #expect(!sums.isToolError, "\(sums.resultText)")
        #expect(sums.structured?["sha256"]?.string == "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
        #expect(sums.structured?["sha512"]?.string == "ddaf35a193617abacc417349ae20413112e6fa4e89a97ea20a9eeee64b55d39a2192992a274fc1a836ba3c23a3feebbd454d4423643ce80e2a9ac94fa54ca49f")
        #expect(sums.structured?["sha1"]?.string == "a9993e364706816aba3e25717850c26c9cd0d89d")
        #expect(sums.structured?["md5"]?.string == "900150983cd24fb0d6963f7d28e17f72")
        #expect(sums.structured?["size"]?.int == 3)
        #expect(sums.resultText.contains("- SHA-256: ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad"))

        let missing = try await host.server.callTool("generate_file_checksum", ["path": .string("WritingTests/ghost.txt")])
        #expect(missing.isToolError && missing.firstText == "File not found at: WritingTests/ghost.txt")
    }

    @Test func plistRoundTripAndEdit() async throws {
        let sample = try TempSample()
        defer { sample.remove() }
        let host = try await opened(sample, policy: .allow)
        let written = try await host.server.callTool("file_write", ["path": .string("WritingTests/app.json"),
                                                                    "content": .string("{\"enabled\":true,\"name\":\"Greeter\",\"version\":1}")])
        #expect(!written.isToolError, "\(written.resultText)")

        let toPlist = try await host.server.callTool("json_to_plist", ["path": .string("WritingTests/app.json"),
                                                                       "destination": .string("WritingTests/app.plist")])
        #expect(!toPlist.isToolError, "\(toPlist.resultText)")
        #expect(toPlist.resultText.contains("Successfully converted JSON `WritingTests/app.json` to Plist (xml) at `WritingTests/app.plist`"))
        #expect(exists(sample, "WritingTests/app.plist"))

        let back = try await host.server.callTool("plist_to_json", ["path": .string("WritingTests/app.plist"),
                                                                    "destination": .string("WritingTests/app-roundtrip.json")])
        #expect(!back.isToolError, "\(back.resultText)")
        #expect(back.resultText.contains("Successfully converted Plist `WritingTests/app.plist` to JSON at `WritingTests/app-roundtrip.json`"))
        let roundTripped = try #require(jsonObject(sample, "WritingTests/app-roundtrip.json") as? [String: Any])
        #expect(roundTripped["name"] as? String == "Greeter")
        #expect(roundTripped["version"] as? Int == 1)
        #expect(roundTripped["enabled"] as? Bool == true)

        let set = try await host.server.callTool("plist_edit", ["path": .string("WritingTests/app.plist"),
                                                                "action": .string("set"), "key": .string("name"),
                                                                "value": .string("Renamed")])
        #expect(!set.isToolError, "\(set.resultText)")
        #expect(set.firstText == "Set key 'name' in 'WritingTests/app.plist'.")
        let get = try await host.server.callTool("plist_edit", ["path": .string("WritingTests/app.plist"),
                                                                "action": .string("get"), "key": .string("name")])
        #expect(!get.isToolError, "\(get.resultText)")
        #expect(get.firstText == "Key 'name' = Renamed in 'WritingTests/app.plist'.")
        let back2 = try await host.server.callTool("plist_to_json", ["path": .string("WritingTests/app.plist"),
                                                                     "destination": .string("WritingTests/app-roundtrip2.json")])
        #expect(!back2.isToolError, "\(back2.resultText)")
        #expect((jsonObject(sample, "WritingTests/app-roundtrip2.json") as? [String: Any])?["name"] as? String == "Renamed")

        let missingKey = try await host.server.callTool("plist_edit", ["path": .string("WritingTests/app.plist"),
                                                                       "action": .string("get"), "key": .string("nope")])
        #expect(missingKey.isToolError && missingKey.firstText == "Key 'nope' not found in 'WritingTests/app.plist'.")
    }

    @Test func csvJsonRoundTrip() async throws {
        let sample = try TempSample()
        defer { sample.remove() }
        try writeFixture(sample, "WritingTests/people.csv", "name,age\nAda,36\nGrace,31\n")
        let host = try await opened(sample, policy: .allow)

        let toJson = try await host.server.callTool("csv_to_json", ["path": .string("WritingTests/people.csv")])
        #expect(!toJson.isToolError, "\(toJson.resultText)")
        #expect(toJson.firstText == "Successfully converted CSV `WritingTests/people.csv` to JSON at `WritingTests/people.json` (2 records parsed).")
        let records = try #require(jsonObject(sample, "WritingTests/people.json") as? [[String: Any]])
        #expect(records.count == 2)
        #expect(records[0]["name"] as? String == "Ada" && records[0]["age"] as? String == "36")
        #expect(records[1]["name"] as? String == "Grace" && records[1]["age"] as? String == "31")

        let toCsv = try await host.server.callTool("json_to_csv", ["path": .string("WritingTests/people.json"),
                                                                   "destination": .string("WritingTests/people-out.csv")])
        #expect(!toCsv.isToolError, "\(toCsv.resultText)")
        #expect(toCsv.firstText == "Successfully converted JSON `WritingTests/people.json` to CSV at `WritingTests/people-out.csv` (2 rows, 2 columns).")
        #expect(sample.read("WritingTests/people-out.csv") == "\"age\",\"name\"\n\"36\",\"Ada\"\n\"31\",\"Grace\"\n")

        try writeFixture(sample, "WritingTests/not-array.json", "{\"a\":1}")
        let notArray = try await host.server.callTool("json_to_csv", ["path": .string("WritingTests/not-array.json")])
        #expect(notArray.isToolError && notArray.firstText == "JSON root must be a non-empty array of objects to convert to CSV.")
    }

    @Test func regexReplaceAcrossFiles() async throws {
        let sample = try TempSample()
        defer { sample.remove() }
        try writeFixture(sample, "WritingTests/RegexA.swift", "let a = ZzReplaceMe\nlet b = ZzReplaceMe\n")
        try writeFixture(sample, "WritingTests/RegexB.swift", "let c = ZzReplaceMe\n")
        let host = try await opened(sample, policy: .allow)

        let dry = try await host.server.callTool("regex_replace_in_files", ["pattern": .string("ZzReplaceMe"),
                                                                             "replacement": .string("Done"),
                                                                             "fileExtension": .string("swift"),
                                                                             "dryRun": .bool(true)])
        #expect(!dry.isToolError, "\(dry.resultText)")
        #expect(dry.resultText.hasPrefix("[DRY RUN] Would modify 2 file(s) with 3 total replacements:"))
        #expect(sample.read("WritingTests/RegexA.swift").contains("ZzReplaceMe"))

        let replaced = try await host.server.callTool("regex_replace_in_files", ["pattern": .string("ZzReplaceMe"),
                                                                                 "replacement": .string("Done"),
                                                                                 "fileExtension": .string("swift")])
        #expect(!replaced.isToolError, "\(replaced.resultText)")
        #expect(replaced.resultText.hasPrefix("Successfully modified 2 file(s) with 3 total replacements:"))
        #expect(sample.read("WritingTests/RegexA.swift") == "let a = Done\nlet b = Done\n")
        #expect(sample.read("WritingTests/RegexB.swift") == "let c = Done\n")

        let badRegex = try await host.server.callTool("regex_replace_in_files", ["pattern": .string("["),
                                                                                "replacement": .string("x")])
        #expect(badRegex.isToolError && badRegex.firstText == "Invalid regular expression pattern: [")
    }

    @Test func formatJsonFile() async throws {
        let sample = try TempSample()
        defer { sample.remove() }
        try writeFixture(sample, "WritingTests/min.json", "{\"b\":2,\"a\":1}")
        let host = try await opened(sample, policy: .allow)
        let formatted = try await host.server.callTool("format_json_file", ["path": .string("WritingTests/min.json")])
        #expect(!formatted.isToolError, "\(formatted.resultText)")
        #expect(formatted.resultText.contains("Successfully formatted and validated JSON file at `WritingTests/min.json`"))
        let text = sample.read("WritingTests/min.json")
        #expect(text.contains("\n"))
        let aAt = try #require(text.range(of: "\"a\"")?.lowerBound)
        let bAt = try #require(text.range(of: "\"b\"")?.lowerBound)
        #expect(aAt < bAt)
        #expect((jsonObject(sample, "WritingTests/min.json") as? [String: Any])?["a"] as? Int == 1)

        try writeFixture(sample, "WritingTests/broken.json", "{not json")
        let broken = try await host.server.callTool("format_json_file", ["path": .string("WritingTests/broken.json")])
        #expect(broken.isToolError && broken.resultText.contains("JSON formatting or validation error in `WritingTests/broken.json`"))
        #expect(sample.read("WritingTests/broken.json") == "{not json")
    }

    @Test func codeFormatNormalizes() async throws {
        let sample = try TempSample()
        defer { sample.remove() }
        try writeFixture(sample, "WritingTests/messy.swift", "func f() {\n\tlet x = 1   \n\n\n    return x\n}")
        let host = try await opened(sample, policy: .allow)
        let formatted = try await host.server.callTool("code_format", ["path": .string("WritingTests/messy.swift")])
        #expect(!formatted.isToolError, "\(formatted.resultText)")
        #expect(formatted.firstText == "Code formatting completed at WritingTests/messy.swift")
        #expect(sample.read("WritingTests/messy.swift") == "func f() {\n    let x = 1\n\n    return x\n}\n")

        let missing = try await host.server.callTool("code_format", ["path": .string("WritingTests/nope.swift")])
        #expect(missing.isToolError && missing.firstText == "Path does not exist: WritingTests/nope.swift")
    }

    @Test func codeGenerateTemplates() async throws {
        let sample = try TempSample()
        defer { sample.remove() }
        let host = try await opened(sample, policy: .allow)

        let strukt = try await host.server.callTool("code_generate", ["path": .string("WritingTests/Generated/Widget.swift"),
                                                                      "template": .string("swift_struct")])
        #expect(!strukt.isToolError, "\(strukt.resultText)")
        #expect(strukt.firstText == "Generated file WritingTests/Generated/Widget.swift using template 'swift_struct'")
        #expect(sample.read("WritingTests/Generated/Widget.swift") == "import Foundation\n\npublic struct Widget {\n    public init() {}\n}\n")

        let klass = try await host.server.callTool("code_generate", ["path": .string("WritingTests/Generated/Gizmo.swift"),
                                                                     "template": .string("swift_class")])
        #expect(!klass.isToolError, "\(klass.resultText)")
        #expect(sample.read("WritingTests/Generated/Gizmo.swift") == "import Foundation\n\npublic final class Gizmo {\n    public init() {}\n}\n")

        let view = try await host.server.callTool("code_generate", ["path": .string("WritingTests/Generated/Badge.swift"),
                                                                    "template": .string("swiftui_view")])
        #expect(!view.isToolError, "\(view.resultText)")
        let viewText = sample.read("WritingTests/Generated/Badge.swift")
        #expect(viewText.contains("struct Badge: View") && viewText.contains("#Preview"))

        let test = try await host.server.callTool("code_generate", ["path": .string("WritingTests/Generated/WidgetTests.swift"),
                                                                    "template": .string("test")])
        #expect(!test.isToolError, "\(test.resultText)")
        let testText = sample.read("WritingTests/Generated/WidgetTests.swift")
        #expect(testText.contains("import XCTest") && testText.contains("final class WidgetTests: XCTestCase")
                && testText.contains("XCTFail(\"Not implemented"))

        let existing = try await host.server.callTool("code_generate", ["path": .string("WritingTests/Generated/Widget.swift"),
                                                                        "template": .string("swift_struct")])
        #expect(existing.isToolError && existing.firstText == "Target file already exists: WritingTests/Generated/Widget.swift")
        let unknown = try await host.server.callTool("code_generate", ["path": .string("WritingTests/Generated/What.swift"),
                                                                       "template": .string("widget")])
        #expect(unknown.isToolError && unknown.firstText == "Unknown template 'widget': expected swift_struct, swift_class, swiftui_view, or test.")
        #expect(!exists(sample, "WritingTests/Generated/What.swift"))
    }

    @Test func codeRefactorFailsCleanlyWithoutLLM() async throws {
        let sample = try TempSample()
        defer { sample.remove() }
        try writeFixture(sample, "WritingTests/refactor.swift", "let x = 1\n")
        let host = try await opened(sample, policy: .allow)
        let refactored = try await host.server.callTool("code_refactor", ["path": .string("WritingTests/refactor.swift"),
                                                                          "action": .string("Rename variable x to y")])
        #expect(refactored.isToolError, "code_refactor must fail without an LLM: \(refactored.resultText)")
        #expect(sample.read("WritingTests/refactor.swift") == "let x = 1\n")
    }

    @Test func batchRenameFiles() async throws {
        let sample = try TempSample()
        defer { sample.remove() }
        try writeFixture(sample, "WritingTests/Rename/old_one.txt", "1\n")
        try writeFixture(sample, "WritingTests/Rename/old_two.txt", "2\n")
        try writeFixture(sample, "WritingTests/Rename/keep.md", "keep\n")
        let host = try await opened(sample, policy: .allow)

        let dry = try await host.server.callTool("batch_rename_files", ["directory": .string("WritingTests/Rename"),
                                                                        "search": .string("old_"), "replacement": .string("new_"),
                                                                        "dryRun": .bool(true)])
        #expect(!dry.isToolError, "\(dry.resultText)")
        #expect(dry.resultText.contains("Dry run: 2 file(s) would be renamed in `WritingTests/Rename`"))
        #expect(dry.resultText.contains("old_one.txt -> new_one.txt"))
        #expect(exists(sample, "WritingTests/Rename/old_one.txt") && !exists(sample, "WritingTests/Rename/new_one.txt"))

        let renamed = try await host.server.callTool("batch_rename_files", ["directory": .string("WritingTests/Rename"),
                                                                            "search": .string("old_"), "replacement": .string("new_")])
        #expect(!renamed.isToolError, "\(renamed.resultText)")
        #expect(renamed.resultText.contains("Successfully batch-renamed 2 file(s) in `WritingTests/Rename`"))
        #expect(!exists(sample, "WritingTests/Rename/old_one.txt") && !exists(sample, "WritingTests/Rename/old_two.txt"))
        #expect(sample.read("WritingTests/Rename/new_one.txt") == "1\n" && sample.read("WritingTests/Rename/new_two.txt") == "2\n")
        #expect(sample.read("WritingTests/Rename/keep.md") == "keep\n")

        let none = try await host.server.callTool("batch_rename_files", ["directory": .string("WritingTests/Rename"),
                                                                         "search": .string("zzz"), "replacement": .string("yyy")])
        #expect(!none.isToolError, "\(none.resultText)")
        #expect(none.firstText == "No files in `WritingTests/Rename` matched search pattern 'zzz'.")

        let missingDir = try await host.server.callTool("batch_rename_files", ["directory": .string("WritingTests/Nope"),
                                                                               "search": .string("a"), "replacement": .string("b")])
        #expect(missingDir.isToolError && missingDir.firstText == "Directory not found at: WritingTests/Nope")
    }

    @Test func fileWriteThenFileBackupRoundTrip() async throws {
        let sample = try TempSample()
        defer { sample.remove() }
        let host = try await opened(sample, policy: .allow, withArtifacts: true)
        let written = try await host.server.callTool("file_write", ["path": .string("WritingTests/precious.txt"),
                                                                    "content": .string("Keep me.\n")])
        #expect(!written.isToolError, "\(written.resultText)")
        let backedUp = try await host.server.callTool("file_backup", ["path": .string("WritingTests/precious.txt")])
        #expect(!backedUp.isToolError, "\(backedUp.resultText)")
        let rel = try #require(backedUp.structured?["backup"]?.string)
        #expect(rel.hasPrefix(".assist_temp/backups/precious.txt.") && rel.hasSuffix(".bak"))
        #expect(fileData(sample, rel) == fileData(sample, "WritingTests/precious.txt"))
        #expect(fileData(sample, rel) == "Keep me.\n".data(using: .utf8))
    }

    @Test func missingRequiredArgumentsAreRejected() async throws {
        let sample = try TempSample()
        defer { sample.remove() }
        let host = try await opened(sample, policy: .allow)
        for id in Self.wave2IDs where id != "code_format" {
            let r = try await host.server.callTool(id, [:])
            #expect(r.isToolError && r.resultText.contains("missing the required argument"), "\(id): \(r.resultText)")
        }
    }
}

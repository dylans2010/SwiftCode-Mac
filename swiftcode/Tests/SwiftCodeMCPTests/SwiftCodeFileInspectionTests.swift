import Foundation
import Testing
import SwiftCodeAssistant
import SwiftCodeIDECore
@testable import SwiftCodeMCP

/// The file-inspection tools (Wave 1 slice C) against a copy of
/// `Samples/AgentSamples/Greeter`.
///
/// The tools are exercised through `MCPServer.run`, exactly as `tools/call`
/// dispatches them, but taken from `host.fileInspectionTools` directly:
/// the array is not wired into `installTools()` yet (that file is owned by
/// the coordinator), so `tools/call` cannot see these tools until then.
@MainActor
@Suite(.serialized) struct SwiftCodeFileInspectionTests {
    /// Runs one inspection tool the way the server would, as a JSON result.
    func call(_ host: SwiftCodeMCPHost, _ name: String, _ args: [String: AnyJSON] = [:]) async throws -> AnyJSON {
        let tool = try #require(host.fileInspectionTools.first { $0.name == name })
        return await host.server.run(tool, MCPToolCall(name: name, arguments: args)).json
    }

    func opened(_ sample: TempSample) async throws -> SwiftCodeMCPHost {
        let host = SwiftCodeMCPHost()
        let r = try await host.server.callTool("workspace_open", ["path": .string(sample.url.path)])
        #expect(!r.isToolError, "\(r.resultText)")
        return host
    }

    func write(_ sample: TempSample, _ rel: String, _ content: String) throws {
        let url = sample.url.appendingPathComponent(rel)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try content.write(to: url, atomically: true, encoding: .utf8)
    }

    func writeData(_ sample: TempSample, _ rel: String, _ data: Data) throws {
        let url = sample.url.appendingPathComponent(rel)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: url)
    }

    /// Known digests of the three bytes `abc` (standard test vectors), so
    /// the hash tools are checked against fixed values, not themselves.
    static let abcSHA256 = "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad"
    static let abcSHA1 = "a9993e364706816aba3e25717850c26c9cd0d89d"
    static let abcMD5 = "900150983cd24fb0d6963f7d28e17f72"

    @Test func catalogue() async throws {
        let host = SwiftCodeMCPHost()
        let tools = host.fileInspectionTools
        #expect(tools.map(\.name) == ["file_compare_diff", "file_checksum_verifier", "file_hash_verify", "file_type_breakdown",
                                      "find_duplicate_files", "empty_dirs_find", "executable_files_scan", "symlink_audit"])
        let byName = Dictionary(uniqueKeysWithValues: tools.map { ($0.name, $0) })
        #expect(byName["file_compare_diff"]?.title == "Compare Two Files and Generate Diff")
        #expect(byName["file_checksum_verifier"]?.title == "File Checksum Verifier")
        #expect(byName["file_hash_verify"]?.title == "Verify File Hash")
        #expect(byName["file_type_breakdown"]?.title == "File Type Breakdown")
        #expect(byName["find_duplicate_files"]?.title == "Find Duplicate Files")
        #expect(byName["empty_dirs_find"]?.title == "Find Empty Directories")
        #expect(byName["executable_files_scan"]?.title == "Executable Files Scan")
        #expect(byName["symlink_audit"]?.title == "Symlink Audit")
        for tool in tools {
            #expect(tool.annotations.readOnly && !tool.writes, "\(tool.name) must be a read-only tool")
            let props = tool.inputSchema["properties"]?.object ?? [:]
            #expect(props["workspace"] != nil, "\(tool.name) must take the workspace parameter")
            #expect(tool.inputSchema["required"]?.array?.compactMap(\.string).contains("workspace") != true)
        }
        #expect(byName["file_compare_diff"]?.inputSchema["required"]?.array?.compactMap(\.string) == ["pathA", "pathB"])
        #expect(byName["file_checksum_verifier"]?.inputSchema["required"]?.array?.compactMap(\.string) == ["path"])
        #expect(byName["file_hash_verify"]?.inputSchema["required"]?.array?.compactMap(\.string) == ["path", "expectedHash"])
        #expect(byName["file_type_breakdown"]?.inputSchema["required"]?.array?.compactMap(\.string).isEmpty == true)
        #expect(byName["find_duplicate_files"]?.inputSchema["required"]?.array?.compactMap(\.string).isEmpty == true)
        #expect(byName["empty_dirs_find"]?.inputSchema["required"]?.array?.compactMap(\.string).isEmpty == true)
        #expect(byName["executable_files_scan"]?.inputSchema["required"]?.array?.compactMap(\.string).isEmpty == true)
        #expect(byName["symlink_audit"]?.inputSchema["required"]?.array?.compactMap(\.string).isEmpty == true)
        #expect(byName["file_compare_diff"]?.description == "Compares two files line-by-line and produces a formatted unified diff with added/removed stats.")
        #expect(byName["find_duplicate_files"]?.description == "Finds byte-identical duplicate files under a directory using SHA-256 content hashing.")
    }

    @Test func compareDiff() async throws {
        let sample = try TempSample()
        defer { sample.remove() }
        try write(sample, "a.txt", "one\ntwo\nthree")
        try write(sample, "b.txt", "one\nTWO\nthree\nfour")
        try write(sample, "c.txt", "alpha\nbeta")
        let host = try await opened(sample)

        let diff = try await call(host, "file_compare_diff", ["pathA": "a.txt", "pathB": "b.txt"])
        #expect(!diff.isToolError, "\(diff.resultText)")
        #expect(diff.structured?["identical"]?.bool == false)
        #expect(diff.structured?["addedLines"]?.int == 2 && diff.structured?["removedLines"]?.int == 1)
        let text = diff.structured?["diff"]?.string ?? ""
        #expect(text.contains("--- a/a.txt") && text.contains("+++ b/b.txt") && text.contains("@@ -1,3 +1,4 @@"))
        #expect(text.contains("  one") && text.contains("- two") && text.contains("+ TWO") && text.contains("+ four"))
        #expect(diff.resultText.contains("Unified diff for `a.txt` vs `b.txt` (+2, -1 lines)"))

        let same = try await call(host, "file_compare_diff", ["pathA": "c.txt", "pathB": "c.txt"])
        #expect(same.structured?["identical"]?.bool == true && same.structured?["lineCount"]?.int == 2)
        #expect(same.resultText.contains("are identical (2 lines)"))

        let missing = try await call(host, "file_compare_diff", ["pathA": "a.txt", "pathB": "NoSuch.txt"])
        #expect(missing.isToolError && missing.resultText.contains("File B not found: NoSuch.txt"))
        let outside = try await call(host, "file_compare_diff", ["pathA": "..", "pathB": "a.txt"])
        #expect(outside.isToolError && outside.resultText.contains("outside the workspace"))

        try writeData(sample, "bin1.dat", Data([0x00, 0x01, 0x02, 0xff]))
        try writeData(sample, "bin2.dat", Data([0x00, 0x01, 0x03, 0xff]))
        let binary = try await call(host, "file_compare_diff", ["pathA": "bin1.dat", "pathB": "bin2.dat"])
        #expect(binary.isToolError && binary.resultText.contains("Failed to read files for comparison"))
    }

    @Test func checksumVerifier() async throws {
        let sample = try TempSample()
        defer { sample.remove() }
        try writeData(sample, "abc.txt", Data("abc".utf8))
        try writeData(sample, "bin.dat", Data([0x00, 0x01, 0x02, 0xff, 0x00]))
        let host = try await opened(sample)

        let def = try await call(host, "file_checksum_verifier", ["path": "abc.txt"])
        #expect(!def.isToolError, "\(def.resultText)")
        #expect(def.structured?["algorithm"]?.string == "sha256" && def.structured?["hash"] == Self.abcSHA256 && def.structured?["size"]?.int == 3)
        #expect(def.resultText.contains("Algorithm: SHA256") && def.resultText.contains(Self.abcSHA256))
        let sha1 = try await call(host, "file_checksum_verifier", ["path": "abc.txt", "algorithm": "sha1"])
        #expect(sha1.structured?["hash"] == Self.abcSHA1)
        let md5 = try await call(host, "file_checksum_verifier", ["path": "abc.txt", "algorithm": "MD5"])
        #expect(md5.structured?["algorithm"]?.string == "md5" && md5.structured?["hash"] == Self.abcMD5)
        // Legacy falls through to SHA-256 for an unknown algorithm name.
        let unknown = try await call(host, "file_checksum_verifier", ["path": "abc.txt", "algorithm": "sha512"])
        #expect(!unknown.isToolError && unknown.structured?["algorithm"]?.string == "sha256" && unknown.structured?["hash"] == Self.abcSHA256)
        // Binary files hash fine; a directory does not.
        let bin = try await call(host, "file_checksum_verifier", ["path": "bin.dat"])
        #expect(!bin.isToolError && bin.structured?["size"]?.int == 5)
        let dir = try await call(host, "file_checksum_verifier", ["path": "Sources"])
        #expect(dir.isToolError && dir.resultText.contains("Unable to read data from file at: Sources"))
        let missing = try await call(host, "file_checksum_verifier", ["path": "NoSuch.txt"])
        #expect(missing.isToolError && missing.resultText.contains("File not found at: NoSuch.txt"))
        let outside = try await call(host, "file_checksum_verifier", ["path": ".."])
        #expect(outside.isToolError && outside.resultText.contains("outside the workspace"))
    }

    @Test func hashVerify() async throws {
        let sample = try TempSample()
        defer { sample.remove() }
        try writeData(sample, "abc.txt", Data("abc".utf8))
        let host = try await opened(sample)

        let match = try await call(host, "file_hash_verify", ["path": "abc.txt", "expectedHash": Self.abcSHA256])
        #expect(!match.isToolError, "\(match.resultText)")
        #expect(match.structured?["match"]?.bool == true && match.structured?["computedHash"] == Self.abcSHA256)
        #expect(match.resultText.contains("Hash match: true."))
        // A mismatch is a successful comparison with match false, not an error.
        let zeros = String(repeating: "0", count: 64)
        let mismatch = try await call(host, "file_hash_verify", ["path": "abc.txt", "expectedHash": zeros])
        #expect(!mismatch.isToolError && mismatch.structured?["match"]?.bool == false)
        #expect(mismatch.resultText.contains("Hash match: false.") && mismatch.resultText.contains("expected \(zeros)"))
        let md5 = try await call(host, "file_hash_verify", ["path": "abc.txt", "expectedHash": Self.abcMD5, "algorithm": "md5"])
        #expect(md5.structured?["match"]?.bool == true)

        let badAlgorithm = try await call(host, "file_hash_verify", ["path": "abc.txt", "expectedHash": Self.abcSHA256, "algorithm": "sha512"])
        #expect(badAlgorithm.isToolError && badAlgorithm.resultText.contains("Invalid algorithm 'sha512'"))
        let short = try await call(host, "file_hash_verify", ["path": "abc.txt", "expectedHash": "abc"])
        #expect(short.isToolError && short.resultText.contains("Invalid expectedHash for sha256. Expected 64 hexadecimal characters."))
        let nonHex = try await call(host, "file_hash_verify", ["path": "abc.txt", "expectedHash": String(repeating: "z", count: 64)])
        #expect(nonHex.isToolError && nonHex.resultText.contains("Invalid expectedHash"))
        let missing = try await call(host, "file_hash_verify", ["path": "NoSuch.txt", "expectedHash": Self.abcSHA256])
        #expect(missing.isToolError && missing.resultText.contains("Hash verification requires an existing file: NoSuch.txt"))
        let dir = try await call(host, "file_hash_verify", ["path": "Sources", "expectedHash": Self.abcSHA256])
        #expect(dir.isToolError && dir.resultText.contains("Hash verification requires an existing file: Sources"))
        let outside = try await call(host, "file_hash_verify", ["path": "..", "expectedHash": Self.abcSHA256])
        #expect(outside.isToolError && outside.resultText.contains("outside the workspace"))
    }

    @Test func typeBreakdown() async throws {
        let sample = try TempSample()
        defer { sample.remove() }
        let host = try await opened(sample)

        let all = try await call(host, "file_type_breakdown")
        #expect(!all.isToolError, "\(all.resultText)")
        // Greeter: 5 Swift files (Package.swift included) + 1 .xcstrings.
        #expect(all.structured?["typeCount"]?.int == 2)
        let swift = all.structured?["types"]?.array?.first { $0["extension"] == ".swift" }
        #expect(swift?["files"]?.int == 5 && (swift?["bytes"]?.int ?? 0) > 0)
        #expect(all.resultText.contains("| Extension | Files | Bytes |") && all.resultText.contains("| .swift | 5 |"))

        let sources = try await call(host, "file_type_breakdown", ["path": "Sources"])
        #expect(sources.structured?["typeCount"]?.int == 1)
        #expect(sources.structured?["types"]?.array?.first?["files"]?.int == 2)

        let missing = try await call(host, "file_type_breakdown", ["path": "NoSuchDir"])
        #expect(missing.isToolError && missing.resultText.contains("Cannot enumerate directory: NoSuchDir"))
        let outside = try await call(host, "file_type_breakdown", ["path": ".."])
        #expect(outside.isToolError && outside.resultText.contains("outside the workspace"))
    }

    @Test func duplicateFiles() async throws {
        let sample = try TempSample()
        defer { sample.remove() }
        try write(sample, "dup/a.txt", "same content")
        try write(sample, "dup/b.txt", "same content")
        try write(sample, "dup/c.txt", "different")
        try write(sample, "dup/d.txt", "same content!")
        let host = try await opened(sample)

        let dupes = try await call(host, "find_duplicate_files", ["path": "dup"])
        #expect(!dupes.isToolError, "\(dupes.resultText)")
        #expect(dupes.structured?["groupCount"]?.int == 1)
        let groups = dupes.structured?["groups"]?.array?.compactMap { $0.array?.compactMap(\.string) }
        #expect(groups == [["dup/a.txt", "dup/b.txt"]])
        #expect(dupes.resultText.contains("Duplicate file groups (1):"))

        // Files below minSize are ignored.
        let none = try await call(host, "find_duplicate_files", ["path": "dup", "minSize": 100])
        #expect(none.structured?["groupCount"]?.int == 0)
        #expect(none.resultText.contains("No duplicate files found under dup."))
        let missing = try await call(host, "find_duplicate_files", ["path": "NoSuchDir"])
        #expect(missing.isToolError && missing.resultText.contains("Cannot enumerate directory: NoSuchDir"))
    }

    @Test func emptyDirs() async throws {
        let sample = try TempSample()
        defer { sample.remove() }
        let fm = FileManager.default
        try fm.createDirectory(atPath: sample.path("empty1"), withIntermediateDirectories: true)
        try fm.createDirectory(atPath: sample.path("nested/empty2"), withIntermediateDirectories: true)
        try write(sample, "full/file.txt", "x")
        let host = try await opened(sample)

        let found = try await call(host, "empty_dirs_find")
        #expect(!found.isToolError, "\(found.resultText)")
        #expect(found.structured?["count"]?.int == 2)
        #expect(found.structured?["directories"]?.array?.compactMap(\.string) == ["empty1", "nested/empty2"])
        #expect(found.resultText.contains("Empty directories (2):"))

        let nested = try await call(host, "empty_dirs_find", ["path": "nested"])
        #expect(nested.structured?["count"]?.int == 1)
        let full = try await call(host, "empty_dirs_find", ["path": "full"])
        #expect(full.structured?["count"]?.int == 0 && full.resultText.contains("No empty directories under full."))
    }

    @Test func executableScan() async throws {
        let sample = try TempSample()
        defer { sample.remove() }
        try write(sample, "bin/run.sh", "#!/bin/sh\necho hi\n")
        try write(sample, "bin/plain.sh", "#!/bin/sh\necho hi\n")
        try write(sample, "bin/tool", "binary")
        let fm = FileManager.default
        try fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: sample.path("bin/run.sh"))
        try fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: sample.path("bin/tool"))
        let host = try await opened(sample)

        let execs = try await call(host, "executable_files_scan", ["path": "bin"])
        #expect(!execs.isToolError, "\(execs.resultText)")
        #expect(execs.structured?["count"]?.int == 2)
        #expect(execs.structured?["files"]?.array?.compactMap(\.string) == ["bin/run.sh", "bin/tool"])

        let limited = try await call(host, "executable_files_scan", ["path": "bin", "limit": 1])
        #expect(limited.structured?["count"]?.int == 1)
        let none = try await call(host, "executable_files_scan", ["path": "Sources"])
        #expect(none.structured?["count"]?.int == 0 && none.resultText.contains("No executable files under Sources."))
    }

    @Test func symlinkAudit() async throws {
        let sample = try TempSample()
        defer { sample.remove() }
        let fm = FileManager.default
        try fm.createDirectory(atPath: sample.path("links"), withIntermediateDirectories: true)
        try fm.createSymbolicLink(atPath: sample.path("links/good"), withDestinationPath: "../Sources/Greeter/Greeter.swift")
        try fm.createSymbolicLink(atPath: sample.path("links/broken"), withDestinationPath: "nope.txt")
        try fm.createSymbolicLink(atPath: sample.path("links/escape"), withDestinationPath: "/etc/hosts")
        try fm.createSymbolicLink(atPath: sample.path("links/dirlink"), withDestinationPath: "../Sources")
        let host = try await opened(sample)

        let audit = try await call(host, "symlink_audit", ["path": "links"])
        #expect(!audit.isToolError, "\(audit.resultText)")
        #expect(audit.structured?["count"]?.int == 4)
        #expect(audit.structured?["brokenCount"]?.int == 1)
        #expect(audit.structured?["escapingCount"]?.int == 1)
        let links = audit.structured?["links"]?.array ?? []
        // The directory link is a leaf: nothing under Sources is listed.
        #expect(links.count == 4)
        let byPath = Dictionary(uniqueKeysWithValues: links.compactMap { l -> (String, AnyJSON)? in
            guard let p = l["path"]?.string else { return nil }
            return (p, l)
        })
        #expect(byPath["links/good"]?["broken"] == false && byPath["links/good"]?["escapesWorkspace"] == false)
        #expect(byPath["links/good"]?["target"] == "../Sources/Greeter/Greeter.swift")
        #expect(byPath["links/broken"]?["broken"] == true)
        #expect(byPath["links/escape"]?["escapesWorkspace"] == true && byPath["links/escape"]?["broken"] == false)
        #expect(audit.resultText.contains("[BROKEN]") && audit.resultText.contains("[ESCAPES WORKSPACE]"))

        let none = try await call(host, "symlink_audit", ["path": "Sources"])
        #expect(none.structured?["count"]?.int == 0 && none.resultText.contains("No symbolic links under Sources."))
        let outside = try await call(host, "symlink_audit", ["path": ".."])
        #expect(outside.isToolError && outside.resultText.contains("outside the workspace"))
    }
}

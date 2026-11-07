import Foundation
import Testing
import YcodeAssistant
@testable import YcodeMCP

@MainActor
@Suite(.serialized) struct SwiftCodeArchiveDataTests {
    static let archiveIDs = ["gzip_compress_file", "gzip_decompress_file", "tar_archive_create",
                             "tar_archive_extract", "unzip_file", "zip_file"]
    static let dataIDs = ["binary_plist_converter", "json_validate", "json_validator_tool",
                          "yaml_parser_tool", "yaml_validate"]

    func opened(_ sample: TempSample, policy: MCPWritePolicy = .allow) async throws -> SwiftCodeMCPHost {
        let host = SwiftCodeMCPHost()
        host.server.writePolicy = policy
        let ported = Set(host.archiveTools.map(\.name) + host.dataTools.map(\.name))
        host.server.tools = host.server.tools.filter { !ported.contains($0.name) } + host.archiveTools + host.dataTools
        let r = try await host.server.callTool("workspace_open", ["path": .string(sample.url.path)])
        #expect(!r.isToolError, "\(r.resultText)")
        return host
    }

    func writeFixture(_ sample: TempSample, _ rel: String, _ content: String) throws {
        let url = URL(fileURLWithPath: sample.path(rel))
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try content.write(to: url, atomically: true, encoding: .utf8)
    }

    func readFixture(_ sample: TempSample, _ rel: String) throws -> String {
        try String(contentsOfFile: sample.path(rel), encoding: .utf8)
    }

    func fileExists(_ sample: TempSample, _ rel: String) -> Bool {
        FileManager.default.fileExists(atPath: sample.path(rel))
    }

    @Test func toolsAreRegisteredWithLegacySchemas() async throws {
        let host = SwiftCodeMCPHost()
        let archiveTools = host.archiveTools
        let dataTools = host.dataTools
        #expect(archiveTools.map(\.name) == Self.archiveIDs)
        #expect(dataTools.map(\.name) == Self.dataIDs)
        let expectedTitles: [String: String] = [
            "gzip_compress_file": "Gzip Compress File", "gzip_decompress_file": "Gzip Decompress File",
            "tar_archive_create": "Create Tar Archive", "tar_archive_extract": "Extract Tar Archive",
            "unzip_file": "Unzip Archive", "zip_file": "Zip File or Directory",
            "binary_plist_converter": "Binary Plist Converter", "json_validate": "Validate JSON",
            "json_validator_tool": "JSON Validator & Formatter", "yaml_parser_tool": "YAML Parser & Validator",
            "yaml_validate": "Validate YAML",
        ]
        let expectedRequired: [String: [String]] = [
            "gzip_compress_file": ["path"], "gzip_decompress_file": ["path"],
            "tar_archive_create": ["path", "destination"], "tar_archive_extract": ["path", "destination"],
            "unzip_file": ["path", "destination"], "zip_file": ["path", "destination"],
            "binary_plist_converter": ["path"], "json_validate": ["path"], "json_validator_tool": ["path"],
            "yaml_parser_tool": ["path"], "yaml_validate": ["path"],
        ]
        let expectedOutputs: [String: [String]] = [
            "gzip_compress_file": ["destination", "size"], "gzip_decompress_file": ["destination", "size"],
            "tar_archive_create": ["destination", "size"], "tar_archive_extract": ["destination", "extractedCount"],
            "unzip_file": ["destination", "extractedCount"], "zip_file": ["destination", "size"],
            "binary_plist_converter": [],
            "json_validate": ["path", "valid", "written"], "json_validator_tool": [],
            "yaml_parser_tool": [], "yaml_validate": ["heuristic", "path", "valid", "written"],
        ]
        for tool in archiveTools + dataTools {
            #expect(tool.title == expectedTitles[tool.name])
            #expect(tool.inputSchema["properties"]?["workspace"] != nil, "\(tool.name) is missing the workspace parameter")
            let required = tool.inputSchema["required"]?.array?.compactMap(\.string) ?? []
            #expect(required == expectedRequired[tool.name], "\(tool.name) required: \(required)")
            let outputKeys = tool.outputSchema?["properties"]?.object?.keys.sorted() ?? []
            #expect(outputKeys == expectedOutputs[tool.name], "\(tool.name) output keys: \(outputKeys)")
            if tool.name == "yaml_parser_tool" {
                #expect(tool.annotations.readOnly && tool.annotations.idempotent && !tool.writes,
                        "\(tool.name) must be a read-only tool")
            } else {
                #expect(!tool.annotations.readOnly && tool.annotations.idempotent && tool.writes,
                        "\(tool.name) must be a safeMutation write tool")
            }
        }
    }

    @Test func zipAndUnzipRoundTrip() async throws {
        let sample = try TempSample()
        defer { sample.remove() }
        try writeFixture(sample, "docs/a.txt", "hello zip")
        try writeFixture(sample, "docs/b.txt", "second file")
        let host = try await opened(sample)
        let zipped = try await host.server.callTool("zip_file",
                                                    ["path": .string("docs"), "destination": .string("docs.zip")])
        #expect(!zipped.isToolError, "\(zipped.resultText)")
        #expect(zipped.firstText.contains("Successfully compressed `docs` into `docs.zip`"))
        #expect(zipped.structured?["destination"]?.string == "docs.zip")
        #expect((zipped.structured?["size"]?.int ?? 0) > 0)
        #expect(fileExists(sample, "docs.zip"))
        let unzipped = try await host.server.callTool("unzip_file",
                                                      ["path": .string("docs.zip"), "destination": .string("out")])
        #expect(!unzipped.isToolError, "\(unzipped.resultText)")
        #expect(unzipped.firstText.contains("Successfully extracted `docs.zip` into `out`"))
        #expect(unzipped.structured?["extractedCount"]?.int == 1)
        #expect(try readFixture(sample, "out/docs/a.txt") == "hello zip")
        #expect(try readFixture(sample, "out/docs/b.txt") == "second file")
    }

    @Test func zipSingleFileRoundTrip() async throws {
        let sample = try TempSample()
        defer { sample.remove() }
        try writeFixture(sample, "note.txt", "just one file")
        let host = try await opened(sample)
        let zipped = try await host.server.callTool("zip_file",
                                                    ["path": .string("note.txt"), "destination": .string("note.zip")])
        #expect(!zipped.isToolError, "\(zipped.resultText)")
        let unzipped = try await host.server.callTool("unzip_file",
                                                      ["path": .string("note.zip"), "destination": .string("unzipped")])
        #expect(!unzipped.isToolError, "\(unzipped.resultText)")
        #expect(try readFixture(sample, "unzipped/note.txt") == "just one file")
    }

    @Test func zipMissingSourceFails() async throws {
        let sample = try TempSample()
        defer { sample.remove() }
        let host = try await opened(sample)
        let r = try await host.server.callTool("zip_file",
                                               ["path": .string("nope"), "destination": .string("nope.zip")])
        #expect(r.isToolError)
        #expect(r.firstText.contains("Source item not found at: nope"))
        #expect(!fileExists(sample, "nope.zip"))
    }

    @Test func zipEscapingPathFails() async throws {
        let sample = try TempSample()
        defer { sample.remove() }
        let host = try await opened(sample)
        let r = try await host.server.callTool("zip_file",
                                               ["path": .string("../escape"), "destination": .string("out.zip")])
        #expect(r.isToolError)
        #expect(r.firstText.contains("outside the workspace"))
    }

    @Test func unzipMissingArchiveFails() async throws {
        let sample = try TempSample()
        defer { sample.remove() }
        let host = try await opened(sample)
        let r = try await host.server.callTool("unzip_file",
                                               ["path": .string("nope.zip"), "destination": .string("out")])
        #expect(r.isToolError)
        #expect(r.firstText.contains("Archive file not found at: nope.zip"))
    }

    @Test func tarGzipRoundTrip() async throws {
        let sample = try TempSample()
        defer { sample.remove() }
        try writeFixture(sample, "src/hello.txt", "hello tar")
        let host = try await opened(sample)
        let created = try await host.server.callTool("tar_archive_create",
                                                     ["path": .string("src"), "destination": .string("src.tar.gz")])
        #expect(!created.isToolError, "\(created.resultText)")
        #expect(created.firstText.contains("Successfully created tar archive `src.tar.gz`"))
        #expect((created.structured?["size"]?.int ?? 0) > 0)
        let extracted = try await host.server.callTool("tar_archive_extract",
                                                       ["path": .string("src.tar.gz"), "destination": .string("restored")])
        #expect(!extracted.isToolError, "\(extracted.resultText)")
        #expect(extracted.firstText.contains("Successfully extracted archive `src.tar.gz` into `restored`"))
        #expect(try readFixture(sample, "restored/src/hello.txt") == "hello tar")
    }

    @Test func tarPlainRoundTrip() async throws {
        let sample = try TempSample()
        defer { sample.remove() }
        try writeFixture(sample, "plain.txt", "no compression")
        let host = try await opened(sample)
        let created = try await host.server.callTool("tar_archive_create",
                                                     ["path": .string("plain.txt"), "destination": .string("plain.tar"),
                                                      "gzip": .bool(false)])
        #expect(!created.isToolError, "\(created.resultText)")
        let extracted = try await host.server.callTool("tar_archive_extract",
                                                       ["path": .string("plain.tar"), "destination": .string("plain-out")])
        #expect(!extracted.isToolError, "\(extracted.resultText)")
        #expect(try readFixture(sample, "plain-out/plain.txt") == "no compression")
    }

    @Test func tarMissingSourceFails() async throws {
        let sample = try TempSample()
        defer { sample.remove() }
        let host = try await opened(sample)
        let r = try await host.server.callTool("tar_archive_create",
                                               ["path": .string("nope"), "destination": .string("nope.tar")])
        #expect(r.isToolError)
        #expect(r.firstText.contains("Source file/folder not found at: nope"))
        let r2 = try await host.server.callTool("tar_archive_extract",
                                                ["path": .string("nope.tar"), "destination": .string("out")])
        #expect(r2.isToolError)
        #expect(r2.firstText.contains("Archive not found at: nope.tar"))
    }

    @Test func gzipRoundTripWithDefaults() async throws {
        let sample = try TempSample()
        defer { sample.remove() }
        try writeFixture(sample, "data.txt", "compress me please")
        let host = try await opened(sample)
        let compressed = try await host.server.callTool("gzip_compress_file", ["path": .string("data.txt")])
        #expect(!compressed.isToolError, "\(compressed.resultText)")
        #expect(compressed.structured?["destination"]?.string == "data.txt.gz")
        #expect(compressed.firstText.contains("Successfully compressed `data.txt` to `data.txt.gz`"))
        #expect(fileExists(sample, "data.txt.gz"))
        #expect(try readFixture(sample, "data.txt") == "compress me please")
        let decompressed = try await host.server.callTool("gzip_decompress_file", ["path": .string("data.txt.gz")])
        #expect(!decompressed.isToolError, "\(decompressed.resultText)")
        #expect(decompressed.structured?["destination"]?.string == "data.txt")
        #expect(decompressed.firstText.contains("Successfully decompressed `data.txt.gz` to `data.txt`"))
    }

    @Test func gzipExplicitDestinations() async throws {
        let sample = try TempSample()
        defer { sample.remove() }
        try writeFixture(sample, "in.txt", "explicit paths")
        let host = try await opened(sample)
        let compressed = try await host.server.callTool("gzip_compress_file",
                                                        ["path": .string("in.txt"), "destination": .string("sub/out.gz")])
        #expect(!compressed.isToolError, "\(compressed.resultText)")
        #expect(fileExists(sample, "sub/out.gz"))
        let decompressed = try await host.server.callTool("gzip_decompress_file",
                                                          ["path": .string("sub/out.gz"), "destination": .string("sub/back.txt")])
        #expect(!decompressed.isToolError, "\(decompressed.resultText)")
        #expect(try readFixture(sample, "sub/back.txt") == "explicit paths")
    }

    @Test func gzipDecompressWithoutSuffixDefaultsToDecompressed() async throws {
        let sample = try TempSample()
        defer { sample.remove() }
        try writeFixture(sample, "raw.txt", "no gz suffix here")
        let host = try await opened(sample)
        let compressed = try await host.server.callTool("gzip_compress_file",
                                                        ["path": .string("raw.txt"), "destination": .string("raw.bin")])
        #expect(!compressed.isToolError, "\(compressed.resultText)")
        let decompressed = try await host.server.callTool("gzip_decompress_file", ["path": .string("raw.bin")])
        #expect(!decompressed.isToolError, "\(decompressed.resultText)")
        #expect(decompressed.structured?["destination"]?.string == "raw.bin.decompressed")
        #expect(try readFixture(sample, "raw.bin.decompressed") == "no gz suffix here")
    }

    @Test func gzipMissingAndCorruptFail() async throws {
        let sample = try TempSample()
        defer { sample.remove() }
        try writeFixture(sample, "bad.gz", "this is not gzip data")
        let host = try await opened(sample)
        let missing = try await host.server.callTool("gzip_compress_file", ["path": .string("nope.txt")])
        #expect(missing.isToolError)
        #expect(missing.firstText.contains("File not found at: nope.txt"))
        let corrupt = try await host.server.callTool("gzip_decompress_file", ["path": .string("bad.gz")])
        #expect(corrupt.isToolError)
        #expect(corrupt.firstText.contains("gzip decompression failed:"))
    }

    @Test func archiveWritesRefusedWhenReadOnly() async throws {
        let sample = try TempSample()
        defer { sample.remove() }
        try writeFixture(sample, "a.txt", "x")
        let host = try await opened(sample, policy: .readOnly)
        let r = try await host.server.callTool("zip_file",
                                               ["path": .string("a.txt"), "destination": .string("a.zip")])
        #expect(r.isToolError)
        #expect(r.firstText.contains("read-only"))
        #expect(!fileExists(sample, "a.zip"))
    }

    @Test func binaryPlistRoundTrip() async throws {
        let sample = try TempSample()
        defer { sample.remove() }
        let xml = """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
        <dict>
        <key>name</key>
        <string>Greeter</string>
        <key>count</key>
        <integer>3</integer>
        </dict>
        </plist>
        """
        try writeFixture(sample, "Info.plist", xml)
        let host = try await opened(sample)
        let toBinary = try await host.server.callTool("binary_plist_converter",
                                                      ["path": .string("Info.plist"), "format": .string("binary1")])
        #expect(!toBinary.isToolError, "\(toBinary.resultText)")
        #expect(toBinary.firstText == "Successfully converted `Info.plist` to binary1 format.")
        let binary = try Data(contentsOf: URL(fileURLWithPath: sample.path("Info.plist")))
        #expect(binary.prefix(6) == Data("bplist".utf8))
        let toXML = try await host.server.callTool("binary_plist_converter",
                                                   ["path": .string("Info.plist"), "format": .string("xml1")])
        #expect(!toXML.isToolError, "\(toXML.resultText)")
        let back = try readFixture(sample, "Info.plist")
        #expect(back.contains("Greeter"))
        #expect(back.contains("<key>count</key>"))
    }

    @Test func binaryPlistDefaultsToXMLAndRejectsBadFormat() async throws {
        let sample = try TempSample()
        defer { sample.remove() }
        let xml = """
        <?xml version="1.0" encoding="UTF-8"?>
        <plist version="1.0"><dict><key>a</key><string>b</string></dict></plist>
        """
        try writeFixture(sample, "a.plist", xml)
        let host = try await opened(sample)
        let bad = try await host.server.callTool("binary_plist_converter",
                                                 ["path": .string("a.plist"), "format": .string("json")])
        #expect(bad.isToolError)
        #expect(bad.firstText.contains("Unsupported plist format 'json'"))
        #expect(try readFixture(sample, "a.plist") == xml)
    }

    @Test func binaryPlistMissingAndInvalidFail() async throws {
        let sample = try TempSample()
        defer { sample.remove() }
        try writeFixture(sample, "bad.plist", "not a plist at all")
        let host = try await opened(sample)
        let missing = try await host.server.callTool("binary_plist_converter", ["path": .string("nope.plist")])
        #expect(missing.isToolError)
        #expect(missing.firstText.contains("File not found at: nope.plist"))
        let invalid = try await host.server.callTool("binary_plist_converter", ["path": .string("bad.plist")])
        #expect(invalid.isToolError)
        #expect(invalid.firstText.contains("Failed to read plist at `bad.plist`"))
    }

    @Test func jsonValidateValidAndInvalid() async throws {
        let sample = try TempSample()
        defer { sample.remove() }
        try writeFixture(sample, "good.json", "{\"b\": 2, \"a\": 1}")
        try writeFixture(sample, "bad.json", "{\"a\": }")
        let host = try await opened(sample)
        let good = try await host.server.callTool("json_validate", ["path": .string("good.json")])
        #expect(!good.isToolError, "\(good.resultText)")
        #expect(good.firstText == "Valid JSON in good.json.")
        #expect(good.structured?["valid"]?.bool == true)
        #expect(good.structured?["written"]?.bool == false)
        let bad = try await host.server.callTool("json_validate", ["path": .string("bad.json")])
        #expect(bad.isToolError)
        #expect(bad.firstText.contains("Invalid JSON in bad.json:"))
    }

    @Test func jsonValidateFormatPreviewDoesNotWrite() async throws {
        let sample = try TempSample()
        defer { sample.remove() }
        let original = "{\"b\": 2, \"a\": 1}"
        try writeFixture(sample, "fmt.json", original)
        let host = try await opened(sample)
        let r = try await host.server.callTool("json_validate",
                                               ["path": .string("fmt.json"), "action": .string("format")])
        #expect(!r.isToolError, "\(r.resultText)")
        #expect(r.firstText.contains("Formatted preview returned without writing."))
        #expect(r.structured?["written"]?.bool == false)
        let formatted = r.structured?["formatted"]?.string ?? ""
        #expect(formatted.contains("\"a\" : 1") || formatted.contains("\"a\": 1"))
        #expect(try readFixture(sample, "fmt.json") == original)
    }

    @Test func jsonValidateFormatWriteRewritesFile() async throws {
        let sample = try TempSample()
        defer { sample.remove() }
        try writeFixture(sample, "fmt.json", "{\"b\": 2, \"a\": 1}")
        let host = try await opened(sample)
        let r = try await host.server.callTool("json_validate",
                                               ["path": .string("fmt.json"), "action": .string("format"),
                                                "write": .string("true")])
        #expect(!r.isToolError, "\(r.resultText)")
        #expect(r.firstText.contains("Formatted JSON written back to the file."))
        #expect(r.structured?["written"]?.bool == true)
        let onDisk = try readFixture(sample, "fmt.json")
        #expect(onDisk.contains("\"a\""))
        #expect(onDisk.firstIndex(of: "a")! < onDisk.firstIndex(of: "b")!)
    }

    @Test func jsonValidateBadActionAndMissingFail() async throws {
        let sample = try TempSample()
        defer { sample.remove() }
        try writeFixture(sample, "a.json", "{}")
        let host = try await opened(sample)
        let badAction = try await host.server.callTool("json_validate",
                                                       ["path": .string("a.json"), "action": .string("frobnicate")])
        #expect(badAction.isToolError)
        #expect(badAction.firstText.contains("Invalid action 'frobnicate'. Allowed: validate, format."))
        let missing = try await host.server.callTool("json_validate", ["path": .string("nope.json")])
        #expect(missing.isToolError)
        #expect(missing.firstText.contains("JSON validation requires an existing file: nope.json"))
    }

    @Test func jsonValidatorToolValidReportsTopLevelType() async throws {
        let sample = try TempSample()
        defer { sample.remove() }
        try writeFixture(sample, "obj.json", "{\"a\": 1}")
        try writeFixture(sample, "arr.json", "[1, 2]")
        let host = try await opened(sample)
        let obj = try await host.server.callTool("json_validator_tool", ["path": .string("obj.json")])
        #expect(!obj.isToolError, "\(obj.resultText)")
        #expect(obj.firstText.contains("✅ JSON syntax valid for `obj.json` (8 bytes). Top-level type:"))
        let arr = try await host.server.callTool("json_validator_tool", ["path": .string("arr.json")])
        #expect(!arr.isToolError, "\(arr.resultText)")
        #expect(arr.firstText.contains("✅ JSON syntax valid for `arr.json` (6 bytes). Top-level type:"))
    }

    @Test func jsonValidatorToolRejectsFragmentUnlikeJsonValidate() async throws {
        let sample = try TempSample()
        defer { sample.remove() }
        try writeFixture(sample, "scalar.json", "42")
        let host = try await opened(sample)
        let validate = try await host.server.callTool("json_validate", ["path": .string("scalar.json")])
        #expect(!validate.isToolError, "\(validate.resultText)")
        let validator = try await host.server.callTool("json_validator_tool", ["path": .string("scalar.json")])
        #expect(validator.isToolError)
        #expect(validator.firstText.contains("JSON Validation Error in `scalar.json`:"))
    }

    @Test func jsonValidatorToolFormatInPlace() async throws {
        let sample = try TempSample()
        defer { sample.remove() }
        try writeFixture(sample, "messy.json", "{\"b\":2,\"a\":1}")
        let host = try await opened(sample)
        let r = try await host.server.callTool("json_validator_tool",
                                               ["path": .string("messy.json"), "formatInPlace": .bool(true)])
        #expect(!r.isToolError, "\(r.resultText)")
        #expect(r.firstText.contains("JSON is valid! Successfully reformatted and saved `messy.json`"))
        let onDisk = try readFixture(sample, "messy.json")
        #expect(onDisk.firstIndex(of: "a")! < onDisk.firstIndex(of: "b")!)
    }

    @Test func jsonValidatorToolInvalidFails() async throws {
        let sample = try TempSample()
        defer { sample.remove() }
        try writeFixture(sample, "bad.json", "{oops")
        let host = try await opened(sample)
        let r = try await host.server.callTool("json_validator_tool", ["path": .string("bad.json")])
        #expect(r.isToolError)
        #expect(r.firstText.contains("JSON Validation Error in `bad.json`:"))
    }

    @Test func yamlParserReportsTabsAndKeys() async throws {
        let sample = try TempSample()
        defer { sample.remove() }
        try writeFixture(sample, "ci.yml", "name: CI\non:\n  push:\n    branches: [main]\n\tbad: tab\n# a comment\njobs:\n  build:\n    runs-on: ubuntu-latest\n")
        let host = try await opened(sample)
        let r = try await host.server.callTool("yaml_parser_tool", ["path": .string("ci.yml")])
        #expect(!r.isToolError, "\(r.resultText)")
        #expect(r.firstText.contains("### YAML Inspection for `ci.yml`:"))
        #expect(r.firstText.contains("Line 5: Hard tab indentation detected. YAML strictly requires spaces."))
        #expect(r.firstText.contains("`name`"))
        #expect(r.firstText.contains("`jobs`"))
        #expect(r.firstText.contains("Root & Key Declarations"))
    }

    @Test func yamlParserCleanFilePassesIndentation() async throws {
        let sample = try TempSample()
        defer { sample.remove() }
        try writeFixture(sample, "ok.yml", "name: demo\nversion: 1\n")
        let host = try await opened(sample)
        let r = try await host.server.callTool("yaml_parser_tool", ["path": .string("ok.yml")])
        #expect(!r.isToolError, "\(r.resultText)")
        #expect(r.firstText.contains("✅ Indentation check passed (no invalid tabs detected)."))
        #expect(r.firstText.contains("Root & Key Declarations (2)"))
    }

    @Test func yamlParserMissingFileFails() async throws {
        let sample = try TempSample()
        defer { sample.remove() }
        let host = try await opened(sample)
        let r = try await host.server.callTool("yaml_parser_tool", ["path": .string("nope.yml")])
        #expect(r.isToolError)
        #expect(r.firstText.contains("File not found at: nope.yml"))
    }

    @Test func yamlValidatePassesCleanFile() async throws {
        let sample = try TempSample()
        defer { sample.remove() }
        try writeFixture(sample, "ok.yml", "name: demo\nversion: 1\nitems:\n  - a\n  - b\n")
        let host = try await opened(sample)
        let r = try await host.server.callTool("yaml_validate", ["path": .string("ok.yml")])
        #expect(!r.isToolError, "\(r.resultText)")
        #expect(r.firstText.contains("YAML validation passed (heuristic — no full YAML parser) in ok.yml."))
        #expect(r.structured?["valid"]?.bool == true)
        #expect(r.structured?["heuristic"]?.bool == true)
        #expect(r.structured?["written"]?.bool == false)
    }

    @Test func yamlValidateRejectsTabsDuplicateKeysAndUnbalancedQuotes() async throws {
        let sample = try TempSample()
        defer { sample.remove() }
        try writeFixture(sample, "tab.yml", "name: demo\n\tbad: tab\n")
        try writeFixture(sample, "dup.yml", "name: one\nname: two\n")
        try writeFixture(sample, "quote.yml", "name: 'unclosed\n")
        try writeFixture(sample, "colon.yml", "name: demo\njust some words\n")
        try writeFixture(sample, "bracket.yml", "items: [a, b\n")
        let host = try await opened(sample)
        let tab = try await host.server.callTool("yaml_validate", ["path": .string("tab.yml")])
        #expect(tab.isToolError)
        #expect(tab.firstText.contains("tab used for indentation"))
        let dup = try await host.server.callTool("yaml_validate", ["path": .string("dup.yml")])
        #expect(dup.isToolError)
        #expect(dup.firstText.contains("duplicate top-level key 'name'"))
        let quote = try await host.server.callTool("yaml_validate", ["path": .string("quote.yml")])
        #expect(quote.isToolError)
        #expect(quote.firstText.contains("Unbalanced single quote opened at line 1."))
        let colon = try await host.server.callTool("yaml_validate", ["path": .string("colon.yml")])
        #expect(colon.isToolError)
        #expect(colon.firstText.contains("expected 'key: value' mapping (no colon found)"))
        let bracket = try await host.server.callTool("yaml_validate", ["path": .string("bracket.yml")])
        #expect(bracket.isToolError)
        #expect(bracket.firstText.contains("Unbalanced opening bracket '[' opened at line 1."))
    }

    @Test func yamlValidateFormatNormalizesIndentation() async throws {
        let sample = try TempSample()
        defer { sample.remove() }
        try writeFixture(sample, "wide.yml", "root:\n    child: 1\n    other: 2\n")
        let host = try await opened(sample)
        let preview = try await host.server.callTool("yaml_validate",
                                                     ["path": .string("wide.yml"), "action": .string("format")])
        #expect(!preview.isToolError, "\(preview.resultText)")
        #expect(preview.firstText.contains("Formatted preview returned without writing."))
        #expect(preview.structured?["written"]?.bool == false)
        #expect(preview.structured?["formatted"]?.string == "root:\n  child: 1\n  other: 2\n")
        #expect(try readFixture(sample, "wide.yml") == "root:\n    child: 1\n    other: 2\n")
        let written = try await host.server.callTool("yaml_validate",
                                                     ["path": .string("wide.yml"), "action": .string("format"),
                                                      "write": .string("true")])
        #expect(!written.isToolError, "\(written.resultText)")
        #expect(written.firstText.contains("Formatted YAML written back to the file."))
        #expect(try readFixture(sample, "wide.yml") == "root:\n  child: 1\n  other: 2\n")
    }

    @Test func yamlValidateFormatWriteRefusesInvalidFile() async throws {
        let sample = try TempSample()
        defer { sample.remove() }
        let original = "name: one\nname: two\n"
        try writeFixture(sample, "dup.yml", original)
        let host = try await opened(sample)
        let r = try await host.server.callTool("yaml_validate",
                                               ["path": .string("dup.yml"), "action": .string("format"),
                                                "write": .string("true")])
        #expect(r.isToolError)
        #expect(r.firstText.contains("YAML validation failed (heuristic — no full YAML parser)"))
        #expect(try readFixture(sample, "dup.yml") == original)
    }

    @Test func yamlValidateBadActionAndMissingFail() async throws {
        let sample = try TempSample()
        defer { sample.remove() }
        try writeFixture(sample, "a.yml", "a: 1\n")
        let host = try await opened(sample)
        let badAction = try await host.server.callTool("yaml_validate",
                                                       ["path": .string("a.yml"), "action": .string("explode")])
        #expect(badAction.isToolError)
        #expect(badAction.firstText.contains("Invalid action 'explode'. Allowed: validate, format."))
        let missing = try await host.server.callTool("yaml_validate", ["path": .string("nope.yml")])
        #expect(missing.isToolError)
        #expect(missing.firstText.contains("YAML validation requires an existing file: nope.yml"))
    }

    @Test func dataWritesRefusedWhenReadOnly() async throws {
        let sample = try TempSample()
        defer { sample.remove() }
        try writeFixture(sample, "a.json", "{\"b\": 2}")
        let host = try await opened(sample, policy: .readOnly)
        let r = try await host.server.callTool("json_validate", ["path": .string("a.json")])
        #expect(r.isToolError)
        #expect(r.firstText.contains("read-only"))
        #expect(try readFixture(sample, "a.json") == "{\"b\": 2}")
    }

    @Test func yamlParserAllowedWhenReadOnly() async throws {
        let sample = try TempSample()
        defer { sample.remove() }
        try writeFixture(sample, "ok.yml", "name: demo\n")
        let host = try await opened(sample, policy: .readOnly)
        let r = try await host.server.callTool("yaml_parser_tool", ["path": .string("ok.yml")])
        #expect(!r.isToolError, "\(r.resultText)")
        #expect(r.firstText.contains("✅ Indentation check passed"))
    }
}

import Foundation
import Testing
import YcodeAssistant
@testable import YcodeMCP

@MainActor
@Suite(.serialized) struct SwiftCodeArtifactsTests {
    func opened(_ sample: TempSample, policy: MCPWritePolicy = .readOnly) async throws -> SwiftCodeMCPHost {
        let host = SwiftCodeMCPHost()
        host.server.writePolicy = policy
        host.server.tools += host.artifactTools
        let r = try await host.server.callTool("workspace_open", ["path": .string(sample.url.path)])
        #expect(!r.isToolError, "\(r.resultText)")
        return host
    }

    final class Reviews: @unchecked Sendable {
        var changes: [MCPChange] = []
        var accept = false
    }

    func artifactNames(_ result: AnyJSON) -> [String] {
        result.structured?["artifacts"]?.array?.compactMap { $0["filename"]?.string } ?? []
    }

    @Test func toolsAreListedWithSchemasAndAnnotations() async throws {
        let sample = try TempSample()
        defer { sample.remove() }
        let host = try await opened(sample)
        #expect(host.artifactTools.map(\.name) == ["list_artifacts", "read_artifact", "create_artifact", "delete_artifact",
                                                   "file_backup", "open_in_finder", "reveal_in_finder"])
        let list = try await host.server.handle(method: "tools/list", params: nil, connection: MCPServer.Connection())
        let tools = list["tools"]?.array ?? []
        func listing(_ name: String) throws -> AnyJSON { try #require(tools.first { $0["name"] == name }) }
        func required(_ name: String) throws -> [String] {
            try listing(name)["inputSchema"]?["required"]?.array?.compactMap(\.string) ?? []
        }
        #expect(try required("list_artifacts") == [])
        #expect(try required("read_artifact") == ["name"])
        #expect(try required("create_artifact") == ["name", "content"])
        #expect(try required("delete_artifact") == ["name", "confirm"])
        #expect(try required("file_backup") == ["path"])
        #expect(try required("open_in_finder") == ["path"])
        #expect(try required("reveal_in_finder") == ["path"])
        #expect(try listing("create_artifact")["description"]?.string?.contains("The single way to produce durable deliverables.") == true)
        #expect(try listing("create_artifact")["inputSchema"]?["properties"]?["kind"]?["description"]?.string?.contains("execution_plan") == true)
        let create = try listing("create_artifact")
        #expect(create["annotations"]?["readOnlyHint"] == false && create["annotations"]?["idempotentHint"] == false)
        let delete = try listing("delete_artifact")
        #expect(delete["annotations"]?["readOnlyHint"] == false && delete["annotations"]?["destructiveHint"] == true)
        let backup = try listing("file_backup")
        #expect(backup["annotations"]?["readOnlyHint"] == false && backup["annotations"]?["idempotentHint"] == false)
        let finder = try listing("open_in_finder")
        #expect(finder["annotations"]?["readOnlyHint"] == true && finder["annotations"]?["idempotentHint"] == true
                && finder["annotations"]?["openWorldHint"] == true)
        #expect(try listing("read_artifact")["annotations"]?["readOnlyHint"] == true)
    }

    @Test func createListReadUpdateAppendDeleteRoundTrip() async throws {
        let sample = try TempSample()
        defer { sample.remove() }
        let host = try await opened(sample, policy: .allow)
        let empty = try await host.server.callTool("list_artifacts")
        #expect(!empty.isToolError && empty.structured?["count"]?.int == 0 && empty.resultText.contains("No artifacts yet"))

        let content = "# Round Trip\n\nBody.\n"
        let created = try await host.server.callTool("create_artifact", ["name": .string("round_trip"), "content": .string(content),
                                                                         "description": .string("A round trip.")])
        #expect(!created.isToolError, "\(created.resultText)")
        #expect(created.structured?["filename"]?.string == "round_trip.md" && created.structured?["title"]?.string == "Round Trip"
                && created.structured?["relativePath"]?.string == ".assist_temp/artifacts/round_trip.md"
                && created.structured?["mode"]?.string == "create" && created.structured?["kind"]?.string == "artifact"
                && created.structured?["contentLength"]?.int == content.count)
        #expect(sample.read(".assist_temp/artifacts/round_trip.md") == "# Round Trip\n\nBody.\n")
        #expect(sample.read(".assist_temp/artifacts/.artifacts_index.json").contains("round_trip.md"))

        let listed = try await host.server.callTool("list_artifacts")
        #expect(listed.structured?["count"]?.int == 1 && artifactNames(listed) == ["round_trip.md"])
        #expect(listed.structured?["artifacts"]?[0]?["title"] == "Round Trip"
                && listed.structured?["artifacts"]?[0]?["description"] == "A round trip.")
        #expect(listed.resultText.contains("[Artifact]"))

        let read = try await host.server.callTool("read_artifact", ["name": .string("round_trip")])
        #expect(read.structured?["filename"]?.string == "round_trip.md" && read.structured?["kind"]?.string == "artifact"
                && read.structured?["truncated"]?.bool == false && read.structured?["content"]?.string == "# Round Trip\n\nBody.\n")

        let updated = try await host.server.callTool("create_artifact", ["name": .string("round_trip"), "content": .string("# V2\n"),
                                                                         "mode": .string("update")])
        #expect(updated.structured?["mode"]?.string == "update" && sample.read(".assist_temp/artifacts/round_trip.md") == "# V2\n")

        let appended = try await host.server.callTool("create_artifact", ["name": .string("round_trip"), "content": .string("More."),
                                                                          "mode": .string("append")])
        #expect(appended.structured?["mode"]?.string == "append")
        #expect(sample.read(".assist_temp/artifacts/round_trip.md") == "# V2\n\nMore.\n")

        let deleted = try await host.server.callTool("delete_artifact", ["name": .string("round_trip"), "confirm": .bool(true)])
        #expect(deleted.structured?["filename"]?.string == "round_trip.md")
        #expect(!FileManager.default.fileExists(atPath: sample.path(".assist_temp/artifacts/round_trip.md")))
        #expect(!sample.read(".assist_temp/artifacts/.artifacts_index.json").contains("round_trip.md"))
        #expect(artifactNames(try await host.server.callTool("list_artifacts")).isEmpty)
    }

    @Test func kindInferenceAndExplicitKind() async throws {
        let sample = try TempSample()
        defer { sample.remove() }
        let host = try await opened(sample, policy: .allow)
        let inferred = try await host.server.callTool("create_artifact", ["name": .string("migration_plan"), "content": .string("Plan.\n")])
        #expect(inferred.structured?["kind"]?.string == "execution_plan", "\(inferred.resultText)")
        let explicit = try await host.server.callTool("create_artifact", ["name": .string("plain_note"), "content": .string("Note.\n"),
                                                                           "kind": .string("execution_plan")])
        #expect(explicit.structured?["kind"]?.string == "execution_plan")
        let wins = try await host.server.callTool("create_artifact", ["name": .string("other_plan"), "content": .string("Note.\n"),
                                                                      "kind": .string("artifact")])
        #expect(wins.structured?["kind"]?.string == "artifact")
        let bare = try await host.server.callTool("create_artifact", ["name": .string("airplane_notes"), "content": .string("Note.\n")])
        #expect(bare.structured?["kind"]?.string == "artifact")
    }

    @Test func createExistingFailsUpdateMissingFailsAppendCreates() async throws {
        let sample = try TempSample()
        defer { sample.remove() }
        let host = try await opened(sample, policy: .allow)
        let first = try await host.server.callTool("create_artifact", ["name": .string("once"), "content": .string("One.\n")])
        #expect(!first.isToolError)
        let again = try await host.server.callTool("create_artifact", ["name": .string("once"), "content": .string("Two.\n")])
        #expect(again.isToolError && again.resultText.contains("already exists"))
        #expect(sample.read(".assist_temp/artifacts/once.md") == "One.\n")
        let missing = try await host.server.callTool("create_artifact", ["name": .string("ghost"), "content": .string("Boo.\n"),
                                                                          "mode": .string("update")])
        #expect(missing.isToolError && missing.resultText.contains("No artifact named"))
        let appended = try await host.server.callTool("create_artifact", ["name": .string("ghost"), "content": .string("Boo.\n"),
                                                                          "mode": .string("append")])
        #expect(!appended.isToolError && sample.read(".assist_temp/artifacts/ghost.md") == "Boo.\n")
        let readMissing = try await host.server.callTool("read_artifact", ["name": .string("never_existed")])
        #expect(readMissing.isToolError && readMissing.resultText.contains("No artifact named"))
    }

    @Test func validationErrors() async throws {
        let sample = try TempSample()
        defer { sample.remove() }
        let host = try await opened(sample, policy: .allow)
        let badName = try await host.server.callTool("create_artifact", ["name": .string("bad name!"), "content": .string("x\n")])
        #expect(badName.isToolError && badName.resultText.contains("Invalid artifact name"))
        let empty = try await host.server.callTool("create_artifact", ["name": .string("empty"), "content": .string("   \n")])
        #expect(empty.isToolError && empty.resultText.contains("Artifact content is empty"))
        let badMode = try await host.server.callTool("create_artifact", ["name": .string("m"), "content": .string("x\n"),
                                                                         "mode": .string("replace")])
        #expect(badMode.isToolError && badMode.resultText.contains("Invalid mode"))
        let badKind = try await host.server.callTool("create_artifact", ["name": .string("k"), "content": .string("x\n"),
                                                                         "kind": .string("image")])
        #expect(badKind.isToolError && badKind.resultText.contains("Invalid kind"))
        let missingName = try await host.server.callTool("read_artifact")
        #expect(missingName.isToolError && missingName.resultText.contains("missing the required argument"))
    }

    @Test func deleteNeedsConfirmAndProtectsAgentNotes() async throws {
        let sample = try TempSample()
        defer { sample.remove() }
        try "# Agent Notes\n\nLive notes.\n".write(toFile: sample.path("agent_notes.md"), atomically: true, encoding: .utf8)
        let host = try await opened(sample, policy: .allow)
        let listed = try await host.server.callTool("list_artifacts")
        #expect(artifactNames(listed) == ["agent_notes.md"])
        #expect(listed.structured?["artifacts"]?[0]?["kind"] == "agent_notes"
                && listed.structured?["artifacts"]?[0]?["title"] == "Agent Notes")
        let read = try await host.server.callTool("read_artifact", ["name": .string("agent_notes")])
        #expect(!read.isToolError && read.structured?["content"]?.string?.contains("Live notes.") == true)

        let created = try await host.server.callTool("create_artifact", ["name": .string("doomed"), "content": .string("Doom.\n")])
        #expect(!created.isToolError)
        let unconfirmed = try await host.server.callTool("delete_artifact", ["name": .string("doomed"), "confirm": .bool(false)])
        #expect(unconfirmed.isToolError && unconfirmed.resultText.contains("confirm: true"))
        #expect(FileManager.default.fileExists(atPath: sample.path(".assist_temp/artifacts/doomed.md")))
        let missingConfirm = try await host.server.callTool("delete_artifact", ["name": .string("doomed")])
        #expect(missingConfirm.isToolError && missingConfirm.resultText.contains("missing the required argument"))
        #expect(FileManager.default.fileExists(atPath: sample.path(".assist_temp/artifacts/doomed.md")))

        let protected = try await host.server.callTool("delete_artifact", ["name": .string("agent_notes"), "confirm": .bool(true)])
        #expect(protected.isToolError && protected.resultText.contains("cannot be deleted"))
        #expect(FileManager.default.fileExists(atPath: sample.path("agent_notes.md")))
        let missing = try await host.server.callTool("delete_artifact", ["name": .string("ghost"), "confirm": .bool(true)])
        #expect(missing.isToolError && missing.resultText.contains("No artifact named"))
    }

    @Test func readOnlyPolicyRefusesWritesButNotReads() async throws {
        let sample = try TempSample()
        defer { sample.remove() }
        let host = try await opened(sample)
        let created = try await host.server.callTool("create_artifact", ["name": .string("x"), "content": .string("x\n")])
        #expect(created.isToolError && created.resultText.contains("read-only"))
        let backedUp = try await host.server.callTool("file_backup", ["path": .string("Package.swift")])
        #expect(backedUp.isToolError && backedUp.resultText.contains("read-only"))
        let deleted = try await host.server.callTool("delete_artifact", ["name": .string("x"), "confirm": .bool(true)])
        #expect(deleted.isToolError && deleted.resultText.contains("read-only"))
        #expect(!FileManager.default.fileExists(atPath: sample.path(".assist_temp/artifacts/x.md")))
        #expect(!FileManager.default.fileExists(atPath: sample.path(".assist_temp/backups")))
        let listed = try await host.server.callTool("list_artifacts")
        #expect(!listed.isToolError && listed.structured?["count"]?.int == 0)
    }

    @Test func reviewRejectsAndAcceptsWrites() async throws {
        let sample = try TempSample()
        defer { sample.remove() }
        let reviews = Reviews()
        let host = try await opened(sample, policy: .review { c in reviews.changes.append(c); return reviews.accept })
        let rejected = try await host.server.callTool("create_artifact", ["name": .string("reviewed"), "content": .string("Hi.\n")])
        #expect(rejected.isToolError && rejected.firstText == MCPServer.rejectedMessage)
        #expect(!FileManager.default.fileExists(atPath: sample.path(".assist_temp/artifacts/reviewed.md")))
        let change = try #require(reviews.changes.first)
        #expect(change.tool == "create_artifact" && change.relativePath == ".assist_temp/artifacts/reviewed.md"
                && change.original == nil && change.proposed == "Hi.\n")
        reviews.accept = true
        let created = try await host.server.callTool("create_artifact", ["name": .string("reviewed"), "content": .string("Hi.\n")])
        #expect(!created.isToolError, "\(created.resultText)")
        reviews.accept = false
        let deleteRejected = try await host.server.callTool("delete_artifact", ["name": .string("reviewed"), "confirm": .bool(true)])
        #expect(deleteRejected.isToolError && deleteRejected.firstText == MCPServer.rejectedMessage)
        #expect(FileManager.default.fileExists(atPath: sample.path(".assist_temp/artifacts/reviewed.md")))
        #expect(reviews.changes.last?.tool == "delete_artifact")
        let backupRejected = try await host.server.callTool("file_backup", ["path": .string("Package.swift")])
        #expect(backupRejected.isToolError && backupRejected.firstText == MCPServer.rejectedMessage)
        #expect(!FileManager.default.fileExists(atPath: sample.path(".assist_temp/backups")))
    }

    @Test func fileBackupRoundTrip() async throws {
        let sample = try TempSample()
        defer { sample.remove() }
        let host = try await opened(sample, policy: .allow)
        let sourceSize = (try? FileManager.default.attributesOfItem(atPath: sample.path("Package.swift")))?[.size] as? Int
        let backedUp = try await host.server.callTool("file_backup", ["path": .string("Package.swift")])
        #expect(!backedUp.isToolError, "\(backedUp.resultText)")
        #expect(backedUp.structured?["source"]?.string == "Package.swift" && backedUp.structured?["bytes"]?.int == sourceSize)
        let rel = try #require(backedUp.structured?["backup"]?.string)
        #expect(rel.hasPrefix(".assist_temp/backups/Package.swift.") && rel.hasSuffix(".bak"))
        #expect(!rel.contains(":"))
        let dstSize = (try? FileManager.default.attributesOfItem(atPath: sample.path(rel)))?[.size] as? Int
        #expect(dstSize == sourceSize)
        let missing = try await host.server.callTool("file_backup", ["path": .string("NoSuchFile.swift")])
        #expect(missing.isToolError && missing.resultText.contains("No file at path"))
        let outside = try await host.server.callTool("file_backup", ["path": .string("../../etc/hosts")])
        #expect(outside.isToolError && outside.resultText.contains("outside the workspace"))
    }

    @Test func readTruncatesLongArtifacts() async throws {
        let sample = try TempSample()
        defer { sample.remove() }
        let host = try await opened(sample, policy: .allow)
        let big = String(repeating: "x", count: 61_000)
        let created = try await host.server.callTool("create_artifact", ["name": .string("big"), "content": .string(big)])
        #expect(!created.isToolError)
        let read = try await host.server.callTool("read_artifact", ["name": .string("big")])
        #expect(read.structured?["truncated"]?.bool == true)
        let content = try #require(read.structured?["content"]?.string)
        #expect(content.hasPrefix(String(repeating: "x", count: 60_000)) && content.contains("truncated"))
    }

    @Test func finderTools() async throws {
        let sample = try TempSample()
        defer { sample.remove() }
        let host = try await opened(sample)
        let missingOpen = try await host.server.callTool("open_in_finder", ["path": .string("NoSuchFile.swift")])
        #expect(missingOpen.isToolError && missingOpen.resultText.contains("does not exist"))
        let missingReveal = try await host.server.callTool("reveal_in_finder", ["path": .string("NoSuchFile.swift")])
        #expect(missingReveal.isToolError && missingReveal.resultText.contains("does not exist"))
        let escape = try await host.server.callTool("open_in_finder", ["path": .string("../../etc/hosts")])
        #expect(escape.isToolError && escape.resultText.contains("outside the workspace"))
        #if !os(macOS)
        let open = try await host.server.callTool("open_in_finder", ["path": .string("Package.swift")])
        #expect(open.isToolError && open.resultText.contains("only available on macOS"))
        let reveal = try await host.server.callTool("reveal_in_finder", ["path": .string("Package.swift")])
        #expect(reveal.isToolError && reveal.resultText.contains("only available on macOS"))
        #endif
    }
}

import Foundation
import Testing
import SwiftCodeAssistant
@testable import SwiftCodeMCP

/// The ported Legacy memory / context tools (Wave 4, Memory slice),
/// each driven through the server's real write-policy path against a
/// copy of `Samples/AgentSamples/Greeter`.
@MainActor
@Suite(.serialized) struct SwiftCodeMemoryToolsTests {
    /// Opens a copy of Greeter and installs the memory tools on the
    /// server. (Wiring `memoryTools` into `installTools()` is the
    /// coordinator's integration step; the tests install them directly
    /// so the tools still run through `MCPServer.run`'s write-policy
    /// gate.)
    func opened(_ sample: TempSample, policy: MCPWritePolicy = .readOnly) async throws -> SwiftCodeMCPHost {
        let host = SwiftCodeMCPHost()
        host.server.writePolicy = policy
        host.server.tools += host.memoryTools
        let r = try await host.server.callTool("workspace_open", ["path": .string(sample.url.path)])
        #expect(!r.isToolError, "\(r.resultText)")
        return host
    }

    @Test func toolsAreListedWithSchemasAndAnnotations() async throws {
        let sample = try TempSample()
        defer { sample.remove() }
        let host = try await opened(sample)
        #expect(host.memoryTools.map(\.name) == ["mem_store", "mem_retrieve", "mem_clear", "mem_context_snapshot",
                                                 "context_persistence_store", "save_to_memory", "view_memory",
                                                 "manage_memory", "conversation_context_manager"])
        let list = try await host.server.handle(method: "tools/list", params: nil, connection: MCPServer.Connection())
        let tools = list["tools"]?.array ?? []
        func listing(_ name: String) throws -> AnyJSON { try #require(tools.first { $0["name"] == name }) }
        func required(_ name: String) throws -> [String] {
            try listing(name)["inputSchema"]?["required"]?.array?.compactMap(\.string) ?? []
        }
        #expect(try required("mem_store") == ["key", "value"])
        #expect(try required("mem_retrieve") == ["key"])
        #expect(try required("mem_clear") == [])
        #expect(try required("mem_context_snapshot") == [])
        #expect(try required("context_persistence_store") == ["key"])
        #expect(try required("save_to_memory") == ["key", "value"])
        #expect(try required("view_memory") == [])
        #expect(try required("manage_memory") == ["action"])
        #expect(try required("conversation_context_manager") == ["action"])
        // Catalogue §1.3 risk table: safeRead → read-only, safeMutation
        // → writes, potentiallyDestructive → writes + destructive.
        let store = try listing("mem_store")
        #expect(store["annotations"]?["readOnlyHint"] == false && store["annotations"]?["idempotentHint"] == true)
        let retrieve = try listing("mem_retrieve")
        #expect(retrieve["annotations"]?["readOnlyHint"] == true && retrieve["annotations"]?["idempotentHint"] == true)
        let clear = try listing("mem_clear")
        #expect(clear["annotations"]?["readOnlyHint"] == false && clear["annotations"]?["destructiveHint"] == true)
        // A fresh snapshot key per call: not idempotent.
        let snapshot = try listing("mem_context_snapshot")
        #expect(snapshot["annotations"]?["readOnlyHint"] == false && snapshot["annotations"]?["idempotentHint"] == false)
        // update_summary appends: not idempotent.
        let context = try listing("conversation_context_manager")
        #expect(context["annotations"]?["readOnlyHint"] == false && context["annotations"]?["idempotentHint"] == false)
        let view = try listing("view_memory")
        #expect(view["annotations"]?["readOnlyHint"] == true)
        #expect(try listing("mem_store")["description"]?.string == "Stores information in the long-term memory graph.")
        #expect(try listing("context_persistence_store")["inputSchema"]?["properties"]?["action"]?["description"]?.string?.contains("delete") == true)
    }

    @Test func sessionGraphStoreRetrieveClearRoundTrip() async throws {
        let sample = try TempSample()
        defer { sample.remove() }
        let host = try await opened(sample, policy: .allow)
        let missing = try await host.server.callTool("mem_retrieve", ["key": .string("nope")])
        #expect(missing.isToolError && missing.resultText.contains("Key not found in memory: nope"))

        let stored = try await host.server.callTool("mem_store", ["key": .string("ArchitectureStyle"), "value": .string("MVVM")])
        #expect(!stored.isToolError && stored.structured?["key"] == "ArchitectureStyle")
        #expect(stored.resultText.contains("Stored in memory: ArchitectureStyle"))

        // Overwrite: the latest value wins, like Legacy's graph.
        let overwritten = try await host.server.callTool("mem_store", ["key": .string("ArchitectureStyle"), "value": .string("TCA")])
        #expect(!overwritten.isToolError)
        let retrieved = try await host.server.callTool("mem_retrieve", ["key": .string("ArchitectureStyle")])
        #expect(retrieved.structured?["value"] == "TCA" && retrieved.resultText.contains("Retrieved from memory: ArchitectureStyle"))

        // Missing parameters fail with Legacy's messages.
        let noKey = try await host.server.callTool("mem_store", ["value": .string("x")])
        #expect(noKey.isToolError)
        let noValue = try await host.server.callTool("mem_store", ["key": .string("k")])
        #expect(noValue.isToolError)

        let cleared = try await host.server.callTool("mem_clear")
        #expect(!cleared.isToolError && cleared.structured?["cleared"] == true && cleared.structured?["entriesCleared"]?.int == 1)
        #expect(cleared.resultText.contains("Memory cleared."))
        let gone = try await host.server.callTool("mem_retrieve", ["key": .string("ArchitectureStyle")])
        #expect(gone.isToolError && gone.resultText.contains("Key not found in memory: ArchitectureStyle"))
    }

    @Test func sessionGraphIsWorkspaceConfined() async throws {
        let first = try TempSample()
        defer { first.remove() }
        let second = try TempSample()
        defer { second.remove() }
        let hostA = try await opened(first, policy: .allow)
        let stored = try await hostA.server.callTool("mem_store", ["key": .string("only_here"), "value": .string("yes")])
        #expect(!stored.isToolError)
        let hostB = try await opened(second, policy: .allow)
        let leaked = try await hostB.server.callTool("mem_retrieve", ["key": .string("only_here")])
        #expect(leaked.isToolError && leaked.resultText.contains("Key not found in memory: only_here"))
        // The first workspace still has it.
        let kept = try await hostA.server.callTool("mem_retrieve", ["key": .string("only_here")])
        #expect(kept.structured?["value"] == "yes")
    }

    @Test func contextSnapshotStoresMarkerInGraph() async throws {
        let sample = try TempSample()
        defer { sample.remove() }
        let host = try await opened(sample, policy: .allow)
        let snap = try await host.server.callTool("mem_context_snapshot")
        #expect(!snap.isToolError, "\(snap.resultText)")
        let key = try #require(snap.structured?["snapshot_key"]?.string)
        #expect(key.hasPrefix("context_snapshot:"))
        // SwiftCode has no snapshot store, so latest_snapshot is "none".
        #expect(snap.structured?["latest_snapshot"] == "none")
        // The marker is a real graph entry, retrievable as stored.
        let back = try await host.server.callTool("mem_retrieve", ["key": .string(key)])
        let payload = try #require(back.structured?["value"]?.string)
        #expect(payload.contains("session=") && payload.contains("workspace=\(sample.url.path)") && payload.contains("latest_snapshot=none"))
    }

    @Test func contextStoreSetGetDeleteRoundTrip() async throws {
        let sample = try TempSample()
        defer { sample.remove() }
        let host = try await opened(sample, policy: .allow)
        // A missing key reads as "" (Legacy's `db[key] ?? ""`).
        let empty = try await host.server.callTool("context_persistence_store", ["key": .string("focus")])
        #expect(!empty.isToolError && empty.structured?["value"] == "" && empty.resultText.contains("Retrieved context for key focus"))

        let set = try await host.server.callTool("context_persistence_store",
                                                 ["key": .string("focus"), "action": .string("set"), "value": .string("editor")])
        #expect(!set.isToolError && set.structured?["value"] == "editor")
        #expect(set.resultText.contains("Stored context for key focus"))
        #expect(sample.read(".assist_context_store.json").contains("\"focus\""))

        let got = try await host.server.callTool("context_persistence_store", ["key": .string("focus"), "action": .string("get")])
        #expect(got.structured?["value"] == "editor")

        // An unknown action falls through to a get, like Legacy's
        // default case.
        let unknown = try await host.server.callTool("context_persistence_store", ["key": .string("focus"), "action": .string("bogus")])
        #expect(!unknown.isToolError && unknown.structured?["value"] == "editor")

        let deleted = try await host.server.callTool("context_persistence_store", ["key": .string("focus"), "action": .string("delete")])
        #expect(!deleted.isToolError && deleted.resultText.contains("Deleted key focus"))
        #expect(!sample.read(".assist_context_store.json").contains("focus"))
        let gone = try await host.server.callTool("context_persistence_store", ["key": .string("focus")])
        #expect(gone.structured?["value"] == "")

        // Legacy's failure messages.
        let noKey = try await host.server.callTool("context_persistence_store", ["action": .string("get")])
        #expect(noKey.isToolError)
        let noValue = try await host.server.callTool("context_persistence_store", ["key": .string("k"), "action": .string("set")])
        #expect(noValue.isToolError)
    }

    @Test func contextStoreEscapesValues() async throws {
        let sample = try TempSample()
        defer { sample.remove() }
        let host = try await opened(sample, policy: .allow)
        let tricky = "quote \" backslash \\ newline\nunicode \u{1F600}"
        let set = try await host.server.callTool("context_persistence_store",
                                                 ["key": .string("tricky"), "action": .string("set"), "value": .string(tricky)])
        #expect(!set.isToolError, "\(set.resultText)")
        let got = try await host.server.callTool("context_persistence_store", ["key": .string("tricky")])
        #expect(got.structured?["value"] == tricky)
    }

    @Test func durableMemorySaveViewManageRoundTrip() async throws {
        let sample = try TempSample()
        defer { sample.remove() }
        let host = try await opened(sample, policy: .allow)
        let empty = try await host.server.callTool("view_memory")
        #expect(!empty.isToolError && empty.structured?["count"] == 0
                && empty.resultText.contains("No memories are currently stored in UserMemory.md."))

        let saved = try await host.server.callTool("save_to_memory",
                                                   ["key": .string("ArchitectureStyle"), "value": .string("MVVM + Observation"),
                                                    "category": .string("Preferences")])
        #expect(!saved.isToolError, "\(saved.resultText)")
        #expect(saved.structured?["category"] == "Preferences")
        #expect(saved.resultText.contains("Saved to memory [Preferences]: **ArchitectureStyle** = MVVM + Observation"))
        #expect(saved.resultText.contains("Persisted to .assist_temp/memory/UserMemory.md"))
        let file = sample.read(".assist_temp/memory/UserMemory.md")
        #expect(file.contains("# User Memory & Durable Context") && file.contains("## Preferences")
                && file.contains("- **ArchitectureStyle**: MVVM + Observation <!-- updated: "))

        // Default category is General, and the key match is
        // case-insensitive on edit (Legacy's saveMemory upsert).
        let second = try await host.server.callTool("save_to_memory",
                                                    ["key": .string("ConcurrencyRule"), "value": .string("Swift 6 strict")])
        #expect(second.structured?["category"] == "General")
        let edited = try await host.server.callTool("manage_memory",
                                                    ["action": .string("edit"), "key": .string("architecturestyle"),
                                                     "value": .string("TCA"), "category": .string("Architecture")])
        #expect(!edited.isToolError && edited.resultText.contains("Memory 'architecturestyle' successfully updated in UserMemory.md."))

        let all = try await host.server.callTool("view_memory")
        #expect(all.structured?["count"] == 2 && all.resultText.contains("### Active User Memories (2 items):"))
        #expect(all.resultText.contains("- [Architecture] **ArchitectureStyle**: TCA"))
        let byCategory = try await host.server.callTool("view_memory", ["category": .string("general")])
        #expect(byCategory.structured?["count"] == 1)
        let byQuery = try await host.server.callTool("view_memory", ["query": .string("swift 6")])
        #expect(byQuery.structured?["count"] == 1)
        let noMatch = try await host.server.callTool("view_memory", ["query": .string("zzz-no-such-memory")])
        #expect(noMatch.structured?["count"] == 0 && noMatch.resultText.contains("No memory items matched the filter. Full UserMemory.md:"))

        // Delete is case-insensitive; deleting twice fails the second time.
        let deleted = try await host.server.callTool("manage_memory", ["action": .string("delete"), "key": .string("CONCURRENCYRULE")])
        #expect(!deleted.isToolError && deleted.resultText.contains("Memory entry 'CONCURRENCYRULE' deleted from UserMemory.md."))
        let again = try await host.server.callTool("manage_memory", ["action": .string("delete"), "key": .string("ConcurrencyRule")])
        #expect(again.isToolError && again.resultText.contains("was not found in UserMemory.md."))

        // manage_memory failures carry Legacy's messages.
        let missingAction = try await host.server.callTool("manage_memory", ["key": .string("k")])
        #expect(missingAction.isToolError)
        let unknown = try await host.server.callTool("manage_memory", ["action": .string("explode")])
        #expect(unknown.isToolError && unknown.resultText.contains("Unknown action 'explode'"))
        let addNoValue = try await host.server.callTool("manage_memory", ["action": .string("add"), "key": .string("k")])
        #expect(addNoValue.isToolError && addNoValue.resultText.contains("require both 'key' and 'value'"))

        let cleared = try await host.server.callTool("manage_memory", ["action": .string("clear")])
        #expect(!cleared.isToolError && cleared.resultText.contains("All memories cleared from UserMemory.md."))
        #expect(sample.read(".assist_temp/memory/UserMemory.md").contains("# User Memory & Durable Context"))
        // After a clear the file holds only the header, so Legacy's
        // view falls back to printing the whole (header-only) file.
        let afterClear = try await host.server.callTool("view_memory")
        #expect(afterClear.structured?["count"] == 0
                && afterClear.resultText.contains("No memory items matched the filter. Full UserMemory.md:"))
    }

    @Test func durableMemoryIsWorkspaceConfined() async throws {
        let first = try TempSample()
        defer { first.remove() }
        let second = try TempSample()
        defer { second.remove() }
        let hostA = try await opened(first, policy: .allow)
        let saved = try await hostA.server.callTool("save_to_memory", ["key": .string("OnlyHere"), "value": .string("yes")])
        #expect(!saved.isToolError)
        let hostB = try await opened(second, policy: .allow)
        let viewed = try await hostB.server.callTool("view_memory")
        #expect(viewed.structured?["count"] == 0)
        #expect(!FileManager.default.fileExists(atPath: second.path(".assist_temp/memory/UserMemory.md")))
    }

    @Test func conversationContextReadUpdateRoundTrip() async throws {
        let sample = try TempSample()
        defer { sample.remove() }
        let host = try await opened(sample, policy: .allow)
        let empty = try await host.server.callTool("conversation_context_manager", ["action": .string("read")])
        #expect(!empty.isToolError && empty.resultText.contains("No custom context file found yet for the active conversation."))

        let updated = try await host.server.callTool("conversation_context_manager",
                                                     ["action": .string("update_summary"), "notes": .string("We chose MVVM.")])
        #expect(!updated.isToolError, "\(updated.resultText)")
        #expect(updated.resultText.contains("Successfully updated conversation context file at: "))
        let file = sample.read(".assist_temp/memory/conversation_context.md")
        #expect(file.contains("# Conversation Context") && file.contains("### Additional Model Context (Updated ")
                && file.contains("We chose MVVM."))

        let read = try await host.server.callTool("conversation_context_manager", ["action": .string("read")])
        #expect(read.resultText.contains("Conversation Context:") && read.resultText.contains("We chose MVVM."))

        // A second update appends a second section (not idempotent).
        let again = try await host.server.callTool("conversation_context_manager",
                                                   ["action": .string("update_summary"), "notes": .string("And TCA for the new screen.")])
        #expect(!again.isToolError)
        let file2 = sample.read(".assist_temp/memory/conversation_context.md")
        #expect(file2.contains("We chose MVVM.") && file2.contains("And TCA for the new screen."))

        // Legacy's failure messages.
        let noNotes = try await host.server.callTool("conversation_context_manager", ["action": .string("update_summary")])
        #expect(noNotes.isToolError && noNotes.resultText.contains("requires non-empty 'notes'"))
        let unknown = try await host.server.callTool("conversation_context_manager", ["action": .string("explode")])
        #expect(unknown.isToolError && unknown.resultText.contains("Unsupported action 'explode'"))
        let missing = try await host.server.callTool("conversation_context_manager", [:])
        #expect(missing.isToolError)
    }

    @Test func writeToolsAreRefusedWhenReadOnly() async throws {
        let sample = try TempSample()
        defer { sample.remove() }
        let host = try await opened(sample) // default policy: .readOnly
        for (name, args) in [("mem_store", ["key": .string("k"), "value": .string("v")]),
                             ("mem_clear", [:]),
                             ("mem_context_snapshot", [:]),
                             ("context_persistence_store", ["key": .string("k"), "action": .string("set"), "value": .string("v")]),
                             ("save_to_memory", ["key": .string("k"), "value": .string("v")]),
                             ("manage_memory", ["action": .string("clear")]),
                             ("conversation_context_manager", ["action": .string("update_summary"), "notes": .string("n")])] {
            let r = try await host.server.callTool(name, args)
            #expect(r.isToolError && r.resultText.contains("read-only"), "\(name): \(r.resultText)")
        }
        // Reads still work when read-only.
        let retrieved = try await host.server.callTool("mem_retrieve", ["key": .string("k")])
        #expect(retrieved.isToolError && retrieved.resultText.contains("Key not found in memory: k"))
        let viewed = try await host.server.callTool("view_memory")
        #expect(!viewed.isToolError && viewed.resultText.contains("No memories are currently stored"))
    }
}

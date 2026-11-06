import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import Testing
import YcodeAssistant
@testable import YcodeMCP

@Suite struct MCPServerTests {
    /// A server with an echo tool and a write tool.
    static func server(policy: MCPWritePolicy = .readOnly) -> MCPServer {
        let s = MCPServer(name: "t", version: "1", instructions: "Use the tools.")
        s.tools = [
            MCPTool(name: "echo", title: "Echo", description: "Echoes.",
                    inputSchema: ["type": "object", "properties": ["text": ["type": "string"], "times": ["type": "integer"]],
                                  "required": ["text"], "additionalProperties": false]) { call in
                .structured(["text": .string(String(repeating: call.string("text") ?? "", count: call.int("times") ?? 1))])
            },
            MCPTool(name: "write", title: "Write", description: "Writes.", inputSchema: ["type": "object", "properties": [:]],
                    annotations: MCPToolAnnotations(readOnly: false), writes: true) { call in
                let ok = await call.approve(MCPChange(tool: "write", path: "/w/a", relativePath: "a", original: nil, proposed: "x", summary: "Create a"))
                return ok ? .text("written") : .error(MCPServer.rejectedMessage)
            },
        ]
        s.prompts = [MCPPrompt(name: "p", title: "P", description: "d", arguments: [.init("x", "an x", required: true)]) { "do \($0["x"] ?? "")" }]
        s.writePolicy = policy
        return s
    }

    @Test func initializeNegotiatesALegacyRevision() async throws {
        let s = Self.server()
        let c = MCPServer.Connection()
        let r = try await s.handle(method: "initialize", params: ["protocolVersion": "2025-06-18", "capabilities": [:], "clientInfo": ["name": "c", "version": "1"]],
                                   connection: c)
        #expect(r["protocolVersion"] == "2025-06-18")
        #expect(r["serverInfo"]?["name"] == "t" && r["instructions"] == "Use the tools.")
        #expect(r["capabilities"]?["tools"] != nil && r["capabilities"]?["prompts"] != nil)
        #expect(c.legacyVersion == "2025-06-18")
        // An unknown version: the newest legacy revision; no resultType on legacy results.
        let r2 = try await s.handle(method: "initialize", params: ["protocolVersion": "2024-01-01"], connection: c)
        #expect(r2["protocolVersion"] == "2025-11-25" && r2["resultType"] == nil)
    }

    @Test func modernRequestsCarryTheirVersionAndGetResultTypes() async throws {
        let s = Self.server()
        let c = MCPServer.Connection()
        let d = try await s.handle(method: "server/discover", params: ["_meta": modernMeta], connection: c)
        #expect(d["supportedVersions"]?.array?.first == .string(MCPServer.modernVersion))
        #expect(d["resultType"] == "complete" && d["_meta"]?[MCPServer.serverInfoKey]?["name"] == "t")
        let list = try await s.handle(method: "tools/list", params: ["_meta": modernMeta], connection: c)
        #expect(list["resultType"] == "complete" && list["tools"]?.array?.count == 2)
        // Unsupported version: -32022 with the supported list.
        do {
            _ = try await s.handle(method: "tools/list", params: ["_meta": [MCPServer.protocolVersionKey: "1900-01-01", MCPServer.clientCapabilitiesKey: [:]]],
                                   connection: c)
            Issue.record("accepted 1900-01-01")
        } catch let e as JSONRPCError {
            #expect(e.code == -32022 && e.data?["requested"] == "1900-01-01")
            #expect(e.data?["supported"]?.array?.contains(.string("2025-11-25")) == true)
        }
        // Missing client capabilities: invalid params.
        await #expect(throws: JSONRPCError.self) {
            try await s.handle(method: "tools/list", params: ["_meta": [MCPServer.protocolVersionKey: .string(MCPServer.modernVersion)]], connection: c)
        }
        await #expect(throws: JSONRPCError.methodNotFound("nope")) { try await s.handle(method: "nope", params: nil, connection: c) }
    }

    @Test func toolCallsValidateArgumentsAndReportToolErrors() async throws {
        let s = Self.server()
        let ok = try await s.callTool("echo", ["text": "ab", "times": 2])
        #expect(ok.structured?["text"] == "abab" && !ok.isToolError && ok.resultText.contains("abab"))
        let missing = try await s.callTool("echo", [:])
        #expect(missing.isToolError && missing.resultText.contains("missing the required argument \"text\""))
        let wrongType = try await s.callTool("echo", ["text": 3])
        #expect(wrongType.isToolError && wrongType.resultText.contains("must be of type string"))
        let unknownArg = try await s.callTool("echo", ["text": "a", "loud": true])
        #expect(unknownArg.isToolError && unknownArg.resultText.contains("unknown argument"))
        await #expect(throws: JSONRPCError.self) { try await s.callTool("missing") }
    }

    @Test func writesFollowThePolicy() async throws {
        let ro = try await Self.server(policy: .readOnly).callTool("write")
        #expect(ro.isToolError && ro.resultText.contains("read-only") && ro.resultText.contains("--allow-writes"))
        let allowed = try await Self.server(policy: .allow).callTool("write")
        #expect(allowed.firstText == "written")
        final class Seen: @unchecked Sendable { var changes: [MCPChange] = [] }
        let seen = Seen()
        let approved = try await Self.server(policy: .review { c in seen.changes.append(c); return true }).callTool("write")
        #expect(approved.firstText == "written" && seen.changes.first?.summary == "Create a")
        let rejected = try await Self.server(policy: .review { _ in false }).callTool("write")
        #expect(rejected.isToolError && rejected.firstText == MCPServer.rejectedMessage)
    }

    @Test func promptsAndMissingResources() async throws {
        let s = Self.server()
        let c = MCPServer.Connection()
        let p = try await s.handle(method: "prompts/get", params: ["name": "p", "arguments": ["x": "it"]], connection: c)
        #expect(p["messages"]?[0]?["content"]?["text"] == "do it")
        await #expect(throws: JSONRPCError.self) { try await s.handle(method: "prompts/get", params: ["name": "p"], connection: c) }
        // No resource source: an empty list; reading fails with the era's code.
        #expect(try await s.handle(method: "resources/list", params: nil, connection: c)["resources"] == [])
        do {
            _ = try await s.handle(method: "resources/read", params: ["uri": "file:///x"], connection: c)
        } catch let e as JSONRPCError { #expect(e.code == -32002) }
        do {
            _ = try await s.handle(method: "resources/read", params: ["uri": "file:///x", "_meta": modernMeta], connection: c)
        } catch let e as JSONRPCError { #expect(e.code == -32602) }
    }

    @MainActor
    @Test func everyYcodeToolHasAValidSchema() throws {
        let host = YcodeMCPHost()
        let tools = host.server.tools
        #expect(tools.count >= 25)
        #expect(Set(tools.map(\.name)).count == tools.count)
        let expected = ["workspace_open", "workspace_describe", "file_list", "file_read", "search", "issues", "build_settings",
                        "symbol_search", "build", "test", "clean", "build_log", "run", "run_output", "stop",
                        "simulator_list", "simulator_boot", "simulator_launch_app", "simulator_shutdown",
                        "simulator_screenshot", "simulator_logs", "preview_list", "preview_render",
                        "strings_catalogs", "strings_list", "strings_set", "file_write", "file_edit", "complete",
                        "dir_read", "dir_pwd", "dir_cd", "dir_size_report", "file_metadata", "file_head_preview",
                        "count_file_lines", "tree_view", "file_compare_diff", "file_checksum_verifier",
                        "file_hash_verify", "file_type_breakdown", "find_duplicate_files", "empty_dirs_find",
                        "executable_files_scan", "symlink_audit", "list_artifacts", "read_artifact",
                        "create_artifact", "delete_artifact", "file_backup", "open_in_finder", "reveal_in_finder",
                        "file_create", "file_append", "file_copy", "file_move", "file_rename", "file_delete",
                        "dir_create", "dir_delete", "code_replace", "code_insert", "code_multi_edit",
                        "code_refactor", "code_format", "code_generate", "format_json_file", "csv_to_json",
                        "json_to_csv", "plist_to_json", "json_to_plist", "batch_rename_files",
                        "generate_file_checksum", "plist_edit", "regex_replace_in_files", "call_hierarchy",
                        "code_summary", "dependency_graph", "extract_code_symbols", "import_graph",
                        "protocol_conformance_list", "search_regex", "search_skills", "search_symbol", "search_text",
                        "semantic_query_engine", "source_graph_builder", "symbol_move_file",
                        "symbol_reference_graph", "symbol_rename_project", "type_hierarchy", "conflict_marker_scan",
                        "git_bisect", "git_blame_inspector", "git_branch_compare", "git_branch_manager",
                        "git_cherry_pick", "git_conflict_resolver", "git_log_viewer", "git_pr_summary",
                        "git_stash_operator", "github_repo", "recent_changes", "version_control_operator",
                        "use_terminal", "task_runner", "env_capture_logs", "env_info", "use_mcp", "use_extension",
                        "use_composio", "use_workers", "environment_variable_manager", "clipboard_manager_tool",
                        "process_monitor_tool", "disk_space_analyzer", "system_notification_tool", "use_system",
                        "take_screenshot", "take_screenrecord", "use_app", "mem_store", "mem_retrieve", "mem_clear",
                        "mem_context_snapshot", "context_persistence_store", "save_to_memory", "view_memory",
                        "manage_memory", "conversation_context_manager", "execution_plan", "intel_plan_task",
                        "intel_breakdown_task", "intel_autofix", "intel_explain_code", "intel_generate_tests",
                        "plan-AskUser", "report_to_user", "artboard_compile", "artboard_create", "artboard_delete",
                        "artboard_get", "artboard_list", "artboard_run_app", "artboard_update", "fix_artboards",
                        "device_list", "simulator_controller", "image_convert_format", "image_decode_base64",
                        "image_encode_base64", "image_extract_metadata", "image_generate_thumbnail",
                        "image_get_dimensions", "svg_to_png", "gzip_compress_file", "gzip_decompress_file",
                        "tar_archive_create", "tar_archive_extract", "unzip_file", "zip_file",
                        "binary_plist_converter", "json_validate", "json_validator_tool", "yaml_parser_tool",
                        "yaml_validate", "code_mutation_engine", "dependency_resolution_engine",
                        "external_resource_gateway", "patch_application_engine", "fetch_documentation",
                        "reverse_analyze"]
        #expect(tools.map(\.name) == expected)
        for t in tools {
            let l = t.listing
            #expect(l["inputSchema"]?["type"] == "object", "\(t.name)")
            let props = l["inputSchema"]?["properties"]?.object ?? [:]
            for r in l["inputSchema"]?["required"]?.array?.compactMap(\.string) ?? [] { #expect(props[r] != nil, "\(t.name).\(r)") }
            for (k, v) in props { #expect(v["type"] != nil && v["description"]?.string?.isEmpty == false, "\(t.name).\(k)") }
            // `plan-AskUser` is the one documented exception to snake_case:
            // Legacy's registry keeps the hyphenated ID by design.
            #expect(t.name == "plan-AskUser" || t.name.range(of: "^[a-z_]+$", options: .regularExpression) != nil)
            #expect(!t.description.isEmpty && !t.title.isEmpty)
            if let o = l["outputSchema"] { #expect(o["type"] == "object", "\(t.name)") }
            #expect(l["annotations"]?["readOnlyHint"] == .bool(!t.writes && t.annotations.readOnly))
        }
        #expect(Set(tools.filter(\.writes).map(\.name)) == ["strings_set", "file_write", "file_edit", "create_artifact", "delete_artifact", "file_backup", "file_create",
                                                           "file_append", "file_copy", "file_move", "file_rename",
                                                           "file_delete", "dir_create", "dir_delete", "code_replace",
                                                           "code_insert", "code_multi_edit", "code_refactor",
                                                           "code_format", "code_generate", "format_json_file",
                                                           "csv_to_json", "json_to_csv", "plist_to_json",
                                                           "json_to_plist", "batch_rename_files", "plist_edit",
                                                           "regex_replace_in_files", "symbol_move_file",
                                                           "symbol_rename_project", "git_bisect",
                                                           "git_branch_manager", "git_cherry_pick",
                                                           "git_conflict_resolver", "git_stash_operator",
                                                           "version_control_operator", "use_terminal", "task_runner",
                                                           "use_mcp", "use_extension", "use_composio", "use_workers",
                                                           "environment_variable_manager", "clipboard_manager_tool",
                                                           "use_system", "take_screenshot", "use_app", "mem_store",
                                                           "mem_clear", "mem_context_snapshot",
                                                           "context_persistence_store", "save_to_memory",
                                                           "manage_memory", "conversation_context_manager",
                                                           "execution_plan", "intel_autofix", "intel_generate_tests",
                                                           "artboard_compile", "artboard_create", "artboard_delete",
                                                           "artboard_run_app", "artboard_update", "fix_artboards",
                                                           "simulator_controller", "image_convert_format",
                                                           "image_decode_base64", "image_generate_thumbnail",
                                                           "svg_to_png", "gzip_compress_file",
                                                           "gzip_decompress_file", "tar_archive_create",
                                                           "tar_archive_extract", "unzip_file", "zip_file",
                                                           "binary_plist_converter", "json_validate",
                                                           "json_validator_tool", "yaml_validate",
                                                           "code_mutation_engine", "dependency_resolution_engine",
                                                           "external_resource_gateway", "patch_application_engine"])
    }
}

@Suite struct MCPHTTPTests {
    static func post(_ t: MCPHTTPTransport, _ body: AnyJSON, headers: [String: String] = [:], token: String? = nil,
                     accept: String = "application/json, text/event-stream") async throws -> (Int, String, [String: String]) {
        var r = URLRequest(url: URL(string: t.endpoint)!)
        r.httpMethod = "POST"
        r.httpBody = body.data()
        r.setValue("application/json", forHTTPHeaderField: "Content-Type")
        r.setValue(accept, forHTTPHeaderField: "Accept")
        r.setValue("Bearer \(token ?? t.token)", forHTTPHeaderField: "Authorization")
        for (k, v) in headers { r.setValue(v, forHTTPHeaderField: k) }
        let (data, response) = try await URLSession.shared.data(for: r)
        let h = response as? HTTPURLResponse
        var out: [String: String] = [:]
        for (k, v) in h?.allHeaderFields ?? [:] { out[String(describing: k).lowercased()] = String(describing: v) }
        return (h?.statusCode ?? 0, String(decoding: data, as: UTF8.self), out)
    }

    static func modernHeaders(_ method: String, name: String? = nil) -> [String: String] {
        var h = ["MCP-Protocol-Version": MCPServer.modernVersion, "Mcp-Method": method]
        if let name { h["Mcp-Name"] = name }
        return h
    }

    @Test func authorizationOriginAndMethods() async throws {
        let t = try MCPHTTPTransport(server: MCPServerTests.server())
        defer { t.stop() }
        #expect(t.endpoint.hasPrefix("http://127.0.0.1:"))
        let ping: AnyJSON = ["jsonrpc": "2.0", "id": 1, "method": "ping"]
        #expect(try await Self.post(t, ping, token: "wrong").0 == 401)
        #expect(try await Self.post(t, ping, headers: ["Origin": "https://evil.example"]).0 == 403)
        #expect(try await Self.post(t, ping, headers: ["Origin": "http://localhost:3000"]).0 == 200)
        var get = URLRequest(url: URL(string: t.endpoint)!)
        get.setValue("Bearer \(t.token)", forHTTPHeaderField: "Authorization")
        let (_, gr) = try await URLSession.shared.data(for: get)
        #expect((gr as? HTTPURLResponse)?.statusCode == 405)
        // A notification: 202, no body.
        #expect(try await Self.post(t, ["jsonrpc": "2.0", "method": "notifications/initialized"]).0 == 202)
    }

    @Test func legacyAndModernRequests() async throws {
        let t = try MCPHTTPTransport(server: MCPServerTests.server())
        defer { t.stop() }
        let (s1, b1, _) = try await Self.post(t, ["jsonrpc": "2.0", "id": 1, "method": "initialize", "params": ["protocolVersion": "2025-11-25"]],
                                              headers: ["MCP-Protocol-Version": "2025-11-25"])
        #expect(s1 == 200 && b1.contains("\"protocolVersion\":\"2025-11-25\""))
        let call: AnyJSON = ["jsonrpc": "2.0", "id": 2, "method": "tools/call", "params": ["name": "echo", "arguments": ["text": "hi"], "_meta": modernMeta]]
        let (s2, b2, _) = try await Self.post(t, call, headers: Self.modernHeaders("tools/call", name: "echo"))
        #expect(s2 == 200)
        let r2 = try AnyJSON.parse(b2)
        #expect(r2["result"]?["structuredContent"]?["text"] == "hi" && r2["result"]?["resultType"] == "complete")
        // Headers must match the body; a base64 Mcp-Name is decoded first.
        #expect(try await Self.post(t, call, headers: Self.modernHeaders("tools/call", name: "other")).0 == 400)
        #expect(try await Self.post(t, call, headers: Self.modernHeaders("tools/call", name: "=?base64?ZWNobw==?=")).0 == 200)
        var wrongVersion = Self.modernHeaders("tools/call", name: "echo")
        wrongVersion["MCP-Protocol-Version"] = "2025-11-25"
        let (s3, b3, _) = try await Self.post(t, call, headers: wrongVersion)
        #expect(s3 == 400 && b3.contains("-32020"))
        // Unknown method (modern): 404 with -32601; unsupported version: 400 with -32022.
        let (s4, b4, _) = try await Self.post(t, ["jsonrpc": "2.0", "id": 3, "method": "nope", "params": ["_meta": modernMeta]],
                                              headers: Self.modernHeaders("nope"))
        #expect(s4 == 404 && b4.contains("-32601"))
        let old: AnyJSON = [MCPServer.protocolVersionKey: "1900-01-01", MCPServer.clientCapabilitiesKey: [:]]
        let (s5, b5, _) = try await Self.post(t, ["jsonrpc": "2.0", "id": 4, "method": "tools/list", "params": ["_meta": old]],
                                              headers: ["MCP-Protocol-Version": "1900-01-01", "Mcp-Method": "tools/list"])
        #expect(s5 == 400 && b5.contains("-32022"))
    }

    @Test func progressStreamsAsServerSentEvents() async throws {
        let s = MCPServer()
        s.tools = [MCPTool(name: "slow", title: "Slow", description: "Reports progress.", inputSchema: ["type": "object", "properties": [:]]) { call in
            for i in 1...3 { call.progress.report(Double(i), total: 3, message: "step \(i)") }
            return .text("done")
        }]
        let t = try MCPHTTPTransport(server: s)
        defer { t.stop() }
        var meta = modernMeta
        meta = meta.setting("progressToken", "tok")
        let (status, body, headers) = try await Self.post(t, ["jsonrpc": "2.0", "id": 9, "method": "tools/call", "params": ["name": "slow", "_meta": meta]],
                                                          headers: Self.modernHeaders("tools/call", name: "slow"))
        #expect(status == 200 && headers["content-type"]?.hasPrefix("text/event-stream") == true)
        let events = body.components(separatedBy: "\n").filter { $0.hasPrefix("data: ") }.compactMap { try? AnyJSON.parse(String($0.dropFirst(6))) }
        #expect(events.count == 4)
        #expect(events.prefix(3).allSatisfy { $0["method"] == "notifications/progress" && $0["params"]?["progressToken"] == "tok" })
        #expect(events[2]["params"]?["message"] == "step 3" && events[2]["params"]?["total"]?.double == 3)
        #expect(events[3]["id"] == 9 && events[3]["result"]?["content"]?[0]?["text"] == "done")
    }
}

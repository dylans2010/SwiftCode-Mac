import Foundation
import SwiftCodeAssistant

public struct MCPToolAnnotations: Sendable, Equatable {
    public var readOnly: Bool
    public var destructive: Bool
    public var idempotent: Bool
    public var openWorld: Bool
    public init(readOnly: Bool, destructive: Bool = false, idempotent: Bool = false, openWorld: Bool = false) {
        self.readOnly = readOnly
        self.destructive = destructive
        self.idempotent = idempotent
        self.openWorld = openWorld
    }
    public static let read = MCPToolAnnotations(readOnly: true, idempotent: true)
}

public struct MCPProgress: Sendable {
    let sink: (@Sendable (_ progress: Double, _ total: Double?, _ message: String?) -> Void)?
    public init(_ sink: (@Sendable (Double, Double?, String?) -> Void)?) { self.sink = sink }
    public static let none = MCPProgress(nil)
    public var isRequested: Bool { sink != nil }
    public func report(_ progress: Double, total: Double? = nil, message: String? = nil) { sink?(progress, total, message) }
}

public struct MCPChange: Sendable, Equatable {
    public var tool: String
    public var path: String
    public var relativePath: String
    public var original: String?
    public var proposed: String
    public var summary: String
    public var caller: MCPToolCaller?
    public init(tool: String, path: String, relativePath: String, original: String?, proposed: String, summary: String,
                caller: MCPToolCaller? = nil) {
        self.tool = tool
        self.path = path
        self.relativePath = relativePath
        self.original = original
        self.proposed = proposed
        self.summary = summary
        self.caller = caller
    }

    public func settingCaller(_ caller: MCPToolCaller?) -> MCPChange {
        var copy = self
        copy.caller = caller
        return copy
    }
}

public struct MCPToolCaller: Sendable, Equatable {
    public var extensionID: String
    public var allowedToolIDs: Set<String>
    public init(extensionID: String, allowedToolIDs: Set<String>) {
        self.extensionID = extensionID
        self.allowedToolIDs = allowedToolIDs
    }
}

public struct MCPToolCall: Sendable {
    public var name: String
    public var arguments: [String: AnyJSON]
    public var progress: MCPProgress
    public var approve: @Sendable (MCPChange) async -> Bool
    public var caller: MCPToolCaller?
    public init(name: String, arguments: [String: AnyJSON], progress: MCPProgress = .none,
                approve: @escaping @Sendable (MCPChange) async -> Bool = { _ in true },
                caller: MCPToolCaller? = nil) {
        self.name = name
        self.arguments = arguments
        self.progress = progress
        self.approve = approve
        self.caller = caller
    }

    public func string(_ key: String) -> String? { arguments[key]?.string.flatMap { $0.isEmpty ? nil : $0 } }
    public func int(_ key: String) -> Int? { arguments[key]?.int }
    public func bool(_ key: String) -> Bool? { arguments[key]?.bool }
    public func strings(_ key: String) -> [String]? { arguments[key]?.array?.compactMap(\.string) }
    public func require(_ key: String) throws -> String {
        guard let s = arguments[key]?.string else { throw MCPToolError("missing the string argument \"\(key)\"") }
        return s
    }
}

public struct MCPToolError: Error, CustomStringConvertible, Sendable {
    public var message: String
    public var structured: AnyJSON?
    public init(_ message: String, structured: AnyJSON? = nil) {
        self.message = message
        self.structured = structured
    }
    public var description: String { message }
}

public struct MCPToolResult: Sendable, Equatable {
    public var content: [AnyJSON]
    public var structured: AnyJSON?
    public var isError: Bool
    public init(content: [AnyJSON], structured: AnyJSON? = nil, isError: Bool = false) {
        self.content = content
        self.structured = structured
        self.isError = isError
    }

    public static func text(_ s: String) -> MCPToolResult { MCPToolResult(content: [.textBlock(s)]) }

    public static func structured(_ v: AnyJSON, summary: String? = nil) -> MCPToolResult {
        var blocks: [AnyJSON] = []
        if let summary { blocks.append(.textBlock(summary)) }
        blocks.append(.textBlock(v.text))
        return MCPToolResult(content: blocks, structured: v)
    }

    public static func error(_ message: String, structured: AnyJSON? = nil) -> MCPToolResult {
        MCPToolResult(content: [.textBlock(message)], structured: structured, isError: true)
    }

    public var json: AnyJSON {
        var o: [String: AnyJSON] = ["content": .array(content), "isError": .bool(isError)]
        if let structured { o["structuredContent"] = structured }
        return .object(o)
    }
}

extension AnyJSON {
    public static func textBlock(_ s: String) -> AnyJSON { ["type": "text", "text": .string(s)] }
    public static func imageBlock(_ data: Data, mimeType: String = "image/png") -> AnyJSON {
        ["type": "image", "data": .string(data.base64EncodedString()), "mimeType": .string(mimeType)]
    }
}

public struct MCPTool: Sendable {
    public var name: String
    public var title: String
    public var description: String
    public var inputSchema: AnyJSON
    public var outputSchema: AnyJSON?
    public var annotations: MCPToolAnnotations
    public var writes: Bool
    public var handler: @Sendable (MCPToolCall) async throws -> MCPToolResult

    public init(name: String, title: String, description: String, inputSchema: AnyJSON, outputSchema: AnyJSON? = nil,
                annotations: MCPToolAnnotations = .read, writes: Bool = false,
                handler: @escaping @Sendable (MCPToolCall) async throws -> MCPToolResult) {
        self.name = name
        self.title = title
        self.description = description
        self.inputSchema = inputSchema
        self.outputSchema = outputSchema
        self.annotations = annotations
        self.writes = writes
        self.handler = handler
    }

    public var listing: AnyJSON {
        var o: [String: AnyJSON] = [
            "name": .string(name), "title": .string(title), "description": .string(description), "inputSchema": inputSchema,
            "annotations": ["title": .string(title), "readOnlyHint": .bool(annotations.readOnly),
                            "destructiveHint": .bool(annotations.destructive), "idempotentHint": .bool(annotations.idempotent),
                            "openWorldHint": .bool(annotations.openWorld)],
        ]
        if let outputSchema { o["outputSchema"] = outputSchema }
        return .object(o)
    }

    public func argumentProblem(_ args: [String: AnyJSON]) -> String? {
        for key in inputSchema["required"]?.array?.compactMap(\.string) ?? [] where args[key] == nil || args[key] == .null {
            return "missing the required argument \"\(key)\""
        }
        let props = inputSchema["properties"]?.object ?? [:]
        for (key, value) in args {
            guard let type = props[key]?["type"]?.string else {
                if inputSchema["additionalProperties"] == .bool(false), props[key] == nil { return "unknown argument \"\(key)\"" }
                continue
            }
            let ok: Bool = switch type {
            case "string": value.string != nil
            case "integer": value.int != nil
            case "number": value.double != nil
            case "boolean": value.bool != nil
            case "array": value.array != nil
            case "object": value.object != nil
            default: true
            }
            if !ok && value != .null { return "the argument \"\(key)\" must be of type \(type)" }
        }
        return nil
    }
}

public struct MCPResource: Sendable, Equatable {
    public var uri: String
    public var name: String
    public var title: String?
    public var mimeType: String?
    public var description: String?
    public init(uri: String, name: String, title: String? = nil, mimeType: String? = nil, description: String? = nil) {
        self.uri = uri
        self.name = name
        self.title = title
        self.mimeType = mimeType
        self.description = description
    }
    public var json: AnyJSON {
        var o: [String: AnyJSON] = ["uri": .string(uri), "name": .string(name)]
        if let title { o["title"] = .string(title) }
        if let mimeType { o["mimeType"] = .string(mimeType) }
        if let description { o["description"] = .string(description) }
        return .object(o)
    }
}

public protocol MCPResourceSource: Sendable {
    func resources() async -> [MCPResource]
    func templates() async -> [AnyJSON]
    func read(_ uri: String) async throws -> [AnyJSON]?
}

public struct MCPPrompt: Sendable {
    public struct Argument: Sendable {
        public var name: String
        public var description: String
        public var required: Bool
        public init(_ name: String, _ description: String, required: Bool = false) {
            self.name = name
            self.description = description
            self.required = required
        }
    }
    public var name: String
    public var title: String
    public var description: String
    public var arguments: [Argument]
    public var render: @Sendable ([String: String]) -> String

    public init(name: String, title: String, description: String, arguments: [Argument] = [], render: @escaping @Sendable ([String: String]) -> String) {
        self.name = name
        self.title = title
        self.description = description
        self.arguments = arguments
        self.render = render
    }

    public var listing: AnyJSON {
        ["name": .string(name), "title": .string(title), "description": .string(description),
         "arguments": .array(arguments.map { ["name": .string($0.name), "description": .string($0.description), "required": .bool($0.required)] })]
    }
}

public enum MCPWritePolicy: Sendable {
    case readOnly
    case allow
    case review(@Sendable (MCPChange) async -> Bool)

    public var allowsWrites: Bool {
        if case .readOnly = self { return false }
        return true
    }
}

public final class MCPServer: @unchecked Sendable {
    public static let toolAliases: [String: String] = [
        "read_file": "file_read",
        "write_file": "file_write",
        "create_file": "file_create",
        "delete_file": "file_delete",
        "move_file": "file_move",
        "copy_file": "file_copy",
        "rename_file": "file_rename",
        "create_directory": "dir_create",
        "make_directory": "dir_create",
        "directory_create": "dir_create",
        "delete_directory": "dir_delete",
        "remove_directory": "dir_delete",
        "directory_delete": "dir_delete",
        "edit_file": "code_replace",
        "replace_in_file": "code_replace",
        "insert_code_block": "code_insert",
        "insert_code": "code_insert",
        "regex_replace": "regex_replace_in_files",
        "checksum_verifier": "file_checksum_verifier",
        "list_directory": "dir_read",
        "execute_terminal_command": "use_terminal",
        "xcode_build": "project_build",
        "semantic_code_search": "semantic_query_engine",
        "cross_reference_search": "symbol_reference_graph",
        "search_dir": "search_text",
        "search_directory": "search_text",
        "find_file": "search_text",
        "symbol_graph": "symbol_reference_graph",
        "git": "version_control_operator",
        "git_rollback": "version_control_operator",
        "git_tool": "version_control_operator",
        "version_control": "version_control_operator",
        "git_branches": "git_branch_manager",
        "git_conflict": "git_conflict_resolver",
        "run_command": "use_terminal",
        "terminal_command": "use_terminal",
        "execute_command": "use_terminal",
        "bash": "use_terminal",
        "sh": "use_terminal",
        "zsh": "use_terminal",
        "useworkers": "use_workers",
        "workflow": "use_workers",
        "env_manager": "environment_variable_manager",
        "clipboard": "clipboard_manager_tool",
        "process_monitor": "process_monitor_tool",
        "disk_space": "disk_space_analyzer",
        "system_notification": "system_notification_tool",
        "memory_save": "save_to_memory",
        "save_memory": "save_to_memory",
        "memory_view": "view_memory",
        "memory_manage": "manage_memory",
        "conversation_context": "conversation_context_manager",
        "plan_askuser": "plan-AskUser",
        "plan_ask_user": "plan-AskUser",
        "ask_user": "plan-AskUser",
        "planaskuser": "plan-AskUser",
        "reporttouser": "report_to_user",
        "task_complete": "report_to_user",
        "task_completion": "report_to_user",
        "simulator": "simulator_controller",
        "binary_plist": "binary_plist_converter",
        "json_validator": "json_validator_tool",
        "yaml_parser": "yaml_parser_tool",
        "reverse": "reverse_analyze",
        "test_coverage": "test_coverage_reporter",
        "metrics": "code_metrics_analyzer",
        "dead_code": "dead_code_eliminator",
        "migration_advisor": "swift_migration_advisor",
        "ast_inspector": "swift_ast_inspector",
        "concurrency_analyzer": "swift_concurrency_analyzer",
        "swift_format": "swift_format_lint",
        "todo_scanner": "todo_fixme_scanner",
        "unused_imports": "unused_imports_detector",
        "security_audit": "security_audit_scanner",
        "memory_leak": "memory_leak_detector",
        "bundle_auditor": "bundle_resource_auditor",
        "core_data_inspector": "core_data_model_inspector",
        "swift_data_schema": "swift_data_schema_auditor",
        "privacy_manifest": "privacy_manifest_auditor",
        "macho_analyzer": "mach_o_binary_analyzer",
        "framework_linker": "framework_linker_auditor",
        "network_security": "network_security_auditor",
        "a11y_scanner": "accessibility_audit_scanner",
        "docstring": "docstring_generator",
        "snippet": "code_snippet_manager",
        "icon_generator": "icon_generator_tool",
        "colorset": "colorset_builder",
        "build_project": "project_build",
        "run_build": "project_build",
        "xcodebuild": "project_build",
        "run_tests": "project_test",
        "xcresult": "xcresult_parser",
        "device_destinations": "xcode_device_destination_finder",
        "xcode_scheme": "xcode_scheme_manager",
        "swift_package": "swift_package_manager",
        "spm": "swift_package_manager",
        "spm_tree": "spm_dependency_tree",
        "podfile": "podfile_inspector",
        "cartfile": "carthage_cartfile_inspector",
        "plist": "plist_editor",
        "entitlements": "entitlements_manager",
        "signing_certificate": "signing_certificate_inspector",
        "provisioning_profile": "provisioning_profile_reader",
        "asset_catalog": "asset_catalog_manager",
        "localization": "localization_manager",
        "string_catalog": "string_catalog_migrator",
    ]

    public static let modernVersion = "2026-07-28"
    public static let legacyVersions = ["2025-11-25", "2025-06-18", "2025-03-26"]
    public static var supportedVersions: [String] { [modernVersion] + legacyVersions }

    public static let protocolVersionKey = "io.modelcontextprotocol/protocolVersion"
    public static let clientCapabilitiesKey = "io.modelcontextprotocol/clientCapabilities"
    public static let clientInfoKey = "io.modelcontextprotocol/clientInfo"
    public static let serverInfoKey = "io.modelcontextprotocol/serverInfo"

    public static let methods: Set<String> = ["initialize", "ping", "server/discover", "tools/list", "tools/call", "resources/list",
                                              "resources/templates/list", "resources/read", "prompts/list", "prompts/get", "logging/setLevel"]

    public var name: String
    public var version: String
    public var title: String
    public var instructions: String
    private let lock = NSLock()
    private var _tools: [MCPTool] = []
    private var _policy: MCPWritePolicy = .readOnly
    public var resources: MCPResourceSource?
    public var prompts: [MCPPrompt] = []

    public init(name: String = "swiftcode", version: String = "1.0", title: String = "SwiftCode", instructions: String = "") {
        self.name = name
        self.version = version
        self.title = title
        self.instructions = instructions
    }

    public var tools: [MCPTool] {
        get { lock.withLock { _tools } }
        set { lock.withLock { _tools = newValue } }
    }

    public var writePolicy: MCPWritePolicy {
        get { lock.withLock { _policy } }
        set { lock.withLock { _policy = newValue } }
    }

    public final class Connection: @unchecked Sendable {
        private let lock = NSLock()
        private var _legacy: String?
        public init() {}
        public var legacyVersion: String? {
            get { lock.withLock { _legacy } }
            set { lock.withLock { _legacy = newValue } }
        }
    }

    var serverInfo: AnyJSON { ["name": .string(name), "version": .string(version), "title": .string(title)] }

    var capabilities: AnyJSON {
        var c: [String: AnyJSON] = ["tools": ["listChanged": false]]
        if resources != nil { c["resources"] = ["listChanged": false, "subscribe": false] }
        if !prompts.isEmpty { c["prompts"] = ["listChanged": false] }
        c["logging"] = [:]
        return .object(c)
    }

    public enum Era: Equatable, Sendable { case modern, legacy }

    public static func era(of params: AnyJSON?) throws -> Era {
        guard let v = params?["_meta"]?[protocolVersionKey] else { return .legacy }
        guard let version = v.string else { throw JSONRPCError.invalidParams("\(protocolVersionKey) must be a string") }
        guard version == modernVersion else {
            if legacyVersions.contains(version) {
                return .legacy
            }
            throw JSONRPCError(code: -32022, message: "Unsupported protocol version",
                               data: ["supported": .strings(supportedVersions), "requested": .string(version)])
        }
        guard params?["_meta"]?[clientCapabilitiesKey]?.object != nil else {
            throw JSONRPCError.invalidParams("\(clientCapabilitiesKey) is required in _meta")
        }
        return .modern
    }

    public func handle(method: String, params: AnyJSON?, connection: Connection, progress: MCPProgress = .none) async throws -> AnyJSON {
        let era = try Self.era(of: params)
        let result = try await dispatch(method: method, params: params, connection: connection, era: era, progress: progress)
        guard era == .modern else { return result }
        var o = result.object ?? [:]
        o["resultType"] = "complete"
        var meta = o["_meta"]?.object ?? [:]
        meta[Self.serverInfoKey] = serverInfo
        o["_meta"] = .object(meta)
        return .object(o)
    }

    private func dispatch(method: String, params: AnyJSON?, connection: Connection, era: Era, progress: MCPProgress) async throws -> AnyJSON {
        switch method {
        case "initialize":
            let asked = params?["protocolVersion"]?.string ?? ""
            let chosen = Self.legacyVersions.contains(asked) ? asked : Self.legacyVersions[0]
            connection.legacyVersion = chosen
            var r: [String: AnyJSON] = ["protocolVersion": .string(chosen), "capabilities": capabilities, "serverInfo": serverInfo]
            if !instructions.isEmpty { r["instructions"] = .string(instructions) }
            return .object(r)
        case "server/discover":
            var r: [String: AnyJSON] = ["supportedVersions": .strings(Self.supportedVersions), "capabilities": capabilities,
                                          "_meta": [Self.serverInfoKey: serverInfo]]
            if !instructions.isEmpty { r["instructions"] = .string(instructions) }
            return .object(r)
        case "ping", "logging/setLevel":
            return [:]
        case "tools/list":
            return ["tools": .array(tools.map(\.listing))]
        case "tools/call":
            guard let name = params?["name"]?.string else { throw JSONRPCError.invalidParams("tools/call needs a tool name") }
            let resolved = Self.toolAliases[name] ?? name
            guard let tool = tools.first(where: { $0.name == resolved }) else { throw JSONRPCError.invalidParams("Unknown tool: \(name)") }
            let args = params?["arguments"]?.object ?? [:]
            let call = MCPToolCall(name: name, arguments: args, progress: progress)
            return await run(tool, call).json
        case "resources/list":
            return ["resources": .array(await (resources?.resources() ?? []).map(\.json))]
        case "resources/templates/list":
            return ["resourceTemplates": .array(await resources?.templates() ?? [])]
        case "resources/read":
            guard let uri = params?["uri"]?.string else { throw JSONRPCError.invalidParams("resources/read needs a uri") }
            guard let contents = try await resources?.read(uri) else {
                throw JSONRPCError(code: era == .modern ? -32602 : -32002, message: "Resource not found", data: ["uri": .string(uri)])
            }
            return ["contents": .array(contents)]
        case "prompts/list":
            return ["prompts": .array(prompts.map(\.listing))]
        case "prompts/get":
            guard let name = params?["name"]?.string, let p = prompts.first(where: { $0.name == name }) else {
                throw JSONRPCError.invalidParams("Unknown prompt: \(params?["name"]?.string ?? "")")
            }
            var args: [String: String] = [:]
            for (k, v) in params?["arguments"]?.object ?? [:] { args[k] = v.string ?? v.text }
            for a in p.arguments where a.required && args[a.name] == nil {
                throw JSONRPCError.invalidParams("prompt \(name) needs the argument \"\(a.name)\"")
            }
            return ["description": .string(p.description),
                    "messages": [["role": "user", "content": .textBlock(p.render(args))]]]
        default:
            throw JSONRPCError.methodNotFound(method)
        }
    }

    public static func readOnlyMessage(_ tool: String) -> String {
        "\(tool) changes files, and this SwiftCode MCP server is read-only. Start it with `swiftcode mcp --allow-writes`, or use agent mode in the SwiftCode IDE, where each change is reviewed as a proposal."
    }

    public static let rejectedMessage = "The change was rejected in SwiftCode's review; nothing was written."

    public func run(_ tool: MCPTool, _ call: MCPToolCall) async -> MCPToolResult {
        var call = call
        call.arguments = MCPParameterAliases.normalized(
            call.arguments,
            declaredProperties: Set(tool.inputSchema["properties"]?.object?.keys.map { $0 } ?? []))
        if let problem = tool.argumentProblem(call.arguments) { return .error("\(tool.name): \(problem)") }
        if let caller = call.caller, !caller.allowedToolIDs.contains(tool.name) {
            return .error("Tool '\(tool.name)' is not approved for extension '\(caller.extensionID)'.")
        }
        if tool.writes {
            switch writePolicy {
            case .readOnly:
                return .error(Self.readOnlyMessage(tool.name))
            case .allow:
                call.approve = { _ in true }
            case .review(let ask):
                if let caller = call.caller {
                    call.approve = { change in await ask(change.settingCaller(caller)) }
                } else {
                    call.approve = ask
                }
            }
        } else {
            call.approve = { _ in false }
        }
        do {
            return try await tool.handler(call)
        } catch let e as MCPToolError {
            return .error(e.message, structured: e.structured)
        } catch is CancellationError {
            return .error("cancelled")
        } catch {
            return .error("\(tool.name) failed: \(error)")
        }
    }
}

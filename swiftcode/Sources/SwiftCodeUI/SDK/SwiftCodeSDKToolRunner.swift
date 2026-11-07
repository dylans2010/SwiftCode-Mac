import Foundation
import SwiftCodeExtensions
import SwiftCodeMCP
import SwiftCodeAssistant
import SwiftCodeSDK

public enum SDKAssistToolMapping {
    public static func mcpTools(for capability: SDKCapabilityID) -> Set<String> {
        switch capability {
        case .workspaceRead:
            return ["file_read", "dir_read", "file_list", "read_multiple_files",
                    "file_metadata", "file_head_preview", "file_checksum_verifier",
                    "file_compare_diff", "search_text", "find_text", "search_regex",
                    "glob_search", "grep"]
        case .projectRead:
            return ["workspace_describe", "project_structure_map", "project_target_list",
                    "target_source_list", "target_dependencies_list", "package_manifest_read"]
        case .workspaceWrite:
            return ["file_write", "file_edit", "file_create", "file_delete",
                    "file_move", "file_copy", "file_rename", "dir_create", "dir_delete",
                    "code_replace", "code_insert", "file_append", "replace_text",
                    "regex_replace_in_files", "code_multi_edit", "code_format"]
        case .sourceControlRead:
            return ["git_status", "git_diff", "git_log", "git_branch", "git_blame", "git_show"]
        case .sourceControlWrite:
            return ["git_add", "git_commit", "git_checkout", "git_merge",
                    "git_revert", "git_reset", "git_stash"]
        case .buildExecute:
            return ["project_build", "project_test", "build", "test"]
        case .taskExecute, .terminalSandbox:
            return ["use_terminal", "task_runner"]
        case .networkRequest:
            return ["fetch_url", "web_search", "http_request"]
        case .docsSearch:
            return ["documentation_search", "api_reference_search"]
        default:
            return []
        }
    }
}

public enum SwiftCodeSDKToolServerRegistry {
    private static let lock = NSLock()
    nonisolated(unsafe) private static var _current: MCPServer?

    public static var current: MCPServer? {
        get { lock.withLock { _current } }
        set { lock.withLock { _current = newValue } }
    }
}

public struct SwiftCodeSDKToolRunner: SDKAssistToolRunning, Sendable {
    public static let mcpToolArgumentKey = "tool"

    private let serverProvider: @Sendable () -> MCPServer?

    public init(serverProvider: @escaping @Sendable () -> MCPServer? = { SwiftCodeSDKToolServerRegistry.current }) {
        self.serverProvider = serverProvider
    }

    public func liveAllowedToolIDs(for extensionID: String) async -> Set<String>? {
        Set(await SDKAssistService.shared.liveAllowedToolIDs(for: extensionID))
    }

    public func runTool(session: SDKAssistSession, call: SDKAssistToolCall) async throws -> SDKAssistToolResult {
        guard session.allowedToolIDs.contains(call.toolName) else {
            throw SDKError(code: .permissionDenied, message: "The tool is not approved for this session.")
        }
        guard let server = serverProvider() else {
            throw SDKError(
                code: .serviceUnavailable,
                message: "Assist is not available for extensions right now.",
                suggestion: "No workspace tool server is attached for extension tool calls."
            )
        }
        guard let requested = call.arguments[Self.mcpToolArgumentKey], !requested.isEmpty else {
            throw SDKError(code: .invalidArgument, message: "The tool call must name an MCP tool in its \"tool\" argument.")
        }
        let resolved = MCPServer.toolAliases[requested] ?? requested
        guard let capability = SDKCapabilityID(rawValue: call.toolName) else {
            throw SDKError(code: .permissionDenied, message: "The tool is not approved for this session.")
        }
        let allowed = SDKAssistToolMapping.mcpTools(for: capability)
        guard allowed.contains(resolved) else {
            throw SDKError(code: .permissionDenied, message: "The tool is not approved for this session.")
        }
        guard let tool = server.tools.first(where: { $0.name == resolved }) else {
            throw SDKError(code: .invalidArgument, message: "The host does not provide the tool \"\(resolved)\".")
        }
        var mcpArguments: [String: AnyJSON] = [:]
        for (key, value) in call.arguments where key != Self.mcpToolArgumentKey {
            mcpArguments[key] = Self.mcpArgument(value)
        }
        let caller = MCPToolCaller(extensionID: session.extensionID, allowedToolIDs: allowed)
        let result = await server.run(tool, MCPToolCall(name: resolved, arguments: mcpArguments, caller: caller))
        let output = result.content.compactMap { $0["text"]?.string }.joined(separator: "\n")
        return SDKAssistToolResult(toolName: call.toolName, succeeded: !result.isError, output: output)
    }

    static func mcpArgument(_ value: String) -> AnyJSON {
        switch value.lowercased() {
        case "true": return .bool(true)
        case "false": return .bool(false)
        default: break
        }
        if let int = Int(value) { return .int(int) }
        if let double = Double(value) { return .double(double) }
        return .string(value)
    }
}

import Foundation
import SwiftCodeExtensions
import SwiftCodeMCP
import SwiftCodeAssistant
import SwiftCodeSDK

// MARK: - SwiftCodeSDKToolRunner (Wave 17, Slice B)
//
// The host-side implementation of `SDKAssistToolRunning`: the
// grant-enforcing tool runner for `SDKAssistHostBackend.
// executeTool`. It lives here (SwiftCodeUI) because it is the only
// layer that may touch both SwiftCodeSDK (the protocol, the session)
// and SwiftCodeMCP (the tool server) — SwiftCodeSDK itself must not
// depend on SwiftCodeMCP.
//
// How a call flows:
//   1. The backend has already checked the session is open, the
//      tool (an SDK capability ID — Legacy: "Tools are addressed
//      by capability ID; there is no separate tool-name registry
//      to drift out of sync") is in the session's snapshot, and
//      the live grants still allow it. This runner re-checks the
//      snapshot itself, so a direct `runTool` caller gets the same
//      refusal.
//   2. The concrete MCP tool is named by the call's `"tool"`
//      argument (aliases resolve through
//      `MCPServer.toolAliases`, exactly as `tools/call` does).
//      It must be in the capability's mapped set
//      (`SDKAssistToolMapping`) — anything else is refused with
//      `.permissionDenied` before any approval UI appears.
//   3. The tool runs on the host's MCP server through
//      `MCPServer.run`, under the server's `MCPWritePolicy`, with
//      the extension's caller identity (`MCPToolCaller`)
//      attached: a granted write still asks the user exactly as a
//      host write would, and an ungranted tool never reaches the
//      approval UI. No bypass, no Autopilot, no parallel
//      registry, no fabricated result: a refused or failed run is
//      an error, never invented output.
//
// The server comes from `SwiftCodeSDKToolServerRegistry`: the
// workspace window publishes its MCP server there (see
// `WorkspaceWindowController+AgentMode.mcpHost`). Until a server
// is published, `runTool` throws `.serviceUnavailable` — the
// honest "not attached" answer, never a fake run. The published
// server's own write policy decides what a write does: the base
// window server is read-only, so extension writes are refused
// there until the window publishes a review-policy server with a
// presenter for extension changes (pending host-UI work — see
// the Wave 17 Slice B draft). Reads already run live against the
// published server.
//
// Wire limitation, stated plainly: `SDKAssistToolCall` arguments
// cross IPC as strings, while MCP tools take typed JSON. The
// runner recovers JSON scalars (`"true"`/`"false"` → bool,
// integer text → int, decimal text → double, else string) so
// schema validation passes for ordinary arguments. A genuinely
// string argument that looks like a number (a file named "123")
// converts to a number and fails validation honestly instead of
// running with the wrong type; structured arguments (objects,
// arrays) cannot cross this wire at all.

/// The MCP tools one SDK capability authorizes (Wave 17, Slice B).
///
/// Deny-by-default: a capability maps ONLY to the tools listed
/// here; every other capability maps to nothing, so its tools are
/// refused even when granted. Each name was verified live against
/// the SwiftCodeMCP registry (`tool("…")` registrations) and its
/// `writes` flag: reads are `writes: false`, writes are
/// `writes: true` (so the server's approval gate applies), builds
/// are `writes: false` (they run without approval, exactly as a
/// host build does), and `use_terminal` is `writes: true` with
/// its own terminal-approval allow-list. Remote side effects are
/// excluded on purpose: no `git_push` / `git_pull` / `git_clone`,
/// no `download_file`, no `open_browser`.
public enum SDKAssistToolMapping {
    /// The canonical MCP tool names an SDK capability authorizes.
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
            // Local mutations only; each is `writes: true`, so the
            // approval gate asks the user. Push/pull/clone are
            // remote side effects and are deliberately NOT mapped.
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
            // UI surfaces, security scopes, Assist variants,
            // simulator/preview views, and everything else: no MCP
            // tool is authorized. A granted-but-unmapped capability
            // is refused, never silently widened.
            return []
        }
    }
}

/// The published MCP server extension tool calls run against
/// (Wave 17, Slice B). The workspace window publishes its server
/// here when it creates it; the runner reads it on every call, so
/// a window closing (or never opening) leaves the runner honestly
/// unattached instead of holding a dead server. Last window wins
/// when several are open.
public enum SwiftCodeSDKToolServerRegistry {
    private static let lock = NSLock()
    nonisolated(unsafe) private static var _current: MCPServer?

    public static var current: MCPServer? {
        get { lock.withLock { _current } }
        set { lock.withLock { _current = newValue } }
    }
}

/// Runs extension tool calls on the host's MCP server, under the
/// caller's grants and the server's approval flow.
public struct SwiftCodeSDKToolRunner: SDKAssistToolRunning, Sendable {
    /// The reserved argument naming the concrete MCP tool.
    public static let mcpToolArgumentKey = "tool"

    private let serverProvider: @Sendable () -> MCPServer?

    public init(serverProvider: @escaping @Sendable () -> MCPServer? = { SwiftCodeSDKToolServerRegistry.current }) {
        self.serverProvider = serverProvider
    }

    public func liveAllowedToolIDs(for extensionID: String) async -> Set<String>? {
        Set(await SDKAssistService.shared.liveAllowedToolIDs(for: extensionID))
    }

    public func runTool(session: SDKAssistSession, call: SDKAssistToolCall) async throws -> SDKAssistToolResult {
        // Snapshot re-check (defense in depth: the backend already
        // checked this, but a direct `runTool` caller must not
        // bypass it).
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

    /// Recovers a JSON scalar from a string wire argument (see the
    /// file header: `"true"` → bool, `"12"` → int, `"1.5"` →
    /// double, anything else → string).
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

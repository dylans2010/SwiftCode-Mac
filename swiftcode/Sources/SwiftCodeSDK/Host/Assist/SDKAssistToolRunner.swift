import Foundation

// MARK: - SDKAssistToolRunning (Wave 17, Slice B)
//
// The grant-enforcing tool runner seam for `SDKAssistHostBackend.
// executeTool`. The layering follows the existing
// `SDKAssistProviderResolving` pattern exactly:
//
//   - This protocol lives in SwiftCodeSDK. SwiftCodeSDK does NOT depend on
//     SwiftCodeMCP (that would be a cycle: SwiftCodeMCP depends on
//     SwiftCodeIDECore/SwiftCodeAssistant, and the SDK host must stay
//     reachable from the UI without dragging the whole tool
//     server in).
//   - The implementation lives in SwiftCodeUI
//     (`SwiftCodeSDKToolRunner`), which depends on both SwiftCodeSDK and
//     SwiftCodeMCP, and is installed by the host UI at startup
//     (`SwiftCodeSDKInstaller`), next to the provider resolver.
//   - The backend never builds a runner itself and never touches
//     an MCP tool directly: it enforces the grant checks that do
//     not need the runner (closed session, snapshot membership,
//     live grants), then delegates the run.
//
// What the runner must do (the implementation's contract):
//   - Run ONLY the MCP tool the call names, and only when that
//     tool is in the capability's mapped set (see
//     `SDKAssistToolMapping` in SwiftCodeUI): an unmapped or
//     ungranted tool is refused with `.permissionDenied` before
//     any approval UI appears.
//   - Run it through the host's EXISTING approval flow — the
//     server's `MCPWritePolicy` — with the extension's caller
//     identity (`MCPToolCaller`: extension ID + grant snapshot)
//     attached, so a granted write still asks the user exactly as
//     a host write would. No bypass, no Autopilot, no parallel
//     registry, no fabricated result: a refused or failed run is
//     an error, never invented output.

/// Runs one approved extension tool call through the host's MCP
/// tools, under the caller's grants and the host's approval flow.
/// Installed by the host UI at startup; until then the backend
/// throws `.serviceUnavailable` for every `executeTool`.
public protocol SDKAssistToolRunning: Sendable {
    /// The tool IDs the extension's LIVE grants allow right now,
    /// as SDK capability IDs — or nil when the host cannot answer
    /// live (the backend then enforces the session snapshot
    /// alone). A revoked grant closes the path even for a session
    /// created before the revocation: live grants can only narrow
    /// the snapshot, never extend it.
    func liveAllowedToolIDs(for extensionID: String) async -> Set<String>?

    /// Runs one tool call for `session` and returns its real
    /// output. The backend has already checked the session is
    /// open, the tool is in the session's snapshot, and the live
    /// grants still allow it; the runner re-checks the mapped MCP
    /// tool against the same snapshot before running anything.
    func runTool(session: SDKAssistSession, call: SDKAssistToolCall) async throws -> SDKAssistToolResult
}

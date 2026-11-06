import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import SwiftCodeAssistant
import SwiftCodeIDECore

/// The real Composio client for `use_composio`, replacing the
/// Wave 4 honest failure.
///
/// Legacy's `AssistComposioTool` prefers the `composio` CLI
/// (`composio execute <slug> -d <argsJSON>`) and falls back to the
/// REST API (`POST https://backend.composio.dev/api/v3.1/tools/execute/<slug>`,
/// header `x-api-key` — or `x-user-api-key` for `uak_…` keys).
/// The API key comes from exactly Legacy's order: the Keychain
/// (SecretStore account `composio.api-key`), then the
/// `COMPOSIO_API_KEY` environment variable, then
/// `~/.composio/user_data.json` (`api_key`, `test_user_id`).
/// The tool never writes a key and never puts one in its output.
/// See `specs/ide/gap-closure-failing-tools.md` §6.
extension SwiftCodeMCPHost {
    /// The SecretStore account for the Composio API key. The
    /// canonical constant lives in `SecretStore.SecretAccount`
    /// (shared file — the one-line patch is delivered to the
    /// coordinator; this local copy keeps the client working until
    /// it lands).
    nonisolated static let composioSecretAccount = "composio.api-key"

    /// Test seam: replaces the secret store in tests. Nil in
    /// production.
    nonisolated(unsafe) static var composioTestSecretStore: SecretStore?

    /// The CLI candidates, in Legacy's order, plus a PATH lookup.
    nonisolated static func composioCLICandidates() -> [String] {
        var candidates = [
            (NSHomeDirectory() as NSString).appendingPathComponent(".local/bin/composio"),
            "/usr/local/bin/composio",
            "/opt/homebrew/bin/composio",
        ]
        if let path = ProcessInfo.processInfo.environment["PATH"] {
            for dir in path.split(separator: ":").map(String.init) {
                candidates.append((dir as NSString).appendingPathComponent("composio"))
            }
        }
        var seen = Set<String>()
        return candidates.filter { seen.insert($0).inserted }
    }

    /// The first CLI candidate that exists and is executable.
    nonisolated static func composioCLIPath() -> String? {
        composioCLICandidates().first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    /// The Composio API key in Legacy's order: SecretStore, then
    /// `COMPOSIO_API_KEY`, then `~/.composio/user_data.json`.
    /// Returns nil when no key is configured anywhere.
    nonisolated static func composioAPIKey() -> String? {
        let store = composioTestSecretStore ?? defaultSecretStore()
        if let key = store.readString(account: composioSecretAccount), !key.isEmpty { return key }
        if let env = ProcessInfo.processInfo.environment["COMPOSIO_API_KEY"], !env.isEmpty { return env }
        let url = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".composio").appendingPathComponent("user_data.json")
        if let data = try? Data(contentsOf: url),
           let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let key = obj["api_key"] as? String, !key.isEmpty { return key }
        return nil
    }

    /// Legacy's slug validation: non-empty, `[A-Z0-9_]+`, max 128
    /// characters.
    nonisolated static func composioValidateSlug(_ slug: String) throws -> String {
        let trimmed = slug.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw MCPToolError("toolSlug cannot be empty") }
        guard trimmed.count <= 128 else { throw MCPToolError("toolSlug is too long (max 128 characters)") }
        let allowed = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_")
        guard trimmed.uppercased().unicodeScalars.allSatisfy({ allowed.contains($0) }) else {
            throw MCPToolError("toolSlug must contain only letters, digits, and underscores (got '\(trimmed)')")
        }
        return trimmed
    }

    /// Parses one JSON object out of CLI stdout: the whole output
    /// when it is JSON, else the first `{…}` span that decodes.
    /// Nil when no JSON object is present.
    nonisolated static func composioExtractJSONObject(_ text: String) -> [String: Any]? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if let data = trimmed.data(using: .utf8),
           let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] { return obj }
        // Scan for the first brace span that decodes as an object.
        var depth = 0
        var start: String.Index?
        var index = trimmed.startIndex
        while index < trimmed.endIndex {
            let ch = trimmed[index]
            if ch == "{" {
                if depth == 0 { start = index }
                depth += 1
            } else if ch == "}" {
                depth -= 1
                if depth == 0, let s = start {
                    let span = String(trimmed[s...index])
                    if let data = span.data(using: .utf8),
                       let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] { return obj }
                }
            }
            index = trimmed.index(after: index)
        }
        return nil
    }

    /// The Composio execution summary: `successful` + `logId` /
    /// `log_id` when the response carries them, else the whole
    /// response as pretty JSON.
    nonisolated static func composioSummarize(_ obj: [String: Any]) -> String {
        if let data = try? JSONSerialization.data(withJSONObject: obj, options: [.prettyPrinted, .sortedKeys]),
           let text = String(data: data, encoding: .utf8) { return text }
        return String(describing: obj)
    }

    /// `use_composio`: CLI first, REST fallback. Approval via
    /// `approveChangeWithoutFile` (no Autopilot bypass). The key
    /// is never written and never appears in the output.
    func useComposioExecute(_ call: MCPToolCall) async throws -> MCPToolResult {
        let slug = try Self.composioValidateSlug(call.string("toolSlug") ?? "")
        let argsText = call.string("arguments") ?? "{}"
        guard let argsData = argsText.data(using: .utf8),
              let argsObj = try? JSONSerialization.jsonObject(with: argsData) as? [String: Any] else {
            throw MCPToolError("arguments must be a JSON object (got: \(argsText.prefix(200)))")
        }
        let argsJSON = String(data: argsData, encoding: .utf8) ?? "{}"
        try await approveChangeWithoutFile(
            tool: "use_composio",
            summary: "Execute Composio tool '\(slug)' with the supplied arguments.",
            call: call)
        let started = Date()
        if let cli = Self.composioCLIPath() {
            guard let run = await archiveRunFixed(cli, ["execute", slug, "-d", argsJSON]) else {
                throw MCPToolError("Could not start the Composio CLI at \(cli)")
            }
            if let obj = Self.composioExtractJSONObject(run.stdout) {
                let summary = Self.composioSummarize(obj)
                let (capped, _) = Self.terminalCappedOutput(summary)
                let successful = (obj["successful"] as? Bool) ?? true
                if !successful {
                    throw MCPToolError("Composio CLI reported failure for '\(slug)':\n\(capped)")
                }
                let logId = (obj["logId"] as? String) ?? (obj["log_id"] as? String)
                return .structured(["slug": .string(slug), "successful": .bool(true),
                                    "logId": logId.map(AnyJSON.string) ?? .null,
                                    "durationMs": .int(Int(Date().timeIntervalSince(started) * 1000))],
                                   summary: capped)
            }
            if run.exitCode != 0 {
                throw MCPToolError("Composio CLI failed for '\(slug)' (exit \(run.exitCode)):\n\(run.stderr.suffix(4_000))")
            }
            throw MCPToolError("Composio CLI succeeded for '\(slug)' but returned no JSON output:\n\(run.stdout.prefix(2_000))")
        }
        guard let key = Self.composioAPIKey() else {
            throw MCPToolError("No Composio API key is configured and no composio CLI was found, so the Composio service cannot run. " +
                "Supply the key in the Keychain (account 'composio.api-key'), the COMPOSIO_API_KEY environment variable, or ~/.composio/user_data.json — or install the CLI (composio) so the key can come from its own login.")
        }
        var request = URLRequest(url: URL(string: "https://backend.composio.dev/api/v3.1/tools/execute/\(slug)")!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if key.hasPrefix("uak_") {
            request.setValue(key, forHTTPHeaderField: "x-user-api-key")
        } else {
            request.setValue(key, forHTTPHeaderField: "x-api-key")
        }
        request.httpBody = try? JSONSerialization.data(withJSONObject: ["arguments": argsObj])
        let response = try await HTTP.send(request, timeout: 30)
        guard (200..<300).contains(response.status) else {
            throw MCPToolError("Composio REST API failed for '\(slug)' (HTTP \(response.status)): \(response.text.prefix(300))")
        }
        guard let obj = try? JSONSerialization.jsonObject(with: response.body) as? [String: Any] else {
            throw MCPToolError("Composio REST API returned non-JSON for '\(slug)': \(response.text.prefix(300))")
        }
        let summary = Self.composioSummarize(obj)
        let (capped, _) = Self.terminalCappedOutput(summary)
        let successful = (obj["successful"] as? Bool) ?? true
        if !successful {
            throw MCPToolError("Composio reported failure for '\(slug)':\n\(capped)")
        }
        let logId = (obj["logId"] as? String) ?? (obj["log_id"] as? String)
        return .structured(["slug": .string(slug), "successful": .bool(true),
                            "logId": logId.map(AnyJSON.string) ?? .null,
                            "durationMs": .int(Int(Date().timeIntervalSince(started) * 1000))],
                           summary: capped)
    }
}

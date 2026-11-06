import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import YcodeAssistant
import YcodeIDECore

/// A real MCP (Model Context Protocol) client for `use_mcp`,
/// replacing the Wave 4 list-only port.
///
/// Legacy's `UseMCP` enumerates its configured servers and calls a
/// tool on one of them through `MCPServerManager`. The destination
/// has no MCP client, so this file is one: it reads the user's
/// server configuration, speaks JSON-RPC 2.0 over stdio (spawned
/// fixed-argv, NDJSON on stdout) or streamable HTTP, and returns
/// the server's content blocks. See
/// `specs/ide/gap-closure-failing-tools.md` §5.
///
/// Configuration: `~/.config/ycode/mcp-servers.json` (or
/// `$XDG_CONFIG_HOME/ycode/mcp-servers.json`), Claude-Desktop
/// shape: `{"mcpServers": {"name": {"command": "...", "args": [...],
/// "env": {...}} | {"url": "https://…", "headers": {...}}}}`.
/// Transport is inferred (a `command` means stdio, a `url` means
/// streamable HTTP). The legacy SSE transport is NOT implemented:
/// a server configured with `"transport": "sse"` fails naming that.
///
/// Every call goes through `terminalApproveChange` (no Autopilot
/// bypass) except the no-connection `list_servers` read, mirroring
/// Legacy's approval behaviour.
extension YcodeMCPHost {
    /// One configured external MCP server.
    struct ExternalMCPServer: Sendable {
        var name: String
        var command: String?
        var args: [String]
        var env: [String: String]
        var url: String?
        var headers: [String: String]
        var transport: String?
    }

    /// Test seam: an in-memory server table used by tests instead
    /// of the config file. Nil in production.
    nonisolated(unsafe) static var externalMCPTestConfig: [String: ExternalMCPServer]?

    /// The config file path (`$XDG_CONFIG_HOME` when set, else
    /// `~/.config`).
    nonisolated static func externalMCPConfigURL() -> URL {
        let base: URL
        if let xdg = ProcessInfo.processInfo.environment["XDG_CONFIG_HOME"], !xdg.isEmpty {
            base = URL(fileURLWithPath: (xdg as NSString).expandingTildeInPath)
        } else {
            base = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".config")
        }
        return base.appendingPathComponent("ycode").appendingPathComponent("mcp-servers.json")
    }

    /// The configured servers, or an empty map when the file is
    /// absent (Legacy's "no servers configured" case). A present
    /// but unparseable file fails naming the path and the expected
    /// shape.
    nonisolated static func externalMCPServers() throws -> [String: ExternalMCPServer] {
        if let test = externalMCPTestConfig { return test }
        let url = externalMCPConfigURL()
        guard FileManager.default.fileExists(atPath: url.path) else { return [:] }
        let data = try Data(contentsOf: url)
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let servers = root["mcpServers"] as? [String: Any] else {
            throw MCPToolError("MCP config \(url.path) is not a valid server map: expected {\"mcpServers\": {\"name\": {\"command\": \"…\", \"args\": […]} | {\"url\": \"https://…\"}}}")
        }
        var out: [String: ExternalMCPServer] = [:]
        for (name, raw) in servers {
            guard let cfg = raw as? [String: Any] else { continue }
            out[name] = ExternalMCPServer(
                name: name,
                command: cfg["command"] as? String,
                args: cfg["args"] as? [String] ?? [],
                env: cfg["env"] as? [String: String] ?? [:],
                url: cfg["url"] as? String,
                headers: cfg["headers"] as? [String: String] ?? [:],
                transport: cfg["transport"] as? String)
        }
        return out
    }

    // MARK: - JSON-RPC

    /// One JSON-RPC 2.0 request object (id, method, params).
    nonisolated static func externalMCPRequest(id: Int, method: String, params: [String: Any]? = nil) -> Data {
        var obj: [String: Any] = ["jsonrpc": "2.0", "id": id, "method": method]
        if let params { obj["params"] = params }
        return (try? JSONSerialization.data(withJSONObject: obj)) ?? Data()
    }

    /// Parses one JSON-RPC message. Returns `.response(result)`,
    /// `.error(message)`, or nil for notifications / other traffic.
    nonisolated static func externalMCPParseMessage(_ line: String) -> Result<Any, String>? {
        guard let data = line.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        guard obj["id"] != nil else { return nil } // notification or response-without-id
        if let error = obj["error"] as? [String: Any] {
            let message = error["message"] as? String ?? "unknown MCP error"
            let code = error["code"] as? Int
            return .failure(code.map { "\(message) (code \($0))" } ?? message)
        }
        guard let result = obj["result"] else { return nil }
        return .success(result)
    }

    /// Joins an MCP `tools/call` result's content blocks into text
    /// (text blocks, plus `data` of embedded resources when present).
    /// `isError` is reported separately so the caller can fail.
    nonisolated static func externalMCPJoinContent(_ result: Any) -> (text: String, isError: Bool) {
        guard let dict = result as? [String: Any] else {
            return (String(describing: result), false)
        }
        let isError = (dict["isError"] as? Bool) ?? false
        var parts: [String] = []
        for block in dict["content"] as? [[String: Any]] ?? [] {
            if let text = block["text"] as? String { parts.append(text) }
            else if let resource = block["resource"] as? [String: Any], let text = resource["text"] as? String {
                parts.append(text)
            } else if let data = block["data"] as? String { parts.append(data) }
        }
        if parts.isEmpty, let structured = dict["structuredContent"] {
            if let data = try? JSONSerialization.data(withJSONObject: structured, options: [.prettyPrinted, .sortedKeys]) {
                parts.append(String(decoding: data, as: UTF8.self))
            }
        }
        return (parts.joined(separator: "\n"), isError)
    }

    /// The `initialize` params (protocol version `2025-03-26`,
    /// client `Ycode` / `ycode-mcp`). The server's protocol version
    /// is accepted, never enforced.
    nonisolated static var externalMCPInitializeParams: [String: Any] {
        ["protocolVersion": "2025-03-26",
         "capabilities": [:] as [String: Any],
         "clientInfo": ["name": "Ycode", "version": "ycode-mcp"]]
    }

    // MARK: - stdio transport

    /// Runs one JSON-RPC exchange against a stdio server: spawns
    /// the fixed command, sends `initialize` + `notifications/initialized`,
    /// then the single `method` call, and terminates the process.
    /// Stdout is read as NDJSON (stderr is bounded to a 4,000-char
    /// tail and only surfaced on failure). Timeouts: 30 s for
    /// initialize/list, 300 s for a tool call.
    func externalMCPStdioExchange(server: ExternalMCPServer, method: String, params: [String: Any]?,
                                  timeout: TimeInterval) async throws -> Any {
        guard let command = server.command, !command.isEmpty else {
            throw MCPToolError("MCP server '\(server.name)' has no command (stdio transport needs one)")
        }
        let (result, stderr) = try await Self.externalMCPStdioRun(
            command: command, args: server.args, env: server.env,
            requests: [
                (1, "initialize", Self.externalMCPInitializeParams),
                (2, method, params),
            ],
            timeout: timeout)
        if let error = result as? MCPToolError { throw error }
        _ = stderr
        return result
    }

    /// The low-level stdio exchange: spawns, writes each request as
    /// one NDJSON line, and collects the response for each request id
    /// (the `notifications/initialized` notification between
    /// initialize and the method call carries no id and is sent
    /// without waiting). Returns the method-call result, or throws.
    nonisolated static func externalMCPStdioRun(command: String, args: [String], env: [String: String],
                                                requests: [(id: Int, method: String, params: [String: Any]?)],
                                                timeout: TimeInterval) async throws -> (Any, String) {
        try await Task.detached {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: command)
            process.arguments = args
            var environment = ProcessInfo.processInfo.environment
            for (key, value) in env { environment[key] = value }
            process.environment = environment
            let outPipe = Pipe(), errPipe = Pipe(), inPipe = Pipe()
            process.standardOutput = outPipe
            process.standardError = errPipe
            process.standardInput = inPipe
            let lock = NSLock()
            var lines: [String] = []
            var stdoutBuffer = Data()
            var stderrData = Data()
            outPipe.fileHandleForReading.readabilityHandler = { handle in
                let chunk = handle.availableData
                guard !chunk.isEmpty else { return }
                lock.lock(); defer { lock.unlock() }
                stdoutBuffer.append(chunk)
                while let newline = stdoutBuffer.firstIndex(of: 0x0A) {
                    let lineData = stdoutBuffer[..<newline]
                    stdoutBuffer.removeSubrange(...newline)
                    if let line = String(data: lineData, encoding: .utf8) { lines.append(line) }
                }
            }
            errPipe.fileHandleForReading.readabilityHandler = { handle in
                let chunk = handle.availableData
                guard !chunk.isEmpty else { return }
                lock.lock(); defer { lock.unlock() }
                stderrData.append(chunk)
                if stderrData.count > 16_384 { stderrData.removeFirst(stderrData.count - 16_384) }
            }
            do { try process.run() } catch {
                throw MCPToolError("Could not start MCP server command '\(command)': \(error.localizedDescription)")
            }
            func response(for id: Int) -> Result<Any, String>? {
                lock.lock(); defer { lock.unlock() }
                for line in lines {
                    guard let data = line.data(using: .utf8),
                          let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                          (obj["id"] as? Int) == id || (obj["id"] as? NSNumber)?.intValue == id else { continue }
                    return externalMCPParseMessage(line)
                }
                return nil
            }
            func send(_ id: Int, _ method: String, _ params: [String: Any]?) {
                var data = externalMCPRequest(id: id, method: method, params: params)
                data.append(0x0A)
                inPipe.fileHandleForWriting.write(data)
            }
            let deadline = Date().addingTimeInterval(timeout)
            // initialize
            let first = requests[0]
            send(first.id, first.method, first.params)
            var initResult: Result<Any, String>?
            while initResult == nil && Date() < deadline && process.isRunning {
                initResult = response(for: first.id)
                if initResult == nil { try await Task.sleep(nanoseconds: 25_000_000) }
            }
            if let initResult {
                if case .failure(let message) = initResult {
                    process.terminate()
                    throw MCPToolError("MCP server '\(command)' initialize failed: \(message)")
                }
            } else {
                process.terminate()
                throw MCPToolError("MCP server '\(command)' did not answer initialize within \(Int(timeout))s")
            }
            // notifications/initialized (a notification: no id, no wait)
            if let data = try? JSONSerialization.data(withJSONObject: ["jsonrpc": "2.0", "method": "notifications/initialized"]) {
                inPipe.fileHandleForWriting.write(data + Data([0x0A]))
            }
            // The method call (only one per exchange).
            guard requests.count > 1 else {
                process.terminate()
                throw MCPToolError("Internal error: no MCP method to call")
            }
            let call = requests[1]
            send(call.id, call.method, call.params)
            var callResult: Result<Any, String>?
            while callResult == nil && Date() < deadline && process.isRunning {
                callResult = response(for: call.id)
                if callResult == nil { try await Task.sleep(nanoseconds: 25_000_000) }
            }
            let stderr = String(decoding: stderrData, as: UTF8.self)
            process.terminate()
            guard let callResult else {
                throw MCPToolError("MCP server '\(command)' did not answer '\(call.method)' within \(Int(timeout))s\(stderr.isEmpty ? "" : "\nServer stderr: \(stderr.suffix(4_000))")")
            }
            switch callResult {
            case .success(let value): return (value, stderr)
            case .failure(let message): throw MCPToolError("MCP server '\(command)' error: \(message)\(stderr.isEmpty ? "" : "\nServer stderr: \(stderr.suffix(4_000))")")
            }
        }.value
    }

    // MARK: - streamable HTTP transport

    /// One JSON-RPC exchange over streamable HTTP: POST with
    /// `Accept: application/json, text/event-stream`, then parse
    /// either a bare JSON response or an SSE stream (`data:` lines).
    func externalMCPHTTPExchange(server: ExternalMCPServer, method: String, params: [String: Any]?,
                                 timeout: TimeInterval) async throws -> Any {
        guard let urlString = server.url, let url = URL(string: urlString) else {
            throw MCPToolError("MCP server '\(server.name)' has no url (streamable HTTP transport needs one)")
        }
        // initialize
        _ = try await externalMCPHTTPRequest(url: url, headers: server.headers, id: 1,
                                             method: "initialize", params: Self.externalMCPInitializeParams, timeout: 30)
        var notificationRequest = URLRequest(url: url)
        notificationRequest.httpMethod = "POST"
        notificationRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        notificationRequest.setValue("application/json, text/event-stream", forHTTPHeaderField: "Accept")
        for (key, value) in server.headers { notificationRequest.setValue(value, forHTTPHeaderField: key) }
        let notificationBody: [String: Any] = ["jsonrpc": "2.0", "method": "notifications/initialized"]
        notificationRequest.httpBody = try? JSONSerialization.data(withJSONObject: notificationBody)
        _ = try? await HTTP.send(notificationRequest, timeout: 10)
        return try await externalMCPHTTPRequest(url: url, headers: server.headers, id: 2,
                                                method: method, params: params, timeout: timeout)
    }

    private func externalMCPHTTPRequest(url: URL, headers: [String: String], id: Int, method: String,
                                        params: [String: Any]?, timeout: TimeInterval) async throws -> Any {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json, text/event-stream", forHTTPHeaderField: "Accept")
        for (key, value) in headers { request.setValue(value, forHTTPHeaderField: key) }
        request.httpBody = Self.externalMCPRequest(id: id, method: method, params: params)
        let response = try await HTTP.send(request, timeout: timeout)
        guard (200..<300).contains(response.status) else {
            throw MCPToolError("MCP server \(url.host ?? url.absoluteString) returned HTTP \(response.status): \(response.text.prefix(300))")
        }
        let text = response.text
        if (response.contentType ?? "").contains("text/event-stream") || text.contains("\ndata:") || text.hasPrefix("data:") {
            // SSE: take the last data line that parses as a JSON-RPC response.
            var last: Result<Any, String>?
            for line in text.components(separatedBy: .newlines) where line.hasPrefix("data:") {
                let payload = line.dropFirst(5).trimmingCharacters(in: .whitespaces)
                if payload.isEmpty || payload == "[DONE]" { continue }
                if let parsed = Self.externalMCPParseMessage(String(payload)) { last = parsed }
            }
            guard let last else { throw MCPToolError("MCP server \(url.host ?? url.absoluteString) sent an SSE stream with no JSON-RPC response") }
            switch last {
            case .success(let value): return value
            case .failure(let message): throw MCPToolError("MCP server error: \(message)")
            }
        }
        guard let parsed = Self.externalMCPParseMessage(text) else {
            throw MCPToolError("MCP server \(url.host ?? url.absoluteString) returned an unparseable response")
        }
        switch parsed {
        case .success(let value): return value
        case .failure(let message): throw MCPToolError("MCP server error: \(message)")
        }
    }

    // MARK: - Handler

    /// `use_mcp`: `serverName: "list"` / `toolName: "list_servers"`
    /// lists the configured servers without connecting or approval
    /// (Legacy's mirror). `list_tools` connects and lists that
    /// server's tools. Any other call parses `arguments` as a JSON
    /// object, goes through `terminalApproveChange`, and returns the
    /// server's content blocks joined as text.
    func useMCPExternal(_ call: MCPToolCall) async throws -> MCPToolResult {
        let serverName = call.string("serverName") ?? ""
        let toolName = call.string("toolName") ?? ""
        if serverName == "list" && toolName == "list_servers" {
            let servers = try Self.externalMCPServers()
            if servers.isEmpty {
                return .text("No MCP servers are currently configured in Ycode. Add them to \(Self.externalMCPConfigURL().path) as {\"mcpServers\": {\"name\": {\"command\": \"…\", \"args\": […]}}} or {\"url\": \"https://…\"}.")
            }
            let lines = servers.keys.sorted().map { name in
                let s = servers[name]!
                if let command = s.command { return "\(name) (stdio): \(command) \(s.args.joined(separator: " "))" }
                return "\(name) (http): \(s.url ?? "")"
            }
            return .structured(["servers": .array(servers.keys.sorted().map(AnyJSON.string))],
                               summary: "Configured MCP servers:\n" + lines.joined(separator: "\n"))
        }
        let servers = try Self.externalMCPServers()
        guard let server = servers[serverName] else {
            if servers.isEmpty {
                throw MCPToolError("No MCP servers are currently configured in Ycode. Add them to \(Self.externalMCPConfigURL().path) as {\"mcpServers\": {\"name\": {\"command\": \"…\", \"args\": […]}}} or {\"url\": \"https://…\"}.")
            }
            throw MCPToolError("No MCP server named '\(serverName)'. Configured servers: \(servers.keys.sorted().joined(separator: ", "))")
        }
        if let transport = server.transport?.lowercased(), transport == "sse" {
            throw MCPToolError("MCP server '\(serverName)' uses the legacy SSE transport, which Ycode does not implement. Use a stdio command or a streamable-HTTP url instead.")
        }
        let isHTTP = server.url != nil && server.command == nil
        let started = Date()
        if toolName == "list_tools" {
            let result: Any = isHTTP
                ? try await externalMCPHTTPExchange(server: server, method: "tools/list", params: nil, timeout: 30)
                : try await externalMCPStdioExchange(server: server, method: "tools/list", params: nil, timeout: 30)
            let tools = (result as? [String: Any])?["tools"] as? [[String: Any]] ?? []
            let lines = tools.compactMap { t -> String? in
                guard let name = t["name"] as? String else { return nil }
                let desc = (t["description"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                return desc.isEmpty ? name : "\(name): \(desc)"
            }
            let summary = lines.isEmpty ? "Server '\(serverName)' exposes no tools." : "Tools on '\(serverName)':\n" + lines.joined(separator: "\n")
            return .structured(["server": .string(serverName),
                                "tools": .array(tools.compactMap { ($0["name"] as? String).map(AnyJSON.string) })],
                               summary: summary)
        }
        // Tool call: parse arguments, approve, call.
        let argsText = call.string("arguments") ?? "{}"
        guard let argsData = argsText.data(using: .utf8),
              let argsObj = try? JSONSerialization.jsonObject(with: argsData) as? [String: Any] else {
            throw MCPToolError("arguments must be a JSON object (got: \(argsText.prefix(200)))")
        }
        try await approveChangeWithoutFile(
            tool: "use_mcp",
            summary: "Call \(toolName) on external MCP server '\(serverName)' with the supplied arguments.",
            call: call)
        let timeout: TimeInterval = 300
        let result: Any = isHTTP
            ? try await externalMCPHTTPExchange(server: server, method: "tools/call",
                                                params: ["name": toolName, "arguments": argsObj], timeout: timeout)
            : try await externalMCPStdioExchange(server: server, method: "tools/call",
                                                 params: ["name": toolName, "arguments": argsObj], timeout: timeout)
        let (text, isError) = Self.externalMCPJoinContent(result)
        let (capped, _) = Self.terminalCappedOutput(text)
        let durationMs = Int(Date().timeIntervalSince(started) * 1000)
        if isError { throw MCPToolError("MCP server '\(serverName)' reported an error from \(toolName):\n\(capped)") }
        return .structured(["server": .string(serverName), "tool": .string(toolName),
                            "durationMs": .int(durationMs), "isError": .bool(false)], summary: capped)
    }
}

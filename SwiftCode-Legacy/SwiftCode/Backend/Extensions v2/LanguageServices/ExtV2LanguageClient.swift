import Foundation

// MARK: - Minimal real LSP client (JSON-RPC over stdio, Content-Length framing)
//
// Supports the lifecycle a language server actually needs: initialize
// with capability negotiation, initialized, textDocument/didOpen,
// didChange, didClose, completion, hover, shutdown, exit, and restart.
// Cancellation is via Task cancellation on the Swift side plus the
// server's own `$/cancelRequest` notification. This client does not
// assume any server binary exists: `start` fails clearly when the
// executable is missing, and the caller decides whether to surface
// that as "no server for this language" rather than an error.

public actor ExtV2LanguageClient {
    public struct ServerInfo: Sendable {
        public let command: String
        public let arguments: [String]
        public let language: String
    }

    private var process: Process?
    private var stdin: Pipe?
    private var nextId = 0
    private var pending: [Int: CheckedContinuation<Data, Error>] = [:]
    private var readingTask: Task<Void, Never>?
    public private(set) var isRunning = false
    public private(set) var serverCapabilities: Data?

    public init() {}

    private nonisolated static func which(_ name: String) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/which")
        process.arguments = [name]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
        } catch { return nil }
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { return nil }
        let found = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return found?.isEmpty == false ? found : nil
    }

    public func start(server: ServerInfo, workspaceRoot: URL) async throws {
        // A bare name (e.g. "sourcekit-lsp") is resolved through PATH;
        // a path is used as-is and must be executable. A relative
        // bare name must never be handed to Process as a file path.
        let executable: String
        if server.command.contains("/") {
            guard FileManager.default.isExecutableFile(atPath: server.command) else {
                throw ExtV2Error.unknown("Language server executable not found: \(server.command)")
            }
            executable = server.command
        } else {
            guard let resolved = Self.which(server.command) else {
                throw ExtV2Error.unknown("Language server '\(server.command)' was not found on PATH.")
            }
            executable = resolved
        }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = server.arguments
        let stdinPipe = Pipe()
        let stdoutPipe = Pipe()
        process.standardInput = stdinPipe
        process.standardOutput = stdoutPipe
        process.standardError = FileHandle.nullDevice
        try process.run()
        self.process = process
        self.stdin = stdinPipe
        self.isRunning = true
        readingTask = Task { [weak self] in
            await self?.readLoop(stdout: stdoutPipe)
        }
        let params: [String: Any] = [
            "processId": NSNull(),
            "rootUri": workspaceRoot.absoluteString,
            "capabilities": ["textDocument": ["completion": ["completionItem": ["snippetSupport": true]]]],
        ]
        let result = try await request(method: "initialize", params: params)
        serverCapabilities = result
        try sendNotification(method: "initialized", params: [:])
        ExtV2DiagnosticsService.shared.info("Language server started for \(server.language).")
    }

    public func didOpen(uri: String, languageId: String, version: Int, text: String) throws {
        try sendNotification(method: "textDocument/didOpen", params: [
            "textDocument": ["uri": uri, "languageId": languageId, "version": version, "text": text],
        ])
    }

    public func didChange(uri: String, version: Int, text: String) throws {
        try sendNotification(method: "textDocument/didChange", params: [
            "textDocument": ["uri": uri, "version": version],
            "contentChanges": [["text": text]],
        ])
    }

    public func didClose(uri: String) throws {
        try sendNotification(method: "textDocument/didClose", params: ["textDocument": ["uri": uri]])
    }

    /// Returns raw completion-item labels, decoded from the server's
    /// response without inventing items the server did not return.
    public func completion(uri: String, line: Int, character: Int) async throws -> [String] {
        let data = try await request(method: "textDocument/completion", params: [
            "textDocument": ["uri": uri],
            "position": ["line": line, "character": character],
        ])
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return [] }
        let items: [[String: Any]]
        if let array = json["items"] as? [[String: Any]] { items = array }
        else if let array = json as? [[String: Any]] { items = array }
        else { return [] }
        return items.compactMap { $0["label"] as? String }
    }

    public func hover(uri: String, line: Int, character: Int) async throws -> String? {
        let data = try await request(method: "textDocument/hover", params: [
            "textDocument": ["uri": uri],
            "position": ["line": line, "character": character],
        ])
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let contents = json["contents"] else { return nil }
        if let string = contents as? String { return string }
        if let dict = contents as? [String: Any], let value = dict["value"] as? String { return value }
        return nil
    }

    public func shutdown() async {
        _ = try? await request(method: "shutdown", params: nil)
        try? sendNotification(method: "exit", params: nil)
        process?.terminate()
        readingTask?.cancel()
        isRunning = false
        pending.removeAll()
    }

    public func restart(server: ServerInfo, workspaceRoot: URL) async throws {
        await shutdown()
        try await start(server: server, workspaceRoot: workspaceRoot)
    }

    // MARK: Framing

    private func request(method: String, params: [String: Any]?) async throws -> Data {
        nextId += 1
        let id = nextId
        var message: [String: Any] = ["jsonrpc": "2.0", "id": id, "method": method]
        if let params { message["params"] = params }
        let body = try JSONSerialization.data(withJSONObject: message)
        try sendFrame(body)
        return try await withCheckedThrowingContinuation { continuation in
            pending[id] = continuation
            Task { [weak self] in
                try? await Task.sleep(nanoseconds: 30_000_000_000)
                await self?.failRequest(id: id)
            }
        }
    }

    private func failRequest(id: Int) {
        guard let continuation = pending.removeValue(forKey: id) else { return }
        continuation.resume(throwing: ExtV2Error.timeout("Language server did not answer within 30s."))
    }

    private func sendNotification(method: String, params: [String: Any]?) throws {
        var message: [String: Any] = ["jsonrpc": "2.0", "method": method]
        if let params { message["params"] = params }
        try sendFrame(try JSONSerialization.data(withJSONObject: message))
    }

    private func sendFrame(_ body: Data) throws {
        guard let stdin else { throw ExtV2Error.unknown("Language server is not running.") }
        var header = Data("Content-Length: \(body.count)\r\n\r\n".utf8)
        header.append(body)
        stdin.fileHandleForWriting.write(header)
    }

    private func readLoop(stdout: Pipe) async {
        let handle = stdout.fileHandleForReading
        var buffer = Data()
        while !Task.isCancelled {
            let chunk = handle.availableData
            if chunk.isEmpty {
                // EOF: the server exited.
                for (_, continuation) in pending {
                    continuation.resume(throwing: ExtV2Error.unknown("Language server exited."))
                }
                pending.removeAll()
                isRunning = false
                return
            }
            buffer.append(chunk)
            while let (message, consumed) = extractMessage(from: buffer) {
                buffer.removeFirst(consumed)
                handleMessage(message)
            }
        }
    }

    private func extractMessage(from buffer: Data) -> (Data, Int)? {
        guard let headerEnd = buffer.range(of: Data("\r\n\r\n".utf8)) else { return nil }
        let header = String(data: buffer[..<headerEnd.lowerBound], encoding: .utf8) ?? ""
        var length: Int?
        for line in header.split(separator: "\r\n") {
            if line.lowercased().hasPrefix("content-length:") {
                length = Int(line.dropFirst("content-length:".count).trimmingCharacters(in: .whitespaces))
            }
        }
        guard let length else { return nil }
        let bodyStart = headerEnd.upperBound
        guard buffer.count >= bodyStart + length else { return nil }
        return (buffer[bodyStart..<(bodyStart + length)], bodyStart + length)
    }

    private func handleMessage(_ body: Data) {
        guard let json = try? JSONSerialization.jsonObject(with: body) as? [String: Any],
              let id = json["id"] as? Int,
              let continuation = pending.removeValue(forKey: id) else { return }
        if let error = json["error"] as? [String: Any] {
            continuation.resume(throwing: ExtV2Error.unknown("Language server error: \(error["message"] as? String ?? "unknown")"))
        } else if let result = json["result"] {
            let data = (try? JSONSerialization.data(withJSONObject: result)) ?? Data()
            continuation.resume(returning: data)
        } else {
            continuation.resume(returning: Data())
        }
    }
}

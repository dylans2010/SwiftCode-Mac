import Foundation
import os

private let logger = Logger(subsystem: "com.swiftcode.mcp", category: "MCPClient")

// MARK: - JSON-RPC Messaging Structs

public enum JSONRPCID: Codable, Sendable, Hashable {
    case integer(Int)
    case string(String)
    case null

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let intValue = try? container.decode(Int.self) {
            self = .integer(intValue)
        } else if let stringValue = try? container.decode(String.self) {
            self = .string(stringValue)
        } else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Invalid JSONRPC ID type")
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .integer(let intValue):
            try container.encode(intValue)
        case .string(let stringValue):
            try container.encode(stringValue)
        case .null:
            try container.encodeNil()
        }
    }

    public var integerValue: Int? {
        switch self {
        case .integer(let val): return val
        case .string(let val): return Int(val)
        case .null: return nil
        }
    }
}

public struct JSONRPCRequest: Codable, Sendable {
    public let jsonrpc: String
    public let id: JSONRPCID?
    public let method: String
    public let params: JSONValue?

    public init(id: JSONRPCID?, method: String, params: JSONValue?) {
        self.jsonrpc = "2.0"
        self.id = id
        self.method = method
        self.params = params
    }
}

public struct JSONRPCResponse: Codable, Sendable {
    public let jsonrpc: String
    public let id: JSONRPCID?
    public let result: JSONValue?
    public let error: JSONRPCError?
}

public struct JSONRPCNotification: Codable, Sendable {
    public let jsonrpc: String
    public let method: String
    public let params: JSONValue?

    public init(method: String, params: JSONValue?) {
        self.jsonrpc = "2.0"
        self.method = method
        self.params = params
    }
}

public struct JSONRPCError: Codable, Sendable, Error {
    public let code: Int
    public let message: String
    public let data: JSONValue?
}

// MARK: - MCP Client Connection Class

public final class MCPClient: Sendable {
    public let server: MCPServer
    private let activeProcess = OSAllocatedUnfairLock<Process?>(initialState: nil)
    private let requestIDCounter = OSAllocatedUnfairLock<Int>(initialState: 1)
    private let stdioOutputTask = OSAllocatedUnfairLock<Task<Void, Never>?>(initialState: nil)
    private let writePipe = OSAllocatedUnfairLock<Pipe?>(initialState: nil)
    private let pendingRequests = OSAllocatedUnfairLock<[Int: CheckedContinuation<JSONRPCResponse, Error>]>(initialState: [:])

    public init(server: MCPServer) {
        self.server = server
    }

    private func logEvent(severity: MCPLogSeverity, message: String) {
        let name = server.displayName
        Task { @MainActor in
            MCPLoggingManager.shared.log(severity: severity, serverName: name, message: message)
        }
    }

    private func getNextRequestID() -> Int {
        requestIDCounter.withLock { current in
            let next = current
            current += 1
            return next
        }
    }

    // MARK: - Handshake and Capabilities Negotiation

    public func connect() async throws -> MCPServerMetadata {
        logger.log("Connecting to MCP Server '\(self.server.displayName)' via \(self.server.transport.rawValue)...")
        logEvent(severity: .info, message: "Initiating connection to MCP Server via \(self.server.transport.rawValue)")

        switch server.transport {
        case .stdio:
            try startStdioSubprocess()
        case .http, .https:
            logEvent(severity: .info, message: "Configuring HTTP transport with URL: \(server.urlString)")
            break
        }

        do {
            let metadata = try await performHandshake()
            logger.log("Successfully connected and negotiated handshake with '\(self.server.displayName)'!")
            logEvent(severity: .info, message: "Handshake negotiation succeeded! Server: \(metadata.name) (Version: \(metadata.version), Protocol: \(metadata.protocolVersion))")
            return metadata
        } catch {
            logger.error("Handshake failed with server '\(self.server.displayName)': \(error.localizedDescription)")
            logEvent(severity: .error, message: "Connection handshake failed: \(error.localizedDescription)")
            disconnect()
            throw error
        }
    }

    public func disconnect() {
        logger.log("Disconnecting from MCP Server '\(self.server.displayName)'...")
        logEvent(severity: .info, message: "Disconnecting from server and cleaning up transport resources")

        stdioOutputTask.withLock { task in
            task?.cancel()
            task = nil
        }

        activeProcess.withLock { process in
            if let p = process, p.isRunning {
                p.terminate()
            }
            process = nil
        }

        writePipe.withLock { pipe in
            pipe = nil
        }

        let continuations = pendingRequests.withLock { requests -> [CheckedContinuation<JSONRPCResponse, Error>] in
            let list = Array(requests.values)
            requests.removeAll()
            return list
        }
        for continuation in continuations {
            continuation.resume(throwing: MCPError.connectionFailed("Server disconnected during transaction"))
        }
    }

    // MARK: - Stdio Subprocess Handling

    private func startStdioSubprocess() throws {
        guard let exePath = server.executablePath, !exePath.isEmpty else {
            logEvent(severity: .error, message: "Configuration error: Executable path is missing for stdio transport")
            throw MCPError.invalidConfiguration("Executable path is missing for stdio transport")
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: exePath)
        process.arguments = server.launchArguments ?? []

        logEvent(severity: .info, message: "Launching stdio subprocess: \(exePath) with args: \(server.launchArguments ?? [])")

        var fullEnv = ProcessInfo.processInfo.environment
        if let envVars = server.envVariables {
            for (k, v) in envVars {
                fullEnv[k] = v
            }
        }
        process.environment = fullEnv

        let inPipe = Pipe()
        let outPipe = Pipe()
        let errPipe = Pipe()

        process.standardInput = inPipe
        process.standardOutput = outPipe
        process.standardError = errPipe

        do {
            try process.run()
            logEvent(severity: .info, message: "Stdio subprocess spawned successfully with PID \(process.processIdentifier)")
        } catch {
            logEvent(severity: .error, message: "Failed to launch subprocess '\(exePath)': \(error.localizedDescription)")
            throw MCPError.processLaunchFailed("Failed to launch subprocess '\(exePath)': \(error.localizedDescription)")
        }

        activeProcess.withLock { $0 = process }
        writePipe.withLock { $0 = inPipe }

        // Read error pipe to log warnings
        let errorHandle = errPipe.fileHandleForReading
        Task.detached { [weak self] in
            guard let self = self else { return }
            for try await line in errorHandle.bytes.lines {
                logger.warning("[Server Stderr '\(self.server.displayName)']: \(line)")
            }
        }

        // Handle stdout asynchronously line-by-line
        let outputHandle = outPipe.fileHandleForReading
        let task = Task.detached { [weak self] in
            guard let self = self else { return }
            do {
                for try await line in outputHandle.bytes.lines {
                    self.handleIncomingJSONLine(line)
                }
            } catch {
                logger.error("Error reading output from stdio stream: \(error.localizedDescription)")
            }
        }
        stdioOutputTask.withLock { $0 = task }
    }

    private func handleIncomingJSONLine(_ line: String) {
        guard let data = line.data(using: .utf8) else { return }
        do {
            let response = try JSONDecoder().decode(JSONRPCResponse.self, from: data)
            if let rpcID = response.id, let id = rpcID.integerValue {
                let continuation = pendingRequests.withLock { requests in
                    requests.removeValue(forKey: id)
                }
                continuation?.resume(returning: response)
            }
        } catch {
            logger.error("Failed to decode incoming JSON-RPC line: \(line)")
        }
    }

    // MARK: - Transport Execution Core

    private func performHandshake() async throws -> MCPServerMetadata {
        logEvent(severity: .info, message: "Performing protocol handshake negotiation...")
        // Step 1: Initialize Request
        let clientInfo: [String: JSONValue] = [
            "name": .string("SwiftCodeIDE"),
            "version": .string("1.0.0")
        ]

        let params: [String: JSONValue] = [
            "protocolVersion": .string("2024-11-05"),
            "capabilities": .object([
                "tools": .object([:])
            ]),
            "clientInfo": .object(clientInfo)
        ]

        logEvent(severity: .info, message: "Sending 'initialize' request with protocol version '2024-11-05'")
        let response = try await sendRPCRequest(method: "initialize", params: .object(params))

        guard let resultObj = response.result,
              case .object(let dict) = resultObj else {
            logEvent(severity: .error, message: "Handshake failed: Server did not return a valid result dictionary.")
            throw MCPError.handshakeFailed("Server handshake did not return a valid result dictionary.")
        }

        // Validate protocol version
        guard let serverInfoObj = dict["serverInfo"],
              case .object(let serverInfo) = serverInfoObj,
              case .string(let serverName) = serverInfo["name"] ?? .null,
              case .string(let serverVersion) = serverInfo["version"] ?? .null else {
            logEvent(severity: .error, message: "Handshake failed: Server response is missing metadata.")
            throw MCPError.handshakeFailed("Server handshake response missing metadata.")
        }

        // Retrieve server capabilities
        var protocolVersion = "2024-11-05"
        if let pvObj = dict["protocolVersion"], case .string(let pv) = pvObj {
            protocolVersion = pv
        }

        // Step 2: Send notifications/initialized
        logEvent(severity: .info, message: "Sending protocol notification: 'notifications/initialized'")
        try await sendNotification(method: "notifications/initialized", params: .object([:]))

        logEvent(severity: .info, message: "Protocol handshake negotiation completed successfully.")
        return MCPServerMetadata(name: serverName, version: serverVersion, protocolVersion: protocolVersion)
    }

    public func listTools() async throws -> [MCPTool] {
        logger.log("Listing tools for server '\(self.server.displayName)'...")
        logEvent(severity: .info, message: "Requesting list of available tools (method: 'tools/list')...")
        let response = try await sendRPCRequest(method: "tools/list", params: .object([:]))

        if let error = response.error {
            logEvent(severity: .error, message: "Tool discovery failed: \(error.message)")
            throw MCPError.toolDiscoveryFailed(error.message)
        }

        guard let resultObj = response.result,
              case .object(let dict) = resultObj,
              let toolsObj = dict["tools"],
              case .array(let toolsArray) = toolsObj else {
            logEvent(severity: .error, message: "Tool discovery failed: Server response is missing list of tools.")
            throw MCPError.toolDiscoveryFailed("Server response is missing list of tools.")
        }

        var mcpTools: [MCPTool] = []
        let decoder = JSONDecoder()

        for tObj in toolsArray {
            do {
                let data = try JSONEncoder().encode(tObj)
                let tool = try decoder.decode(MCPTool.self, from: data)
                mcpTools.append(tool)
            } catch {
                logger.error("Error decoding individual tool object: \(error.localizedDescription)")
                logEvent(severity: .warning, message: "Failed to decode individual tool object: \(error.localizedDescription)")
            }
        }

        logger.log("Discovered \(mcpTools.count) tools from '\(self.server.displayName)'.")
        logEvent(severity: .info, message: "Discovered \(mcpTools.count) tools successfully from server.")
        return mcpTools
    }

    public func callTool(name: String, arguments: [String: JSONValue]) async throws -> MCPExecutionResponse {
        logger.log("Executing tool '\(name)' on server '\(self.server.displayName)'...")
        logEvent(severity: .info, message: "Calling tool '\(name)' with arguments: \(arguments)")

        let params: [String: JSONValue] = [
            "name": .string(name),
            "arguments": .object(arguments)
        ]

        let response = try await sendRPCRequest(method: "tools/call", params: .object(params))

        if let error = response.error {
            logEvent(severity: .error, message: "Tool '\(name)' execution failed: \(error.message)")
            throw MCPError.toolExecutionFailed(error.message)
        }

        guard let resultObj = response.result else {
            logEvent(severity: .error, message: "Tool '\(name)' execution failed: Server returned an empty result.")
            throw MCPError.toolExecutionFailed("Server returned an empty result.")
        }

        do {
            let data = try JSONEncoder().encode(resultObj)
            let executionResult = try JSONDecoder().decode(MCPExecutionResponse.self, from: data)
            logEvent(severity: .info, message: "Tool '\(name)' executed successfully. Content block count: \(executionResult.content.count)")
            return executionResult
        } catch {
            logEvent(severity: .error, message: "Tool '\(name)' execution succeeded but decoding output failed: \(error.localizedDescription)")
            throw MCPError.decodingFailed("Failed to decode tool execution output: \(error.localizedDescription)")
        }
    }

    // MARK: - RPC Primitives

    private func sendRPCRequest(method: String, params: JSONValue?) async throws -> JSONRPCResponse {
        let reqID = getNextRequestID()
        let rpcRequest = JSONRPCRequest(id: .integer(reqID), method: method, params: params)

        switch server.transport {
        case .stdio:
            guard let writeHandle = writePipe.withLock({ $0?.fileHandleForWriting }) else {
                throw MCPError.connectionFailed("Stdio pipe is not available.")
            }
            let data = try JSONEncoder().encode(rpcRequest)
            guard var lineData = String(data: data, encoding: .utf8) else {
                throw MCPError.decodingFailed("Failed to encode request payload.")
            }
            lineData += "\n"

            return try await withCheckedThrowingContinuation { continuation in
                pendingRequests.withLock { requests in
                    requests[reqID] = continuation
                }

                do {
                    try writeHandle.write(contentsOf: lineData.data(using: .utf8) ?? Data())
                } catch {
                    pendingRequests.withLock { _ = $0.removeValue(forKey: reqID) }
                    continuation.resume(throwing: MCPError.connectionFailed("Failed to write to stdio pipe: \(error.localizedDescription)"))
                }
            }

        case .http, .https:
            guard let url = URL(string: server.urlString) else {
                throw MCPError.invalidURL("Invalid HTTP/S url: \(server.urlString)")
            }

            var urlRequest = URLRequest(url: url)
            urlRequest.httpMethod = "POST"
            urlRequest.addValue("application/json", forHTTPHeaderField: "Content-Type")
            urlRequest.timeoutInterval = 30.0

            // Apply authentication headers
            let credentialKey = "mcp-server-key-\(server.id.uuidString)"
            let storedSecret = KeychainService.shared.get(forKey: credentialKey) ?? ""

            switch server.authType {
            case .apiKey:
                if !storedSecret.isEmpty {
                    urlRequest.addValue(storedSecret, forHTTPHeaderField: "X-API-Key")
                }
            case .bearerToken, .oauth:
                if !storedSecret.isEmpty {
                    urlRequest.addValue("Bearer \(storedSecret)", forHTTPHeaderField: "Authorization")
                }
            case .envVars:
                if let envs = server.envVariables {
                    for (k, v) in envs {
                        urlRequest.addValue(v, forHTTPHeaderField: "X-Env-\(k)")
                    }
                }
            case .customHeaders:
                if let custom = server.customHeaders {
                    for (k, v) in custom {
                        urlRequest.addValue(v, forHTTPHeaderField: k)
                    }
                }
            default:
                break
            }

            let encoder = JSONEncoder()
            urlRequest.httpBody = try encoder.encode(rpcRequest)

            let (data, response) = try await URLSession.shared.data(for: urlRequest)

            guard let httpResponse = response as? HTTPURLResponse else {
                throw MCPError.connectionFailed("Invalid response type from server.")
            }

            let contentType = httpResponse.value(forHTTPHeaderField: "Content-Type") ?? ""
            let isJSON = contentType.contains("application/json") || contentType.contains("text/json")

            if httpResponse.statusCode != 200 {
                let responseBody = String(data: data, encoding: .utf8) ?? ""
                if isJSON, let errorObj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                    if let rpcError = errorObj["error"] as? [String: Any], let msg = rpcError["message"] as? String {
                        throw MCPError.authenticationFailed("Server error (code \(httpResponse.statusCode)): \(msg)")
                    } else if let msg = errorObj["message"] as? String {
                        throw MCPError.authenticationFailed("Server error (code \(httpResponse.statusCode)): \(msg)")
                    } else if let err = errorObj["error"] as? String {
                        throw MCPError.authenticationFailed("Server error (code \(httpResponse.statusCode)): \(err)")
                    }
                }
                let truncatedBody = responseBody.count > 150 ? String(responseBody.prefix(150)) + "..." : responseBody
                let sanitizedBody = truncatedBody.replacingOccurrences(of: "\n", with: " ")
                throw MCPError.authenticationFailed("Server returned HTTP \(httpResponse.statusCode). Content-Type: \(contentType). Response: \(sanitizedBody.isEmpty ? "[empty]" : sanitizedBody)")
            }

            if !isJSON {
                let responseBody = String(data: data, encoding: .utf8) ?? ""
                let truncated = responseBody.count > 100 ? String(responseBody.prefix(100)) + "..." : responseBody
                throw MCPError.decodingFailed("Expected JSON response but received Content-Type '\(contentType)'. Raw body: \(truncated)")
            }

            do {
                let decodedResponse = try JSONDecoder().decode(JSONRPCResponse.self, from: data)
                return decodedResponse
            } catch {
                let responseBody = String(data: data, encoding: .utf8) ?? ""
                throw MCPError.decodingFailed("Failed to parse JSON-RPC response: \(error.localizedDescription). Payload: \(responseBody)")
            }
        }
    }

    private func sendNotification(method: String, params: JSONValue?) async throws {
        let notification = JSONRPCNotification(method: method, params: params)
        let data = try JSONEncoder().encode(notification)

        switch server.transport {
        case .stdio:
            guard let writeHandle = writePipe.withLock({ $0?.fileHandleForWriting }) else {
                throw MCPError.connectionFailed("Stdio pipe is not available.")
            }
            guard var lineData = String(data: data, encoding: .utf8) else {
                throw MCPError.decodingFailed("Failed to encode notification payload.")
            }
            lineData += "\n"
            try writeHandle.write(contentsOf: lineData.data(using: .utf8) ?? Data())

        case .http, .https:
            guard let url = URL(string: server.urlString) else {
                throw MCPError.invalidURL("Invalid HTTP/S url: \(server.urlString)")
            }

            var urlRequest = URLRequest(url: url)
            urlRequest.httpMethod = "POST"
            urlRequest.addValue("application/json", forHTTPHeaderField: "Content-Type")
            urlRequest.timeoutInterval = 10.0

            let credentialKey = "mcp-server-key-\(server.id.uuidString)"
            let storedSecret = KeychainService.shared.get(forKey: credentialKey) ?? ""

            switch server.authType {
            case .apiKey:
                if !storedSecret.isEmpty {
                    urlRequest.addValue(storedSecret, forHTTPHeaderField: "X-API-Key")
                }
            case .bearerToken, .oauth:
                if !storedSecret.isEmpty {
                    urlRequest.addValue("Bearer \(storedSecret)", forHTTPHeaderField: "Authorization")
                }
            case .envVars:
                if let envs = server.envVariables {
                    for (k, v) in envs {
                        urlRequest.addValue(v, forHTTPHeaderField: "X-Env-\(k)")
                    }
                }
            case .customHeaders:
                if let custom = server.customHeaders {
                    for (k, v) in custom {
                        urlRequest.addValue(v, forHTTPHeaderField: k)
                    }
                }
            default:
                break
            }

            urlRequest.httpBody = data
            _ = try await URLSession.shared.data(for: urlRequest)
        }
    }
}

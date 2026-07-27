import Foundation
import os

private let logger = Logger(subsystem: "com.swiftcode.mcp", category: "MCPClient")

// MARK: - JSON-RPC Messaging Structs

public struct JSONRPCRequest: Codable, Sendable {
    public let jsonrpc: String
    public let id: Int?
    public let method: String
    public let params: JSONValue?

    public init(id: Int?, method: String, params: JSONValue?) {
        self.jsonrpc = "2.0"
        self.id = id
        self.method = method
        self.params = params
    }
}

public struct JSONRPCResponse: Codable, Sendable {
    public let jsonrpc: String
    public let id: Int?
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

        switch server.transport {
        case .stdio:
            try startStdioSubprocess()
        case .http, .https:
            // For stateless HTTP, connection validation is a simple ping or info check during initialization
            break
        }

        do {
            let metadata = try await performHandshake()
            logger.log("Successfully connected and negotiated handshake with '\(self.server.displayName)'!")
            return metadata
        } catch {
            logger.error("Handshake failed with server '\(self.server.displayName)': \(error.localizedDescription)")
            disconnect()
            throw error
        }
    }

    public func disconnect() {
        logger.log("Disconnecting from MCP Server '\(self.server.displayName)'...")

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
            throw MCPError.invalidConfiguration("Executable path is missing for stdio transport")
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: exePath)
        process.arguments = server.launchArguments ?? []

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
        } catch {
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
            if let id = response.id {
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

        let response = try await sendRPCRequest(method: "initialize", params: .object(params))

        guard let resultObj = response.result,
              case .object(let dict) = resultObj else {
            throw MCPError.handshakeFailed("Server handshake did not return a valid result dictionary.")
        }

        // Validate protocol version
        guard let serverInfoObj = dict["serverInfo"],
              case .object(let serverInfo) = serverInfoObj,
              case .string(let serverName) = serverInfo["name"] ?? .null,
              case .string(let serverVersion) = serverInfo["version"] ?? .null else {
            throw MCPError.handshakeFailed("Server handshake response missing metadata.")
        }

        // Retrieve server capabilities
        var protocolVersion = "2024-11-05"
        if let pvObj = dict["protocolVersion"], case .string(let pv) = pvObj {
            protocolVersion = pv
        }

        // Step 2: Send notifications/initialized
        try await sendNotification(method: "notifications/initialized", params: .object([:]))

        return MCPServerMetadata(name: serverName, version: serverVersion, protocolVersion: protocolVersion)
    }

    public func listTools() async throws -> [MCPTool] {
        logger.log("Listing tools for server '\(self.server.displayName)'...")
        let response = try await sendRPCRequest(method: "tools/list", params: .object([:]))

        if let error = response.error {
            throw MCPError.toolDiscoveryFailed(error.message)
        }

        guard let resultObj = response.result,
              case .object(let dict) = resultObj,
              let toolsObj = dict["tools"],
              case .array(let toolsArray) = toolsObj else {
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
            }
        }

        logger.log("Discovered \(mcpTools.count) tools from '\(self.server.displayName)'.")
        return mcpTools
    }

    public func callTool(name: String, arguments: [String: JSONValue]) async throws -> MCPExecutionResponse {
        logger.log("Executing tool '\(name)' on server '\(self.server.displayName)'...")

        let params: [String: JSONValue] = [
            "name": .string(name),
            "arguments": .object(arguments)
        ]

        let response = try await sendRPCRequest(method: "tools/call", params: .object(params))

        if let error = response.error {
            throw MCPError.toolExecutionFailed(error.message)
        }

        guard let resultObj = response.result else {
            throw MCPError.toolExecutionFailed("Server returned an empty result.")
        }

        do {
            let data = try JSONEncoder().encode(resultObj)
            let executionResult = try JSONDecoder().decode(MCPExecutionResponse.self, from: data)
            return executionResult
        } catch {
            throw MCPError.decodingFailed("Failed to decode tool execution output: \(error.localizedDescription)")
        }
    }

    // MARK: - RPC Primitives

    private func sendRPCRequest(method: String, params: JSONValue?) async throws -> JSONRPCResponse {
        let reqID = getNextRequestID()
        let rpcRequest = JSONRPCRequest(id: reqID, method: method, params: params)

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
            case .bearerToken:
                if !storedSecret.isEmpty {
                    urlRequest.addValue("Bearer \(storedSecret)", forHTTPHeaderField: "Authorization")
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

            guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
                let code = (response as? HTTPURLResponse)?.statusCode ?? 0
                throw MCPError.connectionFailed("HTTP transport error: server returned status \(code)")
            }

            let decodedResponse = try JSONDecoder().decode(JSONRPCResponse.self, from: data)
            return decodedResponse
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
            case .bearerToken:
                if !storedSecret.isEmpty {
                    urlRequest.addValue("Bearer \(storedSecret)", forHTTPHeaderField: "Authorization")
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

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

// MARK: - Transport Session Protocol

public protocol MCPTransportSession: Sendable {
    /// Connects the transport and starts receiving incoming messages.
    /// - Parameter messageHandler: A closure called when a JSON-RPC message/response is received from the server.
    func connect(messageHandler: @escaping @Sendable (JSONRPCResponse) -> Void) async throws

    /// Sends a JSON-RPC request and returns the response.
    func send(request: JSONRPCRequest) async throws -> JSONRPCResponse

    /// Sends a JSON-RPC notification.
    func send(notification: JSONRPCNotification) async throws

    /// Gracefully closes and tears down transport resources.
    func disconnect()
}

// MARK: - Stdio Transport Implementation

public final class StdioTransportSession: MCPTransportSession {
    private let server: MCPServer
    private let activeProcess = OSAllocatedUnfairLock<Process?>(initialState: nil)
    private let stdioOutputTask = OSAllocatedUnfairLock<Task<Void, Never>?>(initialState: nil)
    private let writePipe = OSAllocatedUnfairLock<Pipe?>(initialState: nil)
    private let pendingRequests = OSAllocatedUnfairLock<[Int: CheckedContinuation<JSONRPCResponse, Error>]>(initialState: [:])
    private let logEvent: @Sendable (MCPLogSeverity, String) -> Void

    public init(server: MCPServer, logEvent: @escaping @Sendable (MCPLogSeverity, String) -> Void) {
        self.server = server
        self.logEvent = logEvent
    }

    deinit {
        disconnect()
    }

    public func connect(messageHandler: @escaping @Sendable (JSONRPCResponse) -> Void) async throws {
        guard let exePath = server.executablePath, !exePath.isEmpty else {
            logEvent(.error, "Configuration error: Executable path is missing for stdio transport")
            throw MCPError.invalidConfiguration("Executable path is missing for stdio transport")
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: exePath)
        process.arguments = server.launchArguments ?? []

        logEvent(.info, "Launching stdio subprocess: \(exePath) with args: \(server.launchArguments ?? [])")

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
            logEvent(.info, "Stdio subprocess spawned successfully with PID \(process.processIdentifier)")
        } catch {
            logEvent(.error, "Failed to launch subprocess '\(exePath)': \(error.localizedDescription)")
            throw MCPError.processLaunchFailed("Failed to launch subprocess '\(exePath)': \(error.localizedDescription)")
        }

        activeProcess.withLock { $0 = process }
        writePipe.withLock { $0 = inPipe }

        // Read error pipe to log warnings
        let errorHandle = errPipe.fileHandleForReading
        let serverName = server.displayName
        Task.detached {
            do {
                for try await line in errorHandle.bytes.lines {
                    logger.warning("[Server Stderr '\(serverName)']: \(line)")
                }
            } catch {
                // Ignore pipe close errors
            }
        }

        // Handle stdout asynchronously line-by-line
        let outputHandle = outPipe.fileHandleForReading
        let task = Task.detached { [weak self] in
            guard let self = self else { return }
            do {
                for try await line in outputHandle.bytes.lines {
                    guard let data = line.data(using: .utf8) else { continue }
                    do {
                        let response = try JSONDecoder().decode(JSONRPCResponse.self, from: data)
                        if let rpcID = response.id, let id = rpcID.integerValue {
                            let continuation = self.pendingRequests.withLock { $0.removeValue(forKey: id) }
                            if let continuation = continuation {
                                continuation.resume(returning: response)
                            } else {
                                messageHandler(response)
                            }
                        } else {
                            messageHandler(response)
                        }
                    } catch {
                        logger.error("Failed to decode incoming JSON-RPC line: \(line)")
                    }
                }
            } catch {
                logger.error("Error reading output from stdio stream: \(error.localizedDescription)")
            }
        }
        stdioOutputTask.withLock { $0 = task }
    }

    public func send(request: JSONRPCRequest) async throws -> JSONRPCResponse {
        guard let writeHandle = writePipe.withLock({ $0?.fileHandleForWriting }) else {
            throw MCPError.connectionFailed("Stdio pipe is not available.")
        }
        let data = try JSONEncoder().encode(request)
        guard var lineData = String(data: data, encoding: .utf8) else {
            throw MCPError.decodingFailed("Failed to encode request payload.")
        }
        lineData += "\n"

        guard let reqID = request.id?.integerValue else {
            throw MCPError.requestValidationFailed("Request is missing integer ID")
        }

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
    }

    public func send(notification: JSONRPCNotification) async throws {
        guard let writeHandle = writePipe.withLock({ $0?.fileHandleForWriting }) else {
            throw MCPError.connectionFailed("Stdio pipe is not available.")
        }
        let data = try JSONEncoder().encode(notification)
        guard var lineData = String(data: data, encoding: .utf8) else {
            throw MCPError.decodingFailed("Failed to encode notification payload.")
        }
        lineData += "\n"
        try writeHandle.write(contentsOf: lineData.data(using: .utf8) ?? Data())
    }

    public func disconnect() {
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
}

// MARK: - HTTP JSON Transport Implementation

public final class HTTPJSONTransportSession: MCPTransportSession {
    private let server: MCPServer
    private let logEvent: @Sendable (MCPLogSeverity, String) -> Void

    public init(server: MCPServer, logEvent: @escaping @Sendable (MCPLogSeverity, String) -> Void) {
        self.server = server
        self.logEvent = logEvent
    }

    deinit {
        disconnect()
    }

    public func connect(messageHandler: @escaping @Sendable (JSONRPCResponse) -> Void) async throws {
        logEvent(.info, "HTTP JSON transport session connected successfully.")
    }

    public func send(request: JSONRPCRequest) async throws -> JSONRPCResponse {
        guard let url = URL(string: server.urlString) else {
            throw MCPError.invalidURL("Invalid HTTP/S url: \(server.urlString)")
        }

        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = "POST"
        urlRequest.addValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.addValue("application/json, text/event-stream", forHTTPHeaderField: "Accept")
        urlRequest.timeoutInterval = 30.0

        applyAuthAndCustomHeaders(to: &urlRequest)

        let timestamp = Date().formatted(.dateTime.hour().minute().second())
        logEvent(.info, "[\(timestamp)] POST HTTP JSON request \(request.method) to \(url.absoluteString)")
        logEvent(.info, "Request Headers: \(urlRequest.allHTTPHeaderFields ?? [:])")

        let encoder = JSONEncoder()
        urlRequest.httpBody = try encoder.encode(request)

        let (data, response) = try await URLSession.shared.data(for: urlRequest)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw MCPError.connectionFailed("Invalid response type from server.")
        }

        let contentType = httpResponse.value(forHTTPHeaderField: "Content-Type") ?? ""
        let isJSON = contentType.contains("application/json") || contentType.contains("text/json")
        let isSSE = contentType.contains("text/event-stream")

        logEvent(.info, "[\(timestamp)] HTTP Response status code: \(httpResponse.statusCode), Content-Type: \(contentType)")
        logEvent(.info, "Response Headers: \(httpResponse.allHeaderFields)")

        if httpResponse.statusCode != 200 {
            let responseBody = String(data: data, encoding: .utf8) ?? ""
            if isJSON, let errorObj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                if let rpcError = errorObj["error"] as? [String: Any], let msg = rpcError["message"] as? String {
                    throw MCPError.authenticationFailed("Server error (code \(httpResponse.statusCode)): \(msg)")
                } else if let msg = errorObj["message"] as? String {
                    throw MCPError.authenticationFailed("Server error (code \(httpResponse.statusCode)): \(msg)")
                }
            }
            throw MCPError.authenticationFailed("Server returned HTTP \(httpResponse.statusCode). Response: \(responseBody)")
        }

        if isSSE {
            logEvent(.warning, "[\(timestamp)] Server selected Server-Sent Events (SSE) instead of JSON. Routing response to SSE parser.")
            throw MCPError.decodingFailed("Server selected Server-Sent Events (text/event-stream) response instead of JSON. Please configure transport with SSE auto-detection.")
        }

        if !isJSON {
            let responseBody = String(data: data, encoding: .utf8) ?? ""
            throw MCPError.decodingFailed("Expected JSON response but received Content-Type '\(contentType)'. Raw body: \(responseBody)")
        }

        return try JSONDecoder().decode(JSONRPCResponse.self, from: data)
    }

    public func send(notification: JSONRPCNotification) async throws {
        guard let url = URL(string: server.urlString) else {
            throw MCPError.invalidURL("Invalid HTTP/S url: \(server.urlString)")
        }

        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = "POST"
        urlRequest.addValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.addValue("application/json, text/event-stream", forHTTPHeaderField: "Accept")
        urlRequest.timeoutInterval = 10.0

        applyAuthAndCustomHeaders(to: &urlRequest)

        let timestamp = Date().formatted(.dateTime.hour().minute().second())
        logEvent(.info, "[\(timestamp)] POST HTTP JSON notification \(notification.method) to \(url.absoluteString)")
        logEvent(.info, "Request Headers: \(urlRequest.allHTTPHeaderFields ?? [:])")

        urlRequest.httpBody = try JSONEncoder().encode(notification)
        let (data, response) = try await URLSession.shared.data(for: urlRequest)

        if let httpResponse = response as? HTTPURLResponse {
            let contentType = httpResponse.value(forHTTPHeaderField: "Content-Type") ?? ""
            logEvent(.info, "[\(timestamp)] HTTP Notification Response status code: \(httpResponse.statusCode), Content-Type: \(contentType)")
            logEvent(.info, "Response Headers: \(httpResponse.allHeaderFields)")
        }
    }

    public func disconnect() {
        logEvent(.info, "HTTP JSON transport session disconnected.")
    }

    private func applyAuthAndCustomHeaders(to urlRequest: inout URLRequest) {
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
    }
}

// MARK: - HTTP SSE Transport Implementation

public struct SSEEvent {
    public var eventType: String = "message"
    public var data: String = ""
    public var id: String? = nil
    public var retry: String? = nil
}

public final class HTTPSSETransportSession: MCPTransportSession {
    private let server: MCPServer
    private let logEvent: @Sendable (MCPLogSeverity, String) -> Void

    private let activeTask = OSAllocatedUnfairLock<Task<Void, Never>?>(initialState: nil)
    private let isExplicitlyDisconnected = OSAllocatedUnfairLock<Bool>(initialState: false)
    private let messageEndpoint = OSAllocatedUnfairLock<URL?>(initialState: nil)
    private let endpointContinuation = OSAllocatedUnfairLock<CheckedContinuation<URL, Error>?>(initialState: nil)
    private let pendingRequests = OSAllocatedUnfairLock<[Int: CheckedContinuation<JSONRPCResponse, Error>]>(initialState: [:])

    public init(server: MCPServer, logEvent: @escaping @Sendable (MCPLogSeverity, String) -> Void) {
        self.server = server
        self.logEvent = logEvent
    }

    deinit {
        disconnect()
    }

    public func connect(messageHandler: @escaping @Sendable (JSONRPCResponse) -> Void) async throws {
        isExplicitlyDisconnected.withLock { $0 = false }

        guard let baseSSEURL = URL(string: server.urlString) else {
            throw MCPError.invalidURL("Invalid base SSE URL: \(server.urlString)")
        }

        let resolvedEndpoint = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<URL, Error>) in
            endpointContinuation.withLock { $0 = continuation }

            let task = Task.detached { [weak self] in
                guard let self = self else { return }
                await self.runConnectionLoop(url: baseSSEURL, messageHandler: messageHandler)
            }
            activeTask.withLock { $0 = task }
        }

        messageEndpoint.withLock { $0 = resolvedEndpoint }
        logEvent(.info, "SSE Transport session initialized successfully. Message endpoint URI negotiated: \(resolvedEndpoint.absoluteString)")
    }

    private func runConnectionLoop(url: URL, messageHandler: @escaping @Sendable (JSONRPCResponse) -> Void) async {
        var isFirstAttempt = true
        var retryInterval: TimeInterval = 3.0

        while !isExplicitlyDisconnected.withLock({ $0 }) {
            do {
                var urlRequest = URLRequest(url: url)
                urlRequest.httpMethod = "GET"
                urlRequest.addValue("application/json, text/event-stream", forHTTPHeaderField: "Accept")
                urlRequest.timeoutInterval = 60.0

                applyAuthAndCustomHeaders(to: &urlRequest)

                let timestamp = Date().formatted(.dateTime.hour().minute().second())
                logEvent(.info, "[\(timestamp)] Initiating SSE stream GET connection: \(url.absoluteString)")
                logEvent(.info, "Request Headers: \(urlRequest.allHTTPHeaderFields ?? [:])")

                let (bytes, response) = try await URLSession.shared.bytes(for: urlRequest)

                guard let httpResponse = response as? HTTPURLResponse else {
                    throw MCPError.connectionFailed("Invalid response type from server.")
                }

                let contentType = httpResponse.value(forHTTPHeaderField: "Content-Type") ?? ""
                logEvent(.info, "[\(timestamp)] SSE Response status code: \(httpResponse.statusCode), Content-Type: \(contentType)")
                logEvent(.info, "Response Headers: \(httpResponse.allHeaderFields)")

                if httpResponse.statusCode != 200 {
                    throw MCPError.connectionFailed("Server returned HTTP \(httpResponse.statusCode).")
                }

                if !contentType.contains("text/event-stream") {
                    throw MCPError.connectionFailed("Expected Content-Type 'text/event-stream' but received '\(contentType)'.")
                }

                logEvent(.info, "SSE Stream connected. Listening for events...")
                isFirstAttempt = false

                var currentEvent = SSEEvent()
                for try await line in bytes.lines {
                    if isExplicitlyDisconnected.withLock({ $0 }) {
                        break
                    }

                    let trimmedLine = line.trimmingCharacters(in: .whitespacesAndNewlines)
                    if trimmedLine.isEmpty {
                        if !currentEvent.data.isEmpty {
                            await handleParsedEvent(currentEvent, messageHandler: messageHandler)
                        }
                        currentEvent = SSEEvent()
                        continue
                    }

                    if trimmedLine.hasPrefix(":") {
                        logEvent(.info, "SSE keepalive / comment: \(trimmedLine)")
                        continue
                    }

                    let parts = trimmedLine.split(separator: ":", maxSplits: 1)
                    if parts.isEmpty {
                        continue
                    }

                    let key = parts[0].trimmingCharacters(in: .whitespacesAndNewlines)
                    var value = ""
                    if parts.count > 1 {
                        let valStr = String(parts[1])
                        if valStr.hasPrefix(" ") {
                            value = String(valStr.dropFirst())
                        } else {
                            value = valStr
                        }
                    }

                    switch key {
                    case "event":
                        currentEvent.eventType = value
                    case "data":
                        if currentEvent.data.isEmpty {
                            currentEvent.data = value
                        } else {
                            currentEvent.data += "\n" + value
                        }
                    case "id":
                        currentEvent.id = value
                    case "retry":
                        currentEvent.retry = value
                        if let ms = Int(value) {
                            retryInterval = TimeInterval(ms) / 1000.0
                        }
                    default:
                        logEvent(.info, "Unknown SSE field: \(key)")
                    }
                }
            } catch {
                if isExplicitlyDisconnected.withLock({ $0 }) {
                    break
                }

                logEvent(.warning, "SSE Stream connection lost: \(error.localizedDescription)")

                if isFirstAttempt {
                    let continuation = endpointContinuation.withLock { $0 }
                    endpointContinuation.withLock { $0 = nil }
                    continuation?.resume(throwing: error)
                    break
                }

                logEvent(.info, "Attempting reconnect in \(retryInterval) seconds...")
                try? await Task.sleep(nanoseconds: UInt64(retryInterval * 1_000_000_000))
            }
        }
    }

    private func handleParsedEvent(_ event: SSEEvent, messageHandler: @escaping @Sendable (JSONRPCResponse) -> Void) async {
        let timestamp = Date().formatted(.dateTime.hour().minute().second())
        logEvent(.info, "[\(timestamp)] SSE Event: \(event.eventType), Data length: \(event.data.count) chars")

        switch event.eventType {
        case "endpoint":
            guard let baseSSEURL = URL(string: server.urlString),
                  let resolvedURL = URL(string: event.data, relativeTo: baseSSEURL) else {
                let errorMsg = "Malformed endpoint URI received from SSE: \(event.data)"
                logEvent(.error, errorMsg)
                if let continuation = endpointContinuation.withLock({ $0 }) {
                    endpointContinuation.withLock { $0 = nil }
                    continuation.resume(throwing: MCPError.connectionFailed(errorMsg))
                }
                return
            }

            if let continuation = endpointContinuation.withLock({ $0 }) {
                endpointContinuation.withLock { $0 = nil }
                continuation.resume(returning: resolvedURL)
            } else {
                messageEndpoint.withLock { $0 = resolvedURL }
                logEvent(.info, "SSE message endpoint updated: \(resolvedURL.absoluteString)")
            }

        case "message":
            guard let data = event.data.data(using: .utf8) else { return }
            do {
                let response = try JSONDecoder().decode(JSONRPCResponse.self, from: data)
                if let rpcID = response.id, let id = rpcID.integerValue {
                    let continuation = pendingRequests.withLock { $0.removeValue(forKey: id) }
                    if let continuation = continuation {
                        continuation.resume(returning: response)
                    } else {
                        messageHandler(response)
                    }
                } else {
                    messageHandler(response)
                }
            } catch {
                let truncated = event.data.count > 150 ? String(event.data.prefix(150)) + "..." : event.data
                logEvent(.error, "Failed to decode JSON-RPC response from event stream: \(error.localizedDescription). Payload: \(truncated)")
            }

        default:
            logEvent(.info, "Ignored event type: \(event.eventType)")
        }
    }

    public func send(request: JSONRPCRequest) async throws -> JSONRPCResponse {
        guard let postURL = messageEndpoint.withLock({ $0 }) else {
            throw MCPError.connectionFailed("No active SSE message endpoint available.")
        }

        var urlRequest = URLRequest(url: postURL)
        urlRequest.httpMethod = "POST"
        urlRequest.addValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.addValue("application/json, text/event-stream", forHTTPHeaderField: "Accept")
        urlRequest.timeoutInterval = 30.0

        applyAuthAndCustomHeaders(to: &urlRequest)

        let timestamp = Date().formatted(.dateTime.hour().minute().second())
        logEvent(.info, "[\(timestamp)] POST HTTP JSON request \(request.method) to SSE endpoint \(postURL.absoluteString)")
        logEvent(.info, "Request Headers: \(urlRequest.allHTTPHeaderFields ?? [:])")

        let encoder = JSONEncoder()
        urlRequest.httpBody = try encoder.encode(request)

        guard let reqID = request.id?.integerValue else {
            throw MCPError.requestValidationFailed("Request is missing integer ID")
        }

        return try await withCheckedThrowingContinuation { continuation in
            pendingRequests.withLock { requests in
                requests[reqID] = continuation
            }

            Task {
                do {
                    let (data, response) = try await URLSession.shared.data(for: urlRequest)
                    guard let httpResponse = response as? HTTPURLResponse else {
                        throw MCPError.connectionFailed("Invalid response type from server.")
                    }

                    let contentType = httpResponse.value(forHTTPHeaderField: "Content-Type") ?? ""
                    logEvent(.info, "[\(timestamp)] POST Response status code: \(httpResponse.statusCode), Content-Type: \(contentType)")
                    logEvent(.info, "Response Headers: \(httpResponse.allHeaderFields)")

                    if httpResponse.statusCode != 200 && httpResponse.statusCode != 202 {
                        let responseBody = String(data: data, encoding: .utf8) ?? ""
                        throw MCPError.authenticationFailed("Server returned HTTP \(httpResponse.statusCode). Response: \(responseBody)")
                    }

                    if (contentType.contains("application/json") || contentType.contains("text/json")), !data.isEmpty {
                        do {
                            let immediateResponse = try JSONDecoder().decode(JSONRPCResponse.self, from: data)
                            if let removed = pendingRequests.withLock({ $0.removeValue(forKey: reqID) }) {
                                removed.resume(returning: immediateResponse)
                            }
                        } catch {
                            // Suppress and wait for asynchronous SSE push
                            logEvent(.info, "Failed to decode immediate HTTP POST response payload. Waiting for event stream response instead.")
                        }
                    } else if contentType.contains("text/event-stream") {
                        logEvent(.info, "Server responded with text/event-stream Content-Type to POST request. Handling response via event stream parser.")
                        // We do NOT attempt to decode as raw JSON
                    }
                } catch {
                    if let removed = pendingRequests.withLock({ $0.removeValue(forKey: reqID) }) {
                        removed.resume(throwing: error)
                    }
                }
            }
        }
    }

    public func send(notification: JSONRPCNotification) async throws {
        guard let postURL = messageEndpoint.withLock({ $0 }) else {
            throw MCPError.connectionFailed("No active SSE message endpoint available.")
        }

        var urlRequest = URLRequest(url: postURL)
        urlRequest.httpMethod = "POST"
        urlRequest.addValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.addValue("application/json, text/event-stream", forHTTPHeaderField: "Accept")
        urlRequest.timeoutInterval = 10.0

        applyAuthAndCustomHeaders(to: &urlRequest)

        let timestamp = Date().formatted(.dateTime.hour().minute().second())
        logEvent(.info, "[\(timestamp)] POST HTTP JSON notification \(notification.method) to SSE endpoint \(postURL.absoluteString)")
        logEvent(.info, "Request Headers: \(urlRequest.allHTTPHeaderFields ?? [:])")

        urlRequest.httpBody = try JSONEncoder().encode(notification)
        let (data, response) = try await URLSession.shared.data(for: urlRequest)

        if let httpResponse = response as? HTTPURLResponse {
            let contentType = httpResponse.value(forHTTPHeaderField: "Content-Type") ?? ""
            logEvent(.info, "[\(timestamp)] HTTP SSE Notification Response status: \(httpResponse.statusCode), Content-Type: \(contentType)")
            logEvent(.info, "Response Headers: \(httpResponse.allHeaderFields)")
        }
    }

    public func disconnect() {
        isExplicitlyDisconnected.withLock { $0 = true }

        activeTask.withLock { task in
            task?.cancel()
            task = nil
        }

        let continuations = pendingRequests.withLock { requests -> [CheckedContinuation<JSONRPCResponse, Error>] in
            let list = Array(requests.values)
            requests.removeAll()
            return list
        }
        for continuation in continuations {
            continuation.resume(throwing: MCPError.connectionFailed("Transport disconnected"))
        }

        logEvent(.info, "SSE transport session disconnected.")
    }

    private func applyAuthAndCustomHeaders(to urlRequest: inout URLRequest) {
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
    }
}

// MARK: - MCP Client Connection Class

public final class MCPClient: Sendable {
    public let server: MCPServer
    private let requestIDCounter = OSAllocatedUnfairLock<Int>(initialState: 1)
    private let activeSession = OSAllocatedUnfairLock<MCPTransportSession?>(initialState: nil)

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
            let session = StdioTransportSession(server: server) { [weak self] severity, message in
                self?.logEvent(severity: severity, message: message)
            }
            activeSession.withLock { $0 = session }

        case .http, .https:
            logEvent(severity: .info, message: "Detecting remote transport type at: \(server.urlString)")

            let detectedTransport = await detectRemoteTransport()
            if detectedTransport == .sse {
                logEvent(severity: .info, message: "Detected text/event-stream content. Instantiating Server-Sent Events (SSE) transport.")
                let session = HTTPSSETransportSession(server: server) { [weak self] severity, message in
                    self?.logEvent(severity: severity, message: message)
                }
                activeSession.withLock { $0 = session }
            } else {
                logEvent(severity: .info, message: "Detected standard HTTP JSON response content. Instantiating HTTP JSON transport.")
                let session = HTTPJSONTransportSession(server: server) { [weak self] severity, message in
                    self?.logEvent(severity: severity, message: message)
                }
                activeSession.withLock { $0 = session }
            }
        }

        guard let session = activeSession.withLock({ $0 }) else {
            throw MCPError.connectionFailed("No active transport session initialized.")
        }

        do {
            try await session.connect { [weak self] unsolicitedMessage in
                self?.handleUnsolicitedMessage(unsolicitedMessage)
            }

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

        let session = activeSession.withLock { current -> MCPTransportSession? in
            let s = current
            current = nil
            return s
        }
        session?.disconnect()
    }

    private func handleUnsolicitedMessage(_ message: JSONRPCResponse) {
        logEvent(severity: .info, message: "Received unsolicited JSON-RPC message: \(message.jsonrpc)")
    }

    // MARK: - Auto Detection

    private enum DetectedTransport {
        case json
        case sse
    }

    private func detectRemoteTransport() async -> DetectedTransport {
        guard let url = URL(string: server.urlString) else {
            return .json
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.addValue("application/json, text/event-stream", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 5.0

        // Apply authentication headers
        let credentialKey = "mcp-server-key-\(server.id.uuidString)"
        let storedSecret = KeychainService.shared.get(forKey: credentialKey) ?? ""

        switch server.authType {
        case .apiKey:
            if !storedSecret.isEmpty {
                request.addValue(storedSecret, forHTTPHeaderField: "X-API-Key")
            }
        case .bearerToken, .oauth:
            if !storedSecret.isEmpty {
                request.addValue("Bearer \(storedSecret)", forHTTPHeaderField: "Authorization")
            }
        case .envVars:
            if let envs = server.envVariables {
                for (k, v) in envs {
                    request.addValue(v, forHTTPHeaderField: "X-Env-\(k)")
                }
            }
        case .customHeaders:
            if let custom = server.customHeaders {
                for (k, v) in custom {
                    request.addValue(v, forHTTPHeaderField: k)
                }
            }
        default:
            break
        }

        logEvent(severity: .info, message: "Initiating dynamic transport detection GET request to: \(url.absoluteString)")
        logEvent(severity: .info, message: "Outgoing request headers: \(request.allHTTPHeaderFields ?? [:])")

        do {
            let (_, response) = try await URLSession.shared.bytes(for: request)
            if let httpResponse = response as? HTTPURLResponse {
                let contentType = httpResponse.value(forHTTPHeaderField: "Content-Type") ?? ""
                logEvent(severity: .info, message: "Transport detection response status: \(httpResponse.statusCode), Content-Type: \(contentType)")
                logEvent(severity: .info, message: "Response Headers: \(httpResponse.allHeaderFields)")

                if contentType.contains("text/event-stream") {
                    logEvent(severity: .info, message: "Transport negotiation result: SERVER-SENT EVENTS (SSE)")
                    return .sse
                } else {
                    logEvent(severity: .info, message: "Transport negotiation result: HTTP JSON")
                    return .json
                }
            }
        } catch {
            logger.warning("Dynamic transport detection request failed: \(error.localizedDescription). Falling back to JSON transport.")
            logEvent(severity: .warning, message: "Dynamic transport detection failed with error: \(error.localizedDescription). Falling back to JSON transport.")
        }

        return .json
    }

    // MARK: - Transport Execution Core

    private func performHandshake() async throws -> MCPServerMetadata {
        logEvent(severity: .info, message: "Performing protocol handshake negotiation...")
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

        guard let serverInfoObj = dict["serverInfo"],
              case .object(let serverInfo) = serverInfoObj,
              case .string(let serverName) = serverInfo["name"] ?? .null,
              case .string(let serverVersion) = serverInfo["version"] ?? .null else {
            logEvent(severity: .error, message: "Handshake failed: Server response is missing metadata.")
            throw MCPError.handshakeFailed("Server handshake response missing metadata.")
        }

        var protocolVersion = "2024-11-05"
        if let pvObj = dict["protocolVersion"], case .string(let pv) = pvObj {
            protocolVersion = pv
        }

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

        guard let session = activeSession.withLock({ $0 }) else {
            throw MCPError.connectionFailed("No active transport session to send request.")
        }

        return try await session.send(request: rpcRequest)
    }

    private func sendNotification(method: String, params: JSONValue?) async throws {
        let notification = JSONRPCNotification(method: method, params: params)

        guard let session = activeSession.withLock({ $0 }) else {
            throw MCPError.connectionFailed("No active transport session to send notification.")
        }

        try await session.send(notification: notification)
    }
}

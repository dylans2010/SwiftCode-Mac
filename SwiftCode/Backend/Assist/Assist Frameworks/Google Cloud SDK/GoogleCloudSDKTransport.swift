//
//  GoogleCloudSDKTransport.swift
//  SwiftCode
//
//  Unix domain socket IPC transport implementing structured JSON-RPC 2.0 framing.
//

import Foundation
import Darwin
import os

private let logger = Logger(subsystem: "com.swiftcode.GoogleCloudSDK", category: "GoogleCloudSDKTransport")

public actor GoogleCloudSDKTransport {
    private var socketFD: Int32 = -1
    private var readTask: Task<Void, Never>?
    private var pendingRequests: [String: CheckedContinuation<GoogleCloudSDKResponse, Error>] = [:]
    private var requestTimeoutTasks: [String: Task<Void, Never>] = [:]
    private var eventContinuations: [UUID: AsyncStream<GoogleCloudSDKEvent>.Continuation] = [:]
    private var toolExecutionHandler: (@Sendable (GoogleCloudSDKToolExecutionRequest) async -> (success: Bool, result: String?, error: String?))?

    public init() {}

    deinit {
        let fd = socketFD
        if fd >= 0 {
            Darwin.close(fd)
        }
    }

    /// Sets the handler closure for incoming server-initiated tool execution requests (`tool.execute`).
    public func setToolExecutionHandler(_ handler: @escaping @Sendable (GoogleCloudSDKToolExecutionRequest) async -> (success: Bool, result: String?, error: String?)) {
        self.toolExecutionHandler = handler
    }

    /// Establishes connection to the Unix domain socket at the given path.
    public func connect(to socketPath: String, timeout: TimeInterval = 10.0) async throws {
        disconnect()

        let startTime = Date()
        var lastErr: Int32 = 0

        // Poll for socket file availability (bridge may still be launching)
        while Date().timeIntervalSince(startTime) < timeout {
            if FileManager.default.fileExists(atPath: socketPath) {
                let fd = Darwin.socket(AF_UNIX, SOCK_STREAM, 0)
                guard fd >= 0 else {
                    throw GoogleCloudSDKError.socketConnectionFailed("Failed to create socket descriptor: \(errno)")
                }

                var addr = sockaddr_un()
                addr.sun_family = sa_family_t(AF_UNIX)

                let pathBytes = socketPath.utf8CString
                guard pathBytes.count <= MemoryLayout.size(ofValue: addr.sun_path) else {
                    Darwin.close(fd)
                    throw GoogleCloudSDKError.socketConnectionFailed("Socket path exceeds maximum AF_UNIX length")
                }

                _ = withUnsafeMutablePointer(to: &addr.sun_path) { ptr in
                    ptr.withMemoryRebound(to: CChar.self, capacity: pathBytes.count) { dest in
                        _ = pathBytes.withUnsafeBufferPointer { src in
                            memcpy(dest, src.baseAddress!, src.count)
                        }
                    }
                }

                let connectRes = withUnsafePointer(to: &addr) { ptr in
                    ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { saPtr in
                        Darwin.connect(fd, saPtr, socklen_t(MemoryLayout<sockaddr_un>.size))
                    }
                }

                if connectRes == 0 {
                    self.socketFD = fd
                    logger.info("Successfully connected to Antigravity socket: \(socketPath)")
                    startReading()
                    return
                } else {
                    lastErr = errno
                    Darwin.close(fd)
                }
            }
            try await Task.sleep(nanoseconds: 100_000_000) // 100ms
        }

        throw GoogleCloudSDKError.socketConnectionFailed("Timed out waiting for socket '\(socketPath)' (errno: \(lastErr))")
    }

    /// Disconnects from the socket and cleans up pending requests.
    public func disconnect() {
        readTask?.cancel()
        readTask = nil

        if socketFD >= 0 {
            Darwin.close(socketFD)
            socketFD = -1
        }

        for (_, cont) in pendingRequests {
            cont.resume(throwing: GoogleCloudSDKError.socketConnectionFailed("Connection closed"))
        }
        pendingRequests.removeAll()
        for (_, timeoutTask) in requestTimeoutTasks {
            timeoutTask.cancel()
        }
        requestTimeoutTasks.removeAll()

        for (_, cont) in eventContinuations {
            cont.finish()
        }
        eventContinuations.removeAll()
    }

    /// Subscribes to the broadcast stream of incoming runtime events.
    public func subscribeEvents() -> AsyncStream<GoogleCloudSDKEvent> {
        let id = UUID()
        return AsyncStream { continuation in
            self.eventContinuations[id] = continuation
            continuation.onTermination = { [weak self] _ in
                Task { [weak self] in
                    await self?.removeContinuation(id: id)
                }
            }
        }
    }

    private func removeContinuation(id: UUID) {
        eventContinuations.removeValue(forKey: id)
    }

    /// Sends a JSON-RPC 2.0 request and awaits the matching response.
    public func sendRequest(method: String, params: [String: Any] = [:], timeout: TimeInterval = 60.0) async throws -> GoogleCloudSDKResponse {
        guard socketFD >= 0 else {
            throw GoogleCloudSDKError.socketConnectionFailed("Socket is not connected")
        }

        let id = UUID().uuidString
        let payload: [String: Any] = [
            "jsonrpc": "2.0",
            "id": id,
            "method": method,
            "params": params,
        ]

        guard let data = try? JSONSerialization.data(withJSONObject: payload),
              let jsonString = String(data: data, encoding: .utf8) else {
            throw GoogleCloudSDKError.malformedMessage("Failed to serialize request payload")
        }

        let message = jsonString + "\n"

        return try await withCheckedThrowingContinuation { continuation in
            self.pendingRequests[id] = continuation

            Task { [weak self] in
                guard let self else { return }
                let timeoutTask = Task { [weak self] in
                    do {
                        try await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
                    } catch {
                        return
                    }
                    await self?.expireRequest(id: id, method: method)
                }
                self.requestTimeoutTasks[id] = timeoutTask

                do {
                    try self.writeRaw(message)
                } catch {
                    self.failRequest(id: id, error: error)
                    return
                }
            }
        }
    }

    private func expireRequest(id: String, method: String) {
        requestTimeoutTasks.removeValue(forKey: id)
        guard let continuation = pendingRequests.removeValue(forKey: id) else { return }
        continuation.resume(throwing: GoogleCloudSDKError.requestTimeout(method: method))
    }

    private func failRequest(id: String, error: Error) {
        requestTimeoutTasks.removeValue(forKey: id)?.cancel()
        guard let continuation = pendingRequests.removeValue(forKey: id) else { return }
        continuation.resume(throwing: error)
    }

    private func writeRaw(_ string: String) throws {
        guard socketFD >= 0 else {
            throw GoogleCloudSDKError.socketConnectionFailed("Socket is not connected")
        }

        let data = Array(string.utf8)
        var totalWritten = 0
        while totalWritten < data.count {
            let written = data.withUnsafeBufferPointer { buffer in
                Darwin.write(socketFD, buffer.baseAddress! + totalWritten, data.count - totalWritten)
            }
            if written < 0 {
                throw GoogleCloudSDKError.socketConnectionFailed("Socket write error: \(errno)")
            }
            totalWritten += written
        }
    }

    private func startReading() {
        let fd = self.socketFD
        readTask = Task.detached(priority: .userInitiated) { [weak self] in
            var buffer = [UInt8](repeating: 0, count: 8192)
            var lineBuffer = Data()

            while !Task.isCancelled {
                let bytesRead = Darwin.read(fd, &buffer, buffer.count)
                if bytesRead <= 0 {
                    logger.info("Socket EOF or read error (bytesRead: \(bytesRead), errno: \(errno))")
                    break
                }

                lineBuffer.append(buffer, count: bytesRead)

                while let newlineIndex = lineBuffer.firstIndex(of: UInt8(ascii: "\n")) {
                    let lineData = lineBuffer.subdata(in: 0..<newlineIndex)
                    lineBuffer.removeSubrange(0...newlineIndex)

                    if let lineString = String(data: lineData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
                       !lineString.isEmpty {
                        await self?.handleIncomingLine(lineString)
                    }
                }
            }

            await self?.disconnect()
        }
    }

    private func handleIncomingLine(_ line: String) async {
        guard let data = line.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            logger.warning("Received invalid JSON from socket: \(line)")
            return
        }

        // 1. Check for incoming server-initiated JSON-RPC request (has "method" AND "id")
        if let method = json["method"] as? String, let id = json["id"] {
            let params = json["params"] as? [String: Any] ?? [:]
            if method == "tool.execute" {
                let reqId = "\(id)"
                let sessionId = params["sessionId"] as? String ?? ""
                let toolName = params["toolName"] as? String ?? ""
                let arguments = params["arguments"] as? [String: Any] ?? [:]

                let request = GoogleCloudSDKToolExecutionRequest(requestId: reqId, sessionId: sessionId, toolName: toolName, arguments: arguments)

                Task { [weak self] in
                    await self?.executeTool(request: request, reqId: reqId)
                }
                return
            }
        }

        // 2. Response matching (has "id" but NO "method")
        if let id = json["id"] as? String {
            if let cont = pendingRequests.removeValue(forKey: id) {
                requestTimeoutTasks.removeValue(forKey: id)?.cancel()
                if let errorObj = json["error"] as? [String: Any] {
                    let code = errorObj["code"] as? Int ?? -1
                    let msg = errorObj["message"] as? String ?? "Unknown bridge error"
                    cont.resume(throwing: GoogleCloudSDKError.internalError(code: code, message: msg))
                } else if let result = json["result"] as? [String: Any] {
                    var responseData: [String: JSONValue] = [:]
                    for (k, v) in result {
                        responseData[k] = Self.toJSONValue(v)
                    }
                    cont.resume(returning: GoogleCloudSDKResponse(responseData))
                } else {
                    cont.resume(returning: GoogleCloudSDKResponse([:]))
                }
            }
            return
        }

        // 3. Notification / Event matching (has "method" but NO "id")
        if let method = json["method"] as? String {
            let params = json["params"] as? [String: Any] ?? [:]
            dispatchNotification(method: method, params: params)
        }
    }

    private func executeTool(request: GoogleCloudSDKToolExecutionRequest, reqId: String) async {
        if let handler = self.toolExecutionHandler {
            let resultTuple = await handler(request)
            sendToolExecutionResponse(reqId: reqId, success: resultTuple.success, result: resultTuple.result, error: resultTuple.error)
        } else {
            sendToolExecutionResponse(reqId: reqId, success: false, result: nil, error: "No tool execution handler registered in Swift")
        }
    }

    private func sendToolExecutionResponse(reqId: String, success: Bool, result: String?, error: String?) {
        var payload: [String: Any] = [
            "jsonrpc": "2.0",
            "id": reqId,
        ]

        if success {
            payload["result"] = [
                "success": true,
                "result": result ?? "",
            ]
        } else {
            payload["result"] = [
                "success": false,
                "error": error ?? "Tool execution failed",
            ]
        }

        if let data = try? JSONSerialization.data(withJSONObject: payload),
           let jsonString = String(data: data, encoding: .utf8) {
            try? writeRaw(jsonString + "\n")
        }
    }

    private func dispatchNotification(method: String, params: [String: Any]) {
        let event: GoogleCloudSDKEvent?

        switch method {
        case "runtime.ready":
            let version = params["version"] as? String ?? "0.1.20"
            let pid = Int32(params["pid"] as? Int ?? 0)
            event = .runtimeReady(version: version, pid: pid)

        case "agent.started":
            let sessionId = params["sessionId"] as? String ?? ""
            let prompt = params["prompt"] as? String
            event = .agentStarted(sessionId: sessionId, prompt: prompt)

        case "agent.progress":
            let sessionId = params["sessionId"] as? String ?? ""
            let delta = params["delta"] as? String
            let thoughtDelta = params["thoughtDelta"] as? String
            event = .agentProgress(sessionId: sessionId, delta: delta, thoughtDelta: thoughtDelta)

        case "agent.completed":
            let sessionId = params["sessionId"] as? String ?? ""
            let response = params["response"] as? String ?? ""
            let stopReason = params["stopReason"] as? String
            var usage: GoogleCloudSDKUsage? = nil
            if let usageDict = params["usage"] as? [String: Any] {
                usage = GoogleCloudSDKUsage(
                    promptTokens: usageDict["promptTokens"] as? Int ?? 0,
                    completionTokens: usageDict["completionTokens"] as? Int ?? 0,
                    totalTokens: usageDict["totalTokens"] as? Int ?? 0
                )
            }
            event = .agentCompleted(sessionId: sessionId, response: response, stopReason: stopReason, usage: usage)

        case "agent.failed":
            let sessionId = params["sessionId"] as? String ?? ""
            let err = params["error"] as? String ?? "Unknown error"
            event = .agentFailed(sessionId: sessionId, error: err)

        case "tool.started":
            let sessionId = params["sessionId"] as? String ?? ""
            let callId = params["toolCallId"] as? String ?? UUID().uuidString
            let toolName = params["toolName"] as? String ?? ""
            let args = params["args"] as? [String: Any] ?? [:]
            let rawArgs = (try? JSONSerialization.data(withJSONObject: args)).flatMap { String(data: $0, encoding: .utf8) } ?? "{}"
            let tool = GoogleCloudSDKToolEvent(id: callId, sessionId: sessionId, name: toolName, rawArgs: rawArgs)
            event = .toolStarted(tool: tool)

        case "tool.completed":
            let sessionId = params["sessionId"] as? String ?? ""
            let callId = params["toolCallId"] as? String ?? ""
            let toolName = params["toolName"] as? String ?? ""
            let result = params["result"] as? String ?? ""
            let toolRes = GoogleCloudSDKToolResult(id: callId, sessionId: sessionId, name: toolName, result: result)
            event = .toolCompleted(result: toolRes)

        case "tool.failed":
            let sessionId = params["sessionId"] as? String ?? ""
            let callId = params["toolCallId"] as? String ?? ""
            let toolName = params["toolName"] as? String ?? ""
            let err = params["error"] as? String ?? ""
            event = .toolFailed(toolId: callId, toolName: toolName, error: err)

        case "worker.started":
            let sessionId = params["sessionId"] as? String ?? ""
            let workerId = params["workerId"] as? String ?? ""
            let name = params["name"] as? String ?? ""
            let args = params["args"] as? [String: Any] ?? [:]
            let rawArgs = (try? JSONSerialization.data(withJSONObject: args)).flatMap { String(data: $0, encoding: .utf8) } ?? "{}"
            event = .workerStarted(sessionId: sessionId, workerId: workerId, name: name, args: rawArgs)

        case "worker.progress":
            let sessionId = params["sessionId"] as? String ?? ""
            let workerId = params["workerId"] as? String ?? ""
            let prog = params["progress"] as? String ?? ""
            event = .workerProgress(sessionId: sessionId, workerId: workerId, progress: prog)

        case "worker.completed":
            let sessionId = params["sessionId"] as? String ?? ""
            let workerId = params["workerId"] as? String ?? ""
            let result = params["result"] as? String ?? ""
            event = .workerCompleted(sessionId: sessionId, workerId: workerId, result: result)

        case "worker.failed":
            let sessionId = params["sessionId"] as? String ?? ""
            let workerId = params["workerId"] as? String ?? ""
            let err = params["error"] as? String ?? ""
            event = .workerFailed(sessionId: sessionId, workerId: workerId, error: err)

        case "error":
            let msg = params["message"] as? String ?? "Unknown error"
            event = .error(message: msg)

        default:
            logger.debug("Unhandled notification method: \(method)")
            event = nil
        }

        if let event = event {
            for (_, cont) in eventContinuations {
                cont.yield(event)
            }
        }
    }

    private static func toJSONValue(_ value: Any) -> JSONValue {
        switch value {
        case let str as String:
            return .string(str)
        case let bool as Bool:
            return .boolean(bool)
        case let num as NSNumber:
            if CFGetTypeID(num) == CFBooleanGetTypeID() {
                return .boolean(num.boolValue)
            }
            return .number(num.doubleValue)
        case let dict as [String: Any]:
            var obj: [String: JSONValue] = [:]
            for (k, v) in dict {
                obj[k] = toJSONValue(v)
            }
            return .object(obj)
        case let arr as [Any]:
            return .array(arr.map { toJSONValue($0) })
        default:
            return .null
        }
    }
}

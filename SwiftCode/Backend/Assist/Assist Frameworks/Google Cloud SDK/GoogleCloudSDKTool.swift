//
//  GoogleCloudSDKTool.swift
//  SwiftCode
//
//  Native representation of Antigravity SDK tool calls, inputs, and results.
//

import Foundation

public struct GoogleCloudSDKToolExecutionRequest: Sendable {
    public let requestId: String
    public let sessionId: String
    public let toolName: String
    public let arguments: [String: Any]

    public init(requestId: String, sessionId: String, toolName: String, arguments: [String: Any]) {
        self.requestId = requestId
        self.sessionId = sessionId
        self.toolName = toolName
        self.arguments = arguments
    }
}

public struct GoogleCloudSDKToolEvent: Identifiable, Sendable, Codable {
    public let id: String
    public let sessionId: String
    public let name: String
    public let rawArgs: String
    public let timestamp: Date

    public init(id: String, sessionId: String, name: String, rawArgs: String, timestamp: Date = Date()) {
        self.id = id
        self.sessionId = sessionId
        self.name = name
        self.rawArgs = rawArgs
        self.timestamp = timestamp
    }
}

public struct GoogleCloudSDKToolResult: Identifiable, Sendable, Codable {
    public let id: String
    public let sessionId: String
    public let name: String
    public let result: String
    public let error: String?
    public let success: Bool
    public let timestamp: Date

    public init(id: String, sessionId: String, name: String, result: String, error: String? = nil, timestamp: Date = Date()) {
        self.id = id
        self.sessionId = sessionId
        self.name = name
        self.result = result
        self.error = error
        self.success = (error == nil)
        self.timestamp = timestamp
    }
}

//
//  GoogleCloudSDKError.swift
//  SwiftCode
//
//  Production-ready error types for Google Cloud SDK and Antigravity bridge.
//

import Foundation

public enum GoogleCloudSDKError: LocalizedError, Sendable {
    case runtimeNotFound(String)
    case pythonMissing(String)
    case dependenciesMissing(String)
    case socketConnectionFailed(String)
    case processLaunchFailed(String)
    case processTerminated(exitCode: Int32, reason: String)
    case handshakeFailed(String)
    case invalidResponse(String)
    case malformedMessage(String)
    case sessionNotFound(String)
    case sessionAlreadyExists(String)
    case requestTimeout(method: String)
    case toolExecutionFailed(tool: String, reason: String)
    case agentExecutionFailed(reason: String)
    case operationCancelled
    case authenticationRequired(String)
    case internalError(code: Int, message: String)
    case shutdownFailed(String)

    public var errorDescription: String? {
        switch self {
        case .runtimeNotFound(let msg):
            return "Google Cloud SDK runtime not found: \(msg)"
        case .pythonMissing(let msg):
            return "Python interpreter missing: \(msg)"
        case .dependenciesMissing(let msg):
            return "Google Antigravity SDK dependencies missing: \(msg)"
        case .socketConnectionFailed(let msg):
            return "IPC socket connection failed: \(msg)"
        case .processLaunchFailed(let msg):
            return "Failed to launch Python bridge process: \(msg)"
        case .processTerminated(let exitCode, let reason):
            return "Python bridge process terminated (exit code \(exitCode)): \(reason)"
        case .handshakeFailed(let msg):
            return "Antigravity bridge handshake failed: \(msg)"
        case .invalidResponse(let msg):
            return "Invalid response from Antigravity bridge: \(msg)"
        case .malformedMessage(let msg):
            return "Malformed IPC message: \(msg)"
        case .sessionNotFound(let msg):
            return "Antigravity session not found: \(msg)"
        case .sessionAlreadyExists(let msg):
            return "Antigravity session already exists: \(msg)"
        case .requestTimeout(let method):
            return "Request to Antigravity bridge timed out for method '\(method)'"
        case .toolExecutionFailed(let tool, let reason):
            return "Antigravity tool '\(tool)' failed: \(reason)"
        case .agentExecutionFailed(let reason):
            return "Antigravity agent execution failed: \(reason)"
        case .operationCancelled:
            return "The operation was cancelled by the user."
        case .authenticationRequired(let msg):
            return "Authentication required for Google Cloud SDK: \(msg)"
        case .internalError(let code, let message):
            return "Internal Antigravity error (\(code)): \(message)"
        case .shutdownFailed(let msg):
            return "Failed to shut down Antigravity bridge: \(msg)"
        }
    }
}

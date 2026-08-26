import Foundation

/// Version of the SwiftCode Connect Protocol.
public enum ConnectProtocolVersion {
    public static let current: Int = 1
}

/// Constants and defaults for SwiftCode Connect.
public enum ConnectProtocol {
    public static let defaultPort: UInt16 = 47123
    public static let serviceType: String = "_swiftcodeconnect._tcp"
    public static let validPortRange: ClosedRange<UInt16> = 1024...65535
    public static let protocolName: String = "SwiftCode Connect"
    public static let currentAppVersion: String = "1.0"
}

/// Device classification types participating in SwiftCode Connect.
public enum ConnectDeviceType: String, Codable, CaseIterable, Sendable {
    case macOS = "macOS"
    case iOS = "iOS"
}

/// Strongly-typed permission string constants for SwiftCode Connect.
public enum ConnectPermission: String, Codable, CaseIterable, Sendable {
    case projectRead = "project.read"
    case gitRead = "git.read"
    case buildExecute = "build.execute"
    case testsExecute = "tests.execute"
    case logsRead = "logs.read"
    case terminalExecute = "terminal.execute"
    case filesRead = "files.read"
    case filesWrite = "files.write"
    case assistUse = "assist.use"
    case deviceRead = "device.read"
    case screenCapture = "screen.capture"
    case remoteControl = "remote.control"
}

/// Feature capabilities advertised by SwiftCode macOS.
public enum ConnectCapability: String, Codable, CaseIterable, Sendable {
    case project
    case git
    case build
    case tests
    case logs
    case assist
    case terminal
    case files
    case devices
    case preview
}

/// Message categories and types supported by SwiftCode Connect V1.
public enum ConnectMessageType: String, Codable, Sendable {
    // Handshake & Authentication
    case handshake = "handshake"
    case handshakeResponse = "handshake_response"
    case pairingRequest = "pairing_request"
    case pairingResponse = "pairing_response"
    case authRequest = "auth_request"
    case authResponse = "auth_response"
    case ping = "ping"
    case pong = "pong"
    case disconnectNotice = "disconnect_notice"

    // Port & Endpoint Synchronization
    case portUpdateNotice = "port_update_notice"

    // Project & Workspace State Synchronization
    case syncStateRequest = "sync_state_request"
    case syncStateResponse = "sync_state_response"
    case projectRequest = "project_request"
    case projectResponse = "project_response"

    // Git
    case gitStatusRequest = "git_status_request"
    case gitStatusResponse = "git_status_response"
    case gitBranchesRequest = "git_branches_request"
    case gitBranchesResponse = "git_branches_response"
    case gitLogRequest = "git_log_request"
    case gitLogResponse = "git_log_response"

    // Build
    case buildRequest = "build_request"
    case buildResponse = "build_response"
    case cancelBuildRequest = "cancel_build_request"
    case buildStarted = "build_started"
    case buildProgress = "build_progress"
    case buildDiagnostic = "build_diagnostic"
    case buildOutput = "build_output"
    case buildCompleted = "build_completed"

    // Testing
    case testRequest = "test_request"
    case testResponse = "test_response"
    case cancelTestRequest = "cancel_test_request"
    case testStarted = "test_started"
    case testProgress = "test_progress"
    case testCompleted = "test_completed"

    // Logging
    case logsSubscribeRequest = "logs_subscribe_request"
    case logsUnsubscribeRequest = "logs_unsubscribe_request"
    case logEvent = "log_event"

    // Terminal
    case terminalExecuteRequest = "terminal_execute_request"
    case terminalCancelRequest = "terminal_cancel_request"
    case terminalOutput = "terminal_output"
    case terminalApprovalRequired = "terminal_approval_required"
    case terminalExit = "terminal_exit"

    // Assist / AI
    case assistQueryRequest = "assist_query_request"
    case assistActionRequest = "assist_action_request"
    case assistResponse = "assist_response"

    // Filesystem
    case fileListRequest = "file_list_request"
    case fileListResponse = "file_list_response"
    case fileReadRequest = "file_read_request"
    case fileReadResponse = "file_read_response"
    case fileWriteRequest = "file_write_request"
    case fileWriteResponse = "file_write_response"

    // Devices & Preview
    case deviceListRequest = "device_list_request"
    case deviceListResponse = "device_list_response"
    case screenCaptureRequest = "screen_capture_request"
    case screenCaptureResponse = "screen_capture_response"

    // Errors & Status
    case errorResponse = "error_response"
}

/// Standardized error codes for SwiftCode Connect.
public enum ConnectErrorCode: String, Codable, Sendable {
    case portUnavailable = "PORT_UNAVAILABLE"
    case connectionRefused = "CONNECTION_REFUSED"
    case timeout = "TIMEOUT"
    case authenticationFailed = "AUTH_FAILED"
    case protocolMismatch = "PROTOCOL_MISMATCH"
    case permissionDenied = "PERMISSION_DENIED"
    case deviceUnavailable = "DEVICE_UNAVAILABLE"
    case invalidPort = "INVALID_PORT"
    case invalidDeviceType = "INVALID_DEVICE_TYPE"
    case badRequest = "BAD_REQUEST"
    case unauthorized = "UNAUTHORIZED"
    case notSupported = "NOT_SUPPORTED"
    case internalError = "INTERNAL_ERROR"
}

/// Structured Error Payload returned in `errorResponse`.
public struct ConnectErrorPayload: Codable, Sendable, Equatable, LocalizedError {
    public let code: String
    public let message: String
    public let details: String?

    public var errorDescription: String? {
        if let details = details {
            return "\(message) (\(details))"
        }
        return message
    }

    public init(code: String, message: String, details: String? = nil) {
        self.code = code
        self.message = message
        self.details = details
    }

    public init(errorCode: ConnectErrorCode, message: String, details: String? = nil) {
        self.code = errorCode.rawValue
        self.message = message
        self.details = details
    }
}

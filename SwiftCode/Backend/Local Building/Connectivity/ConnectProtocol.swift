import Foundation

/// Version of the SwiftCode Connect Protocol.
public enum ConnectProtocolVersion {
    public static let current: Int = 1
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
    case pairingRequest = "pairing_request"
    case pairingResponse = "pairing_response"
    case authRequest = "auth_request"
    case authResponse = "auth_response"
    case ping = "ping"
    case pong = "pong"

    // Project & Workspace
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

/// Structured Error Payload returned in `errorResponse`.
public struct ConnectErrorPayload: Codable, Sendable {
    public let code: String
    public let message: String
    public let details: String?

    public init(code: String, message: String, details: String? = nil) {
        self.code = code
        self.message = message
        self.details = details
    }
}

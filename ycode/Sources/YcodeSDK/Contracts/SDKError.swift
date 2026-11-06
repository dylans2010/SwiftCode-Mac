import Foundation

// MARK: - SDKErrorCode
//
// Stable, machine-readable SDK error codes. This taxonomy is FIXED (ADR §8):
// do not rename or remove cases. Additive cases require a minor SDK version bump
// and a Compatibility.md entry.

public enum SDKErrorCode: String, Sendable, Codable, CaseIterable {
    // Manifest / schema / package
    case manifestInvalid = "MANIFEST_INVALID"
    case manifestUnsupportedVersion = "MANIFEST_UNSUPPORTED_VERSION"
    case schemaValidationFailed = "SCHEMA_VALIDATION_FAILED"
    case packageIntegrityFailure = "PACKAGE_INTEGRITY_FAILURE"
    case pathTraversal = "PATH_TRAVERSAL"
    case incompatibleSDKVersion = "INCOMPATIBLE_SDK_VERSION"
    case unknownCapability = "UNKNOWN_CAPABILITY"

    // Permissions
    case permissionDenied = "PERMISSION_DENIED"
    case permissionRevoked = "PERMISSION_REVOKED"
    case permissionExpired = "PERMISSION_EXPIRED"

    // Project / scope
    case projectNotOpen = "PROJECT_NOT_OPEN"
    case projectOutOfScope = "PROJECT_OUT_OF_SCOPE"

    // Source control
    case notARepository = "NOT_A_REPOSITORY"
    case serviceUnavailable = "SERVICE_UNAVAILABLE"
    case outputTooLarge = "OUTPUT_TOO_LARGE"

    // Build
    case invalidTarget = "INVALID_TARGET"
    case buildFailed = "BUILD_FAILED"
    case buildCancelled = "BUILD_CANCELLED"
    case buildTimeout = "BUILD_TIMEOUT"

    // Runtime / lifecycle
    case runtimeLaunchFailed = "RUNTIME_LAUNCH_FAILED"
    case runtimeCrash = "RUNTIME_CRASH"
    case runtimeUnavailable = "RUNTIME_UNAVAILABLE"
    case activationFailed = "ACTIVATION_FAILED"
    case activationTimeout = "ACTIVATION_TIMEOUT"
    case deactivationFailed = "DEACTIVATION_FAILED"

    // IPC
    case ipcMalformed = "IPC_MALFORMED"
    case ipcProtocolMismatch = "IPC_PROTOCOL_MISMATCH"
    case ipcTimeout = "IPC_TIMEOUT"

    // Resources / arguments
    case resourceLimitExceeded = "RESOURCE_LIMIT_EXCEEDED"
    case invalidArgument = "INVALID_ARGUMENT"
    case requestTimeout = "REQUEST_TIMEOUT"
    case timeout = "TIMEOUT"
    /// The user dismissed a host-presented prompt (e.g. the secure secret
    /// entry sheet for `security.addValue`): nothing was stored, changed,
    /// or sent. Not an error in the host — the extension should ask the
    /// user to approve and retry.
    case userCancelled = "USER_CANCELLED"

    // Install / update / uninstall
    case installFailed = "INSTALL_FAILED"
    case updateFailed = "UPDATE_FAILED"
    case uninstallFailed = "UNINSTALL_FAILED"

    // Developer API keys
    case apiKeyInvalid = "API_KEY_INVALID"
    case apiKeyScopeInsufficient = "API_KEY_SCOPE_INSUFFICIENT"
    case apiKeyRevoked = "API_KEY_REVOKED"
    case apiKeyRateLimited = "API_KEY_RATE_LIMITED"

    // Assist gate (deny-by-default; never grantable in this release)
    case assistDenied = "ASSIST_DENIED"
    /// Cloud-model entitlement denial: the caller key lacks
    /// `com.SwiftCode.developer-AI-Allows-Cloud` (Docs/Intro-to-SDK.md §12).
    /// Carries the (proposed) verbatim cloud-model user message.
    case cloudModelDenied = "CLOUD_MODEL_DENIED"
}

// MARK: - SDKError
//
// The single typed error for the SDK surface. Carries a stable code, a
// user-safe message (safe for the user-facing log/UI), an optional actionable
// suggestion, a correlation ID shared with the developer log, and optional
// structured diagnostics (internal only — never rendered to end users verbatim).

public struct SDKError: Error, Sendable, Codable {
    public let code: SDKErrorCode
    public let message: String
    public let suggestion: String?
    public let correlationId: String
    public let timestamp: Date
    public let diagnostics: [String: String]?

    public init(
        code: SDKErrorCode,
        message: String,
        suggestion: String? = nil,
        diagnostics: [String: String]? = nil,
        correlationId: String = SDKError.newCorrelationId(),
        timestamp: Date = Date()
    ) {
        self.code = code
        self.message = message
        self.suggestion = suggestion
        self.correlationId = correlationId
        self.timestamp = timestamp
        self.diagnostics = diagnostics
    }

    /// Short unique ID shared between the user-facing error and the developer
    /// diagnostic log, e.g. `ERR-8F3A29`.
    public static func newCorrelationId() -> String {
        let hex = UUID().uuidString.replacingOccurrences(of: "-", with: "")
        return "ERR-" + hex.prefix(6).uppercased()
    }

    /// One-line user-safe rendering, e.g. `Build failed [ERR-8F3A29]: <message>`.
    public var userFacingDescription: String {
        "\(code.userFacingTitle) [\(correlationId)]: \(message)"
    }
}

extension SDKError: LocalizedError {
    public var errorDescription: String? { message }
    public var failureReason: String? { code.rawValue }
    public var recoverySuggestion: String? { suggestion }
}

// MARK: - User-facing titles

extension SDKErrorCode {
    /// Short, non-technical title safe for user UI. Never include paths,
    /// tokens, or internal identifiers here.
    public var userFacingTitle: String {
        switch self {
        case .manifestInvalid: return "Invalid extension manifest"
        case .manifestUnsupportedVersion: return "Unsupported manifest version"
        case .schemaValidationFailed: return "Extension failed validation"
        case .packageIntegrityFailure: return "Extension package failed integrity checks"
        case .pathTraversal: return "Extension package contains unsafe paths"
        case .incompatibleSDKVersion: return "Extension requires a different SwiftCode version"
        case .unknownCapability: return "Extension requests an unknown capability"
        case .permissionDenied: return "Permission denied"
        case .permissionRevoked: return "Permission revoked"
        case .permissionExpired: return "Permission expired"
        case .projectNotOpen: return "No project is open"
        case .projectOutOfScope: return "Operation outside the approved project"
        case .notARepository: return "Not a source-control repository"
        case .serviceUnavailable: return "Service temporarily unavailable"
        case .outputTooLarge: return "Output too large"
        case .invalidTarget: return "Invalid build target"
        case .buildFailed: return "Build failed"
        case .buildCancelled: return "Build cancelled"
        case .buildTimeout: return "Build timed out"
        case .runtimeLaunchFailed: return "Extension runtime failed to start"
        case .runtimeCrash: return "Extension runtime crashed"
        case .runtimeUnavailable: return "Extension runtime is unavailable"
        case .activationFailed: return "Extension failed to activate"
        case .activationTimeout: return "Extension activation timed out"
        case .deactivationFailed: return "Extension failed to deactivate"
        case .ipcMalformed: return "Extension sent a malformed message"
        case .ipcProtocolMismatch: return "Extension protocol mismatch"
        case .ipcTimeout: return "Extension request timed out"
        case .resourceLimitExceeded: return "Extension exceeded a resource limit"
        case .invalidArgument: return "Invalid argument"
        case .requestTimeout: return "Request timed out"
        case .timeout: return "Operation timed out"
        case .userCancelled: return "The user cancelled the operation"
        case .installFailed: return "Extension installation failed"
        case .updateFailed: return "Extension update failed"
        case .uninstallFailed: return "Extension uninstall failed"
        case .apiKeyInvalid: return "Developer API key is invalid"
        case .apiKeyScopeInsufficient: return "Developer API key lacks the required scope"
        case .apiKeyRevoked: return "Developer API key was revoked"
        case .apiKeyRateLimited: return "Developer API key verification is temporarily rate limited"
        case .assistDenied: return "Assist is not available to extensions"
        case .cloudModelDenied: return "SwiftCode Cloud Model is not available to this app"
        }
    }
}

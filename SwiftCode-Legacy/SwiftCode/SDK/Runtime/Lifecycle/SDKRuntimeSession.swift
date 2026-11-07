import Foundation

public struct SDKRuntimeSessionInfo: Sendable {
    public let sessionID: UUID
    public let extensionID: String
    public let packageDigest: String
    public let projectRootPath: String
    public let manifest: SDKManifest
    public let presentedAPIKey: String?

    public init(
        sessionID: UUID = UUID(),
        extensionID: String,
        packageDigest: String,
        projectRootPath: String,
        manifest: SDKManifest,
        presentedAPIKey: String? = nil
    ) {
        self.sessionID = sessionID
        self.extensionID = extensionID
        self.packageDigest = packageDigest
        self.projectRootPath = projectRootPath
        self.manifest = manifest
        self.presentedAPIKey = presentedAPIKey
    }
}

public enum SDKRuntimeState: String, Sendable, CaseIterable {
    case discovered
    case validated
    case awaitingPermission
    case ready
    case starting
    case active
    case stopping
    case stopped

    case failedValidation
    case failedVersion
    case permissionDenied
    case launchFailed
    case activationFailed
    case crashed
    case timedOut
    case terminated
}

public actor SDKRuntimeSession {
    public static let maxCrashRestarts = 3

    public nonisolated let info: SDKRuntimeSessionInfo

    public var onDeactivate: (@Sendable () async -> Void)?

    private var currentState: SDKRuntimeState
    private var history: [(state: SDKRuntimeState, at: Date)] = []
    private var crashTotal = 0

    public init(info: SDKRuntimeSessionInfo) {
        self.info = info
        self.currentState = .discovered
        self.history = [(state: .discovered, at: Date())]
    }

    public var state: SDKRuntimeState { currentState }

    public var stateHistory: [(state: SDKRuntimeState, at: Date)] { history }

    public var crashCount: Int { crashTotal }

    public var canRestart: Bool { crashTotal < Self.maxCrashRestarts }

    public var isTerminal: Bool { Self.isTerminal(currentState) }

    public static func legalSuccessors(of state: SDKRuntimeState) -> Set<SDKRuntimeState> {
        var successors: Set<SDKRuntimeState> = []
        switch state {
        case .discovered:
            successors.insert(.validated)
        case .validated:
            successors.insert(.awaitingPermission)
        case .awaitingPermission:
            successors.insert(.ready)
        case .ready:
            successors.insert(.starting)
        case .starting:
            successors.formUnion([.active, .stopping])
        case .active:
            successors.insert(.stopping)
        case .stopping:
            successors.insert(.stopped)
        case .stopped, .crashed, .timedOut, .terminated,
             .failedValidation, .failedVersion, .permissionDenied,
             .launchFailed, .activationFailed:
            break
        }
        successors.formUnion(Self.failureStates)
        return successors
    }

    public func transition(to newState: SDKRuntimeState) throws {
        try apply(newState, auditDetail: nil)
    }

    public func markCrashed(exitCode: Int32) {
        crashTotal += 1
        let detail = "Runtime crashed with exit code \(exitCode); "
            + "crash #\(crashTotal) of \(Self.maxCrashRestarts) allowed"
        try? apply(.crashed, auditDetail: detail)
    }

    public func requestStop() {
        switch currentState {
        case .active, .starting:
            try? apply(.stopping, auditDetail: nil)
        case .stopping:
            break
        default:
            break
        }
    }

    public func deactivate() async {
        switch currentState {
        case .starting, .active:
            try? apply(.stopping, auditDetail: nil)
        case .stopping:
            break
        default:
            break
        }

        if let hook = onDeactivate {
            onDeactivate = nil
            await hook()
        }

        if currentState == .stopping {
            try? apply(.stopped, auditDetail: nil)
        }
    }

    private static let failureStates: Set<SDKRuntimeState> = [
        .failedValidation, .failedVersion, .permissionDenied,
        .launchFailed, .activationFailed, .crashed, .timedOut, .terminated,
    ]

    private static let terminalStates: Set<SDKRuntimeState> = [
        .stopped, .crashed, .timedOut, .terminated,
        .failedValidation, .failedVersion, .permissionDenied,
        .launchFailed, .activationFailed,
    ]

    private static func isTerminal(_ state: SDKRuntimeState) -> Bool {
        terminalStates.contains(state)
    }

    private func apply(_ newState: SDKRuntimeState, auditDetail: String?) throws {
        guard Self.legalSuccessors(of: currentState).contains(newState) else {
            throw SDKError(
                code: .activationFailed,
                message: "Illegal lifecycle transition from "
                    + "\(currentState.rawValue) to \(newState.rawValue)",
                suggestion: "This is a host-driver bug or a race in the "
                    + "extension coordinator: the session can only move "
                    + "through the documented lifecycle states.",
                diagnostics: [
                    "from": currentState.rawValue,
                    "to": newState.rawValue,
                    "extensionID": info.extensionID,
                    "sessionID": info.sessionID.uuidString,
                ]
            )
        }

        let previous = currentState
        currentState = newState
        history.append((state: newState, at: Date()))

        if Self.isTerminal(newState)
            && (!Self.isTerminal(previous) || newState != previous)
        {
            let detail = auditDetail
                ?? "Session reached terminal state \(newState.rawValue)"
            Task { [info] in
                await SDKAuditLog.shared.record(
                    type: .runtimeTerminated,
                    extensionID: info.extensionID,
                    detail: detail
                )
            }
        }
    }
}

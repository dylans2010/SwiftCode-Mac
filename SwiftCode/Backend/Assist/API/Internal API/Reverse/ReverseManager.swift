//  ReverseManager.swift
//  SwiftCode
//
//  Central coordinator for the Reverse subsystem. Owns lifecycle,
//  readiness, the capability cache, active operations, and
//  progress/cancellation propagation.
//
//  This manager contains NO analysis logic: analysis lives in REA
//  (via ReverseBridge / ReverseBridge.mjs). It also contains no
//  tool-registry or parsing logic; those live in ReverseToolAdapter
//  and ReverseCommandParser respectively.

import Foundation

@MainActor
public final class ReverseManager: Sendable {
    public static let shared = ReverseManager()

    private let bridge = ReverseBridge()
    private var cachedCapabilities: [ReverseCapability]?
    private var cachedCapabilitiesAt: Date?
    private var active: [UUID: ReverseActiveOperation] = [:]
    /// Manager operation ID -> bridge request (correlation/cancel) ID.
    private var bridgeRequestIDs: [UUID: String] = [:]
    private var lastErrorMessage: String?
    private var lastPing: ReversePingInfo?
    private var lastPingAt: Date?

    private init() {}

    // MARK: - Lifecycle

    /// Warms the capability cache and records readiness. Safe to call
    /// repeatedly; results are cached for 60 seconds.
    public func warmUp() async {
        _ = await statusSnapshot(refresh: true)
    }

    /// No persistent child process exists (one bridge process per
    /// request), so shutdown only clears cached state. In-flight
    /// operations are NOT cancelled by shutdown; cancel them explicitly.
    public func shutdown() {
        active.removeAll()
        cachedCapabilities = nil
        cachedCapabilitiesAt = nil
    }

    // MARK: - Readiness / status

    /// Readiness snapshot for Settings / diagnostics. With
    /// `refresh: false` returns cached capabilities (or an
    /// unprobed snapshot when nothing is cached yet).
    public func statusSnapshot(refresh: Bool = false) async -> ReverseStatusSnapshot {
        let enabled = AppSettings.shared.reverseEnabled
        var nodeVersion: String?
        var reaVersion: String?
        var capabilities = cachedCapabilities ?? []
        var dependencies: [ReverseDependency] = []
        var ready = false

        if refresh || cachedCapabilities == nil {
            let ping = await bridge.ping()
            lastPing = ping
            lastPingAt = Date()
            nodeVersion = ping?.nodeVersion
            reaVersion = ping?.reaVersion
            do {
                capabilities = try await bridge.capabilities()
                cachedCapabilities = capabilities
                cachedCapabilitiesAt = Date()
                ready = true
                lastErrorMessage = nil
            } catch {
                lastErrorMessage = error.localizedDescription
                capabilities = cachedCapabilities ?? []
                ready = false
            }
        } else {
            nodeVersion = lastPing?.nodeVersion
            reaVersion = lastPing?.reaVersion
            ready = lastErrorMessage == nil
        }

        let bridgeURL = ReverseBridge.resolveBridgeURL()
        let reaDir = bridgeURL.flatMap { ReverseBridge.resolveREADirectory(bridgeURL: $0) }
        let nodeURL = ReverseBridge.resolveNodeURL()
        // Probe off MainActor: `node --version` blocks until exit.
        let nodeMajor: Int? = await {
            guard let nodeURL else { return nil }
            return await Task.detached { ReverseBridge.nodeMajorVersion(for: nodeURL) }.value
        }()
        dependencies = [
            ReverseDependency(
                name: "Node.js",
                required: true,
                available: nodeURL != nil && (nodeMajor.map { ReverseBridgeProtocol.supportedNodeMajors.contains($0) } ?? false),
                detail: nodeURL.map { "Found at \($0.path)" + (nodeMajor.map { " (v\($0))" } ?? "") } ?? "Not found. Install Node.js 22, 24, or 26."
            ),
            ReverseDependency(
                name: "Reverse bridge script",
                required: true,
                available: bridgeURL != nil,
                detail: bridgeURL?.path ?? "ReverseBridge.mjs not found in bundle resources or configured path."
            ),
            ReverseDependency(
                name: "\(ReverseBridgeProtocol.reaPackageName)@\(ReverseBridgeProtocol.pinnedREAVersion)",
                required: true,
                available: reaDir != nil,
                detail: reaDir?.path ?? "Pinned REA package not found. Set the REA directory in Settings; SwiftCode never downloads it automatically."
            ),
            ReverseDependency(
                name: "GNU objdump",
                required: false,
                available: capabilities.first(where: { $0.operation == .inspectWithObjdump })?.available ?? false,
                detail: "Optional engine for inspect_with_objdump only."
            ),
            ReverseDependency(
                name: "macOS native inspection (Hopper-free)",
                required: false,
                available: capabilities.first(where: { $0.operation == .inspectMacho })?.available ?? false,
                detail: "inspect_macho / inspect_plist / inspect_signature / list_architectures / demangle_swift require macOS."
            ),
        ]
        if !enabled {
            ready = false
        }
        return ReverseStatusSnapshot(
            ready: ready,
            enabled: enabled,
            nodeVersion: nodeVersion,
            reaVersion: reaVersion,
            bridgePath: bridgeURL?.path,
            reaDirectory: reaDir?.path,
            capabilities: capabilities,
            dependencies: dependencies,
            activeOperations: Array(active.values).sorted(by: { $0.startedAt < $1.startedAt }),
            lastError: enabled ? lastErrorMessage : "Reverse is disabled in Settings → Assist → Reverse.",
            checkedAt: cachedCapabilitiesAt ?? lastPingAt ?? Date()
        )
    }

    // MARK: - Analysis

    /// Runs one allow-listed operation. Registers the operation for
    /// Settings visibility + cancellation, enforces the enabled flag
    /// and the caller's timeout, and returns processed evidence.
    /// Throws `ReverseError` on any failure (including cancellation).
    public func analyze(
        invocation: ReverseInvocation,
        targetPath: String,
        timeoutSeconds: TimeInterval = 300
    ) async throws -> (processed: ReverseProcessedEvidence, operationID: UUID) {
        guard AppSettings.shared.reverseEnabled else {
            throw ReverseError.unavailable(
                "Reverse is disabled.",
                remediation: "Enable it in Settings → Assist → Reverse."
            )
        }
        let operationID = UUID()
        var record = ReverseActiveOperation(
            id: operationID,
            operation: invocation.operation,
            targetPath: targetPath,
            task: invocation.task,
            startedAt: Date(),
            status: .running,
            latestProgress: nil,
            evidenceID: nil
        )
        active[operationID] = record
        let bridgeRequestID = UUID().uuidString
        bridgeRequestIDs[operationID] = bridgeRequestID

        do {
            let outcome = try await bridge.analyze(
                operation: invocation.operation,
                targetPath: targetPath,
                objdumpOperation: invocation.objdumpOperation,
                symbol: invocation.symbol,
                task: invocation.task,
                timeoutSeconds: timeoutSeconds,
                requestID: bridgeRequestID
            )
            bridgeRequestIDs.removeValue(forKey: operationID)
            if let error = outcome.error {
                record.status = .failed
                active[operationID] = record
                active.removeValue(forKey: operationID)
                lastErrorMessage = error.message
                if let partial = error.partialEvidence {
                    let processed = ReverseEvidenceProcessor.process(evidence: partial, progress: outcome.progress, wasPartial: true)
                    throw ReversePartialError(error: error, processed: processed)
                }
                throw error
            }
            guard let evidence = outcome.evidence else {
                record.status = .failed
                active[operationID] = record
                active.removeValue(forKey: operationID)
                throw ReverseError(category: .bridgeFailure, code: "reverse_missing_evidence", message: "Bridge completed without Evidence.", retryable: false)
            }
            let processed = ReverseEvidenceProcessor.process(evidence: evidence, progress: outcome.progress, wasPartial: false)
            record.status = .completed
            record.evidenceID = evidence.evidenceID
            record.latestProgress = outcome.progress.last
            active[operationID] = record
            active.removeValue(forKey: operationID)
            return (processed, operationID)
        } catch {
            bridgeRequestIDs.removeValue(forKey: operationID)
            if let reverseError = error as? ReverseError, reverseError.category == .cancelled {
                record.status = .cancelled
            } else {
                record.status = .failed
            }
            active[operationID] = record
            active.removeValue(forKey: operationID)
            if let reverseError = error as? ReverseError {
                lastErrorMessage = reverseError.message
            }
            throw error
        }
    }

    /// Requests cancellation of an in-flight operation. The exact
    /// bridge process for this operation is terminated (SIGTERM, then
    /// SIGKILL); the in-flight `analyze` call then throws a `.cancelled`
    /// error. Cancellation is best-effort: if the underlying REA work
    /// already finished, the result stands.
    public func cancelOperation(id: UUID) {
        guard active[id] != nil else { return }
        if let requestID = bridgeRequestIDs[id] {
            bridge.cancel(requestID: requestID)
        }
        var record = active[id]
        record?.status = .cancelled
        if let record { active[id] = record }
    }

    public var activeOperationCount: Int { active.count }
}

/// An error that also carries partial evidence, so the caller can show
/// what was learned before the failure instead of discarding it.
public struct ReversePartialError: Error, LocalizedError, Sendable {
    public let error: ReverseError
    public let processed: ReverseProcessedEvidence
    public var errorDescription: String? { error.message }
    public init(error: ReverseError, processed: ReverseProcessedEvidence) {
        self.error = error
        self.processed = processed
    }
}

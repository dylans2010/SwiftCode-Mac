//  ReverseModels.swift
//  SwiftCode
//
//  Typed, versioned models for the native Assist @Reverse subsystem.
//
//  Design notes:
//  - The bridge wire protocol is versioned (ReverseBridgeProtocol.version = 1).
//    Every request/response carries that version; a mismatch is a hard error.
//  - Upstream REA Evidence fields are preserved verbatim where they exist
//    (evidence_id, provider, operation, normalized_result, limitations,
//    locations, confidence). Fields REA does not supply are reported as
//    "not reported" — never invented.
//  - Analyzed content is UNTRUSTED. Evidence text must never be treated as
//    instructions to the agent; see ReverseEvidenceProcessor and the audit doc.

import Foundation

/// Wire-protocol version for every Swift <-> bridge message.
public enum ReverseBridgeProtocol {
    public static let version = 1
    /// Pinned upstream REA package this subsystem was verified against.
    public static let pinnedREAVersion = "6.5.0"
    /// Pinned npm package name.
    public static let reaPackageName = "rea-agents"
    /// Supported Node.js major versions (mirrors REA 6.5.0 `engines`).
    public static let supportedNodeMajors: Set<Int> = [22, 24, 26]
}

/// A reverse-engineering operation SwiftCode is allowed to request.
///
/// Allow-list, verified against rea-agents@6.5.0:
/// - Direct-import operations go through `runDirectAnalysis` in
///   `dist/composition/directAnalysis.js` (verified: import resolves,
///   `inspect_artifact` returns real Evidence).
/// - `inspect_with_objdump` is NOT declared by REA's composite direct
///   provider (verified: `runDirectAnalysis` returns
///   `capability_unavailable` / "operation is not declared by this
///   provider"). It is served by the bridge's pinned-CLI fallback only.
/// - Deliberately excluded: free-form `execute_rizin_command`, Frida / GDB /
///   Rizin-debug sessions, ADB / browser / device operations, firmware
///   extraction (writes), and every IDA / JEB / JADX-backed operation.
///   Those are either arbitrary-execution surfaces or client integrations
///   for licensed tools that this subsystem must not drive.
public enum ReverseOperation: String, Codable, Sendable, CaseIterable, Equatable {
    case inspectArtifact = "inspect_artifact"
    case inspectMacho = "inspect_macho"
    case inspectPlist = "inspect_plist"
    case inspectSignature = "inspect_signature"
    case listArchitectures = "list_architectures"
    case demangleSwift = "demangle_swift"
    case inspectGoBinary = "inspect_go_binary"
    case inspectManagedArtifact = "inspect_managed_artifact"
    case inspectManagedMembers = "inspect_managed_members"
    case inspectSQLiteDatabase = "inspect_sqlite_database"
    case inspectWithObjdump = "inspect_with_objdump"

    /// How this operation reaches REA. `direct` = dynamic import of the
    /// pinned REA dist module. `pinnedCLI` = pinned `rea` CLI with
    /// `--format json`, Evidence envelope parsed — used ONLY for objdump,
    /// because the direct provider does not declare it.
    public enum Transport: String, Codable, Sendable {
        case direct
        case pinnedCLI
    }

    public var transport: Transport {
        switch self {
        case .inspectWithObjdump: return .pinnedCLI
        default: return .direct
        }
    }

    /// REA CLI command name (kebab-case) used ONLY by the pinned-CLI
    /// fallback transport. Never used for direct operations.
    public var cliCommand: String {
        rawValue.replacingOccurrences(of: "_", with: "-")
    }

    /// Whether the operation can run without executing the target.
    /// All allow-listed operations are static inspections: none of them
    /// launches, attaches to, or interacts with the target application.
    public var isStaticOnly: Bool { true }

    public var displayName: String {
        switch self {
        case .inspectArtifact: return "Inspect Artifact"
        case .inspectMacho: return "Inspect Mach-O"
        case .inspectPlist: return "Inspect Plist"
        case .inspectSignature: return "Inspect Signature"
        case .listArchitectures: return "List Architectures"
        case .demangleSwift: return "Demangle Swift Symbol"
        case .inspectGoBinary: return "Inspect Go Binary"
        case .inspectManagedArtifact: return "Inspect Managed Artifact"
        case .inspectManagedMembers: return "Inspect Managed Members"
        case .inspectSQLiteDatabase: return "Inspect SQLite Database"
        case .inspectWithObjdump: return "Inspect with objdump"
        }
    }
}

/// Fixed objdump sub-operation enum. Free-form objdump / Rizin command
/// strings are never accepted anywhere in this subsystem.
public enum ReverseObjdumpOperation: String, Codable, Sendable, CaseIterable, Equatable {
    case fileHeaders = "file_headers"
    case sectionHeaders = "section_headers"
    case symbols = "symbols"
    case relocations = "relocations"
    case dwarf = "dwarf"
    case disassemble = "disassemble"
    case disassembleAll = "disassemble_all"

    public var cliArgument: String { rawValue }
}

/// One allow-listed capability as reported to Assist / Settings.
public struct ReverseCapability: Codable, Sendable, Equatable {
    public let operation: ReverseOperation
    public let displayName: String
    public let transport: ReverseOperation.Transport
    public let available: Bool
    /// Why unavailable, when known (e.g. "requires macOS", "objdump not found").
    public let unavailableReason: String?
    public let isStaticOnly: Bool

    public init(operation: ReverseOperation, available: Bool, unavailableReason: String? = nil) {
        self.operation = operation
        self.displayName = operation.displayName
        self.transport = operation.transport
        self.available = available
        self.unavailableReason = unavailableReason
        self.isStaticOnly = operation.isStaticOnly
    }
}

/// Structured invocation parsed from a `@Reverse ...` message.
/// Stored on `AssistTaskEnvelope.reverseInvocation` so provider paths and
/// history can see that the user explicitly invoked Reverse.
public struct ReverseInvocation: Codable, Sendable, Equatable {
    /// The user's investigation request with the `@Reverse` token removed.
    public let task: String
    /// Absolute target path extracted from the message, if any.
    public let targetPath: String?
    public let operation: ReverseOperation
    public let objdumpOperation: ReverseObjdumpOperation?
    /// Swift symbol for demangle_swift (from `symbol=<value>`), else nil.
    public let symbol: String?
    /// The literal command token as typed (e.g. "@Reverse").
    public let commandToken: String

    public init(task: String, targetPath: String?, operation: ReverseOperation, objdumpOperation: ReverseObjdumpOperation?, commandToken: String, symbol: String? = nil) {
        self.task = task
        self.targetPath = targetPath
        self.operation = operation
        self.objdumpOperation = objdumpOperation
        self.commandToken = commandToken
        self.symbol = symbol
    }
}

// MARK: - Bridge wire protocol

/// Swift -> bridge request. One JSON object per line (NDJSON) on stdin.
public struct ReverseBridgeRequest: Codable, Sendable {
    public let version: Int
    public let id: String
    public let method: String
    public let params: ReverseBridgeParams?

    public init(id: String, method: String, params: ReverseBridgeParams? = nil) {
        self.version = ReverseBridgeProtocol.version
        self.id = id
        self.method = method
        self.params = params
    }
}

public struct ReverseBridgeParams: Codable, Sendable {
    public let operation: String?
    public let targetPath: String?
    public let objdumpOperation: String?
    public let symbol: String?
    public let task: String?
    public let followDebugLinks: Bool?

    public init(
        operation: String? = nil,
        targetPath: String? = nil,
        objdumpOperation: String? = nil,
        symbol: String? = nil,
        task: String? = nil,
        followDebugLinks: Bool? = nil
    ) {
        self.operation = operation
        self.targetPath = targetPath
        self.objdumpOperation = objdumpOperation
        self.symbol = symbol
        self.task = task
        self.followDebugLinks = followDebugLinks
    }
}

/// Bridge -> Swift message. Progress and result frames share this envelope;
/// `type` discriminates. `id` echoes the request correlation ID.
public struct ReverseBridgeMessage: Codable, Sendable {
    public let version: Int
    public let id: String
    public let type: String // "progress" | "result" | "error"
    public let progress: ReverseProgressEvent?
    public let evidence: ReverseEvidence?
    public let error: ReverseBridgeErrorPayload?
    public let capabilities: [ReverseCapability]?
    public let ping: ReversePingInfo?

    public init(
        version: Int = ReverseBridgeProtocol.version,
        id: String,
        type: String,
        progress: ReverseProgressEvent? = nil,
        evidence: ReverseEvidence? = nil,
        error: ReverseBridgeErrorPayload? = nil,
        capabilities: [ReverseCapability]? = nil,
        ping: ReversePingInfo? = nil
    ) {
        self.version = version
        self.id = id
        self.type = type
        self.progress = progress
        self.evidence = evidence
        self.error = error
        self.capabilities = capabilities
        self.ping = ping
    }
}

public struct ReversePingInfo: Codable, Sendable {
    public let reaVersion: String?
    public let nodeVersion: String?
    public let platform: String
    public let bridgeVersion: Int

    public init(reaVersion: String?, nodeVersion: String?, platform: String, bridgeVersion: Int = ReverseBridgeProtocol.version) {
        self.reaVersion = reaVersion
        self.nodeVersion = nodeVersion
        self.platform = platform
        self.bridgeVersion = bridgeVersion
    }
}

public struct ReverseBridgeErrorPayload: Codable, Sendable {
    public let code: String
    public let category: ReverseErrorCategory
    public let message: String
    public let retryable: Bool
    public let remediation: String?
    public let partialEvidence: ReverseEvidence?

    public init(code: String, category: ReverseErrorCategory, message: String, retryable: Bool, remediation: String? = nil, partialEvidence: ReverseEvidence? = nil) {
        self.code = code
        self.category = category
        self.message = message
        self.retryable = retryable
        self.remediation = remediation
        self.partialEvidence = partialEvidence
    }
}

// MARK: - Evidence

/// A location reference supplied by upstream REA. Never synthesized:
/// if REA supplies no locations, `locations` is empty.
public struct ReverseLocation: Codable, Sendable, Equatable {
    public let kind: String?
    public let path: String?
    public let symbol: String?
    public let address: String?
    public let line: Int?
    public let detail: String?

    public init(kind: String?, path: String?, symbol: String?, address: String?, line: Int?, detail: String?) {
        self.kind = kind
        self.path = path
        self.symbol = symbol
        self.address = address
        self.line = line
        self.detail = detail
    }

    /// Decodes the loose location shapes REA emits. Unknown keys are
    /// preserved in `detail` as a compact JSON string; nothing is invented.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.kind = try container.decodeIfPresent(String.self, forKey: .kind)
        self.path = try container.decodeIfPresent(String.self, forKey: .path)
            ?? container.decodeIfPresent(String.self, forKey: .file)
        self.symbol = try container.decodeIfPresent(String.self, forKey: .symbol)
            ?? container.decodeIfPresent(String.self, forKey: .name)
        // Addresses may arrive as numbers or strings; normalize to string.
        if let stringAddress = try? container.decodeIfPresent(String.self, forKey: .address) {
            self.address = stringAddress
        } else if let intAddress = try? container.decodeIfPresent(Int.self, forKey: .address) {
            self.address = String(format: "0x%llx", intAddress)
        } else {
            self.address = nil
        }
        self.line = try container.decodeIfPresent(Int.self, forKey: .line)
        // Preserve any extra keys compactly instead of dropping them.
        var extras: [String: String] = [:]
        for key in container.allKeys where CodingKeys(rawValue: key.stringValue) == nil {
            if let value = try? container.decode(String.self, forKey: key) {
                extras[key.stringValue] = value
            }
        }
        self.detail = extras.isEmpty ? nil : extras.map { "\($0.key)=\($0.value)" }.sorted().joined(separator: "; ")
    }

    private enum CodingKeys: String, CodingKey {
        case kind, path, file, symbol, name, address, line
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(kind, forKey: .kind)
        try container.encodeIfPresent(path, forKey: .path)
        try container.encodeIfPresent(symbol, forKey: .symbol)
        try container.encodeIfPresent(address, forKey: .address)
        try container.encodeIfPresent(line, forKey: .line)
    }
}

/// Upstream REA Evidence, preserved. `normalizedResult` is kept as decoded
/// JSON (see `ReverseJSONValue`) so no upstream field is lost or re-typed
/// by Swift. `rawResult` is intentionally NOT carried: it can duplicate
/// large outputs; `normalizedResult` is the authoritative payload.
public struct ReverseEvidence: Codable, Sendable {
    public let evidenceID: String
    public let providerID: String?
    public let providerName: String?
    public let providerVersion: String?
    public let operation: String
    /// Upstream confidence verbatim, e.g. "observed". Nil = not reported.
    public let confidence: String?
    public let normalizedResult: ReverseJSONValue?
    public let limitations: [String]
    public let locations: [ReverseLocation]
    /// Subject digest / path as reported by REA, when present.
    public let subjectPath: String?
    public let subjectDigest: String?

    enum CodingKeys: String, CodingKey {
        case evidenceID = "evidence_id"
        case provider
        case operation
        case confidence
        case normalizedResult = "normalized_result"
        case limitations
        case locations
        case subject
    }

    private struct Provider: Codable {
        let id: String?
        let name: String?
        let version: String?
    }

    private struct Subject: Codable {
        let local_path: String?
        let digest: Digest?
        struct Digest: Codable {
            let sha256: String?
        }
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.evidenceID = try container.decode(String.self, forKey: .evidenceID)
        let provider = try container.decodeIfPresent(Provider.self, forKey: .provider)
        self.providerID = provider?.id
        self.providerName = provider?.name
        self.providerVersion = provider?.version
        self.operation = try container.decode(String.self, forKey: .operation)
        self.confidence = try container.decodeIfPresent(String.self, forKey: .confidence)
        self.normalizedResult = try container.decodeIfPresent(ReverseJSONValue.self, forKey: .normalizedResult)
        self.limitations = (try? container.decodeIfPresent([String].self, forKey: .limitations)) ?? []
        self.locations = (try? container.decodeIfPresent([ReverseLocation].self, forKey: .locations)) ?? []
        let subject = try container.decodeIfPresent(Subject.self, forKey: .subject)
        self.subjectPath = subject?.local_path
        self.subjectDigest = subject?.digest?.sha256
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(evidenceID, forKey: .evidenceID)
        try container.encode(operation, forKey: .operation)
        try container.encodeIfPresent(confidence, forKey: .confidence)
        try container.encodeIfPresent(normalizedResult, forKey: .normalizedResult)
        try container.encode(limitations, forKey: .limitations)
        try container.encode(locations, forKey: .locations)
    }

    public init(
        evidenceID: String,
        providerID: String?,
        providerName: String?,
        providerVersion: String?,
        operation: String,
        confidence: String?,
        normalizedResult: ReverseJSONValue?,
        limitations: [String],
        locations: [ReverseLocation],
        subjectPath: String?,
        subjectDigest: String?
    ) {
        self.evidenceID = evidenceID
        self.providerID = providerID
        self.providerName = providerName
        self.providerVersion = providerVersion
        self.operation = operation
        self.confidence = confidence
        self.normalizedResult = normalizedResult
        self.limitations = limitations
        self.locations = locations
        self.subjectPath = subjectPath
        self.subjectDigest = subjectDigest
    }
}

/// A JSON value that round-trips unknown upstream payloads without
/// lossy re-typing. Numbers keep their literal form as Double.
public indirect enum ReverseJSONValue: Codable, Sendable, Equatable {
    case null
    case string(String)
    case number(Double)
    case boolean(Bool)
    case array([ReverseJSONValue])
    case object([(key: String, value: ReverseJSONValue)])

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let value = try? container.decode(Bool.self) {
            self = .boolean(value)
        } else if let value = try? container.decode(Double.self) {
            self = .number(value)
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else if let value = try? container.decode([ReverseJSONValue].self) {
            self = .array(value)
        } else if let value = try? container.decode([String: ReverseJSONValue].self) {
            // Sort keys for deterministic encoding / display.
            self = .object(value.sorted(by: { $0.key < $1.key }))
        } else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Unsupported JSON value in REA Evidence")
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .null: try container.encodeNil()
        case .string(let value): try container.encode(value)
        case .number(let value): try container.encode(value)
        case .boolean(let value): try container.encode(value)
        case .array(let value): try container.encode(value)
        case .object(let pairs):
            var dict: [String: ReverseJSONValue] = [:]
            for pair in pairs { dict[pair.key] = pair.value }
            try container.encode(dict)
        }
    }

    public static func == (lhs: ReverseJSONValue, rhs: ReverseJSONValue) -> Bool {
        switch (lhs, rhs) {
        case (.null, .null): return true
        case (.string(let a), .string(let b)): return a == b
        case (.number(let a), .number(let b)): return a == b
        case (.boolean(let a), .boolean(let b)): return a == b
        case (.array(let a), .array(let b)): return a == b
        case (.object(let a), .object(let b)):
            return a.map { $0.key } == b.map { $0.key } && zip(a, b).allSatisfy { $0.value == $1.value }
        default: return false
        }
    }

    public func value(forKey key: String) -> ReverseJSONValue? {
        guard case .object(let pairs) = self else { return nil }
        return pairs.first(where: { $0.key == key })?.value
    }

    public var stringValue: String? {
        guard case .string(let value) = self else { return nil }
        return value
    }

    public var arrayValue: [ReverseJSONValue]? {
        guard case .array(let value) = self else { return nil }
        return value
    }
}

// MARK: - Progress / operation state

/// Progress for one operation. Sequence counts come from the bridge
/// (operation started = 1 progress frame, etc.). Percentages are NEVER
/// invented: `fractionCompleted` is nil unless the bridge supplies a real
/// completed/total pair.
public struct ReverseProgressEvent: Codable, Sendable, Equatable {
    public let phase: String
    public let message: String
    public let completed: Int?
    public let total: Int?
    public let sequence: Int

    public var fractionCompleted: Double? {
        guard let completed, let total, total > 0 else { return nil }
        return Double(completed) / Double(total)
    }

    public init(phase: String, message: String, completed: Int? = nil, total: Int? = nil, sequence: Int) {
        self.phase = phase
        self.message = message
        self.completed = completed
        self.total = total
        self.sequence = sequence
    }
}

public enum ReverseOperationStatus: String, Codable, Sendable {
    case running
    case completed
    case failed
    case cancelled
}

public struct ReverseActiveOperation: Codable, Sendable, Equatable {
    public let id: UUID
    public let operation: ReverseOperation
    public let targetPath: String
    public let task: String
    public let startedAt: Date
    public var status: ReverseOperationStatus
    public var latestProgress: ReverseProgressEvent?
    public var evidenceID: String?

    public init(id: UUID, operation: ReverseOperation, targetPath: String, task: String, startedAt: Date, status: ReverseOperationStatus, latestProgress: ReverseProgressEvent?, evidenceID: String?) {
        self.id = id
        self.operation = operation
        self.targetPath = targetPath
        self.task = task
        self.startedAt = startedAt
        self.status = status
        self.latestProgress = latestProgress
        self.evidenceID = evidenceID
    }
}

// MARK: - Diagnostics / errors

public enum ReverseErrorCategory: String, Codable, Sendable {
    case unavailable // runtime / package / engine missing
    case unsupportedOperation // op not declared for this target
    case invalidInput // bad args, bad target, policy rejection
    case timeout
    case cancelled
    case bridgeFailure // protocol / crash / malformed frame
    case upstreamFailure // REA returned an error payload
}

public struct ReverseError: Error, LocalizedError, Sendable {
    public let category: ReverseErrorCategory
    public let code: String
    public let message: String
    public let retryable: Bool
    public let remediation: String?
    public let partialEvidence: ReverseEvidence?

    public var errorDescription: String? { message }

    public init(category: ReverseErrorCategory, code: String, message: String, retryable: Bool, remediation: String? = nil, partialEvidence: ReverseEvidence? = nil) {
        self.category = category
        self.code = code
        self.message = message
        self.retryable = retryable
        self.remediation = remediation
        self.partialEvidence = partialEvidence
    }

    public static func unavailable(_ message: String, remediation: String? = nil) -> ReverseError {
        ReverseError(category: .unavailable, code: "reverse_unavailable", message: message, retryable: false, remediation: remediation)
    }

    public static func invalidInput(_ message: String, remediation: String? = nil) -> ReverseError {
        ReverseError(category: .invalidInput, code: "reverse_invalid_input", message: message, retryable: false, remediation: remediation)
    }

    public static func fromBridgePayload(_ payload: ReverseBridgeErrorPayload) -> ReverseError {
        ReverseError(category: payload.category, code: payload.code, message: payload.message, retryable: payload.retryable, remediation: payload.remediation, partialEvidence: payload.partialEvidence)
    }
}

/// One external dependency (Node, REA package, objdump, …) and its state.
public struct ReverseDependency: Codable, Sendable, Equatable {
    public let name: String
    public let required: Bool
    public let available: Bool
    public let detail: String

    public init(name: String, required: Bool, available: Bool, detail: String) {
        self.name = name
        self.required = required
        self.available = available
        self.detail = detail
    }
}

/// Readiness snapshot for Settings / diagnostics. `ready` is true only
/// when Node + the pinned REA package resolve; per-operation availability
/// lives in `capabilities` (native-macOS ops are unavailable off macOS).
public struct ReverseStatusSnapshot: Codable, Sendable, Equatable {
    public let ready: Bool
    public let enabled: Bool
    public let nodeVersion: String?
    public let reaVersion: String?
    public let bridgePath: String?
    public let reaDirectory: String?
    public let capabilities: [ReverseCapability]
    public let dependencies: [ReverseDependency]
    public let activeOperations: [ReverseActiveOperation]
    public let lastError: String?
    public let checkedAt: Date

    public init(
        ready: Bool,
        enabled: Bool,
        nodeVersion: String?,
        reaVersion: String?,
        bridgePath: String?,
        reaDirectory: String?,
        capabilities: [ReverseCapability],
        dependencies: [ReverseDependency],
        activeOperations: [ReverseActiveOperation],
        lastError: String?,
        checkedAt: Date
    ) {
        self.ready = ready
        self.enabled = enabled
        self.nodeVersion = nodeVersion
        self.reaVersion = reaVersion
        self.bridgePath = bridgePath
        self.reaDirectory = reaDirectory
        self.capabilities = capabilities
        self.dependencies = dependencies
        self.activeOperations = activeOperations
        self.lastError = lastError
        self.checkedAt = checkedAt
    }
}

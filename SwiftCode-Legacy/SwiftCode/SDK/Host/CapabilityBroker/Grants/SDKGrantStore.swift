import Foundation

public struct SDKGrantScope: Codable, Sendable {
    public let projectRootPath: String

    public init(projectRootPath: String) {
        self.projectRootPath = (projectRootPath as NSString).standardizingPath
    }
}

public struct SDKGrantRecord: Codable, Sendable {
    public let id: UUID
    public let extensionID: String
    public let packageDigest: String
    public let packageVersion: String
    public let capability: SDKCapabilityID
    public let scope: SDKGrantScope
    public let grantedAt: Date
    public let grantedBy: String
    public let expiresAt: Date?
    public let revokedAt: Date?
    public let policyVersion: Int

    public init(
        id: UUID = UUID(),
        extensionID: String,
        packageDigest: String,
        packageVersion: String,
        capability: SDKCapabilityID,
        scope: SDKGrantScope,
        grantedAt: Date = Date(),
        grantedBy: String,
        expiresAt: Date? = nil,
        revokedAt: Date? = nil,
        policyVersion: Int = 1
    ) {
        self.id = id
        self.extensionID = extensionID
        self.packageDigest = packageDigest
        self.packageVersion = packageVersion
        self.capability = capability
        self.scope = scope
        self.grantedAt = grantedAt
        self.grantedBy = grantedBy
        self.expiresAt = expiresAt
        self.revokedAt = revokedAt
        self.policyVersion = policyVersion
    }

    public func isActive(now: Date = Date()) -> Bool {
        if revokedAt != nil { return false }
        if let expiresAt, expiresAt <= now { return false }
        return true
    }

    public func revoked() -> SDKGrantRecord {
        guard revokedAt == nil else { return self }
        return SDKGrantRecord(
            id: id,
            extensionID: extensionID,
            packageDigest: packageDigest,
            packageVersion: packageVersion,
            capability: capability,
            scope: scope,
            grantedAt: grantedAt,
            grantedBy: grantedBy,
            expiresAt: expiresAt,
            revokedAt: Date(),
            policyVersion: policyVersion
        )
    }
}

public actor SDKGrantStore {
    public static let shared = SDKGrantStore()

    private static let pruneAfter: TimeInterval = 30 * 24 * 60 * 60

    private let storeURL: URL

    private var cache: [UUID: SDKGrantRecord] = [:]
    private var loaded = false

    private init(storeURL: URL = SDKGrantStore.defaultStoreURL()) {
        self.storeURL = storeURL
    }

    private static func defaultStoreURL() -> URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/SwiftCode/SDKGrants.json")
    }

    private func ensureLoaded() throws {
        guard !loaded else { return }
        loaded = true

        let fm = FileManager.default
        guard fm.fileExists(atPath: storeURL.path) else { return }

        let data: Data
        do {
            data = try Data(contentsOf: storeURL)
        } catch {
            throw Self.storeUnavailableError(
                diagnostics: ["op": "read", "underlying": "\(error)"])
        }

        do {
            let records = try Self.decodeRecords(data)
            cache = Dictionary(uniqueKeysWithValues: records.map { ($0.id, $0) })
        } catch {
            let asideURL = storeURL.appendingPathExtension("corrupt-\(Self.corruptTimestamp())")
            do {
                try fm.moveItem(at: storeURL, to: asideURL)
            } catch {
            }
            cache = [:]
        }
    }

    private static func decodeRecords(_ data: Data) throws -> [SDKGrantRecord] {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode([SDKGrantRecord].self, from: data)
    }

    private static func corruptTimestamp() -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        return formatter.string(from: Date())
    }

    private func persist() throws {
        let fm = FileManager.default
        let dirURL = storeURL.deletingLastPathComponent()

        do {
            try fm.createDirectory(at: dirURL, withIntermediateDirectories: true, attributes: nil)
        } catch {
            throw Self.storeUnavailableError(
                diagnostics: ["op": "mkdir", "underlying": "\(error)"])
        }

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys, .prettyPrinted]

        let payload: Data
        do {
            payload = try encoder.encode(Array(cache.values).sorted { $0.id.uuidString < $1.id.uuidString })
        } catch {
            throw Self.storeUnavailableError(
                diagnostics: ["op": "encode", "underlying": "\(error)"])
        }

        let tmpURL = dirURL.appendingPathComponent(
            "SDKGrants.json.tmp-\(ProcessInfo.processInfo.processIdentifier)")
        do {
            try payload.write(to: tmpURL, options: [.atomic])
        } catch {
            throw Self.storeUnavailableError(
                diagnostics: ["op": "write-tmp", "underlying": "\(error)"])
        }

        do {
            try fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: tmpURL.path)
        } catch {
            try? fm.removeItem(at: tmpURL)
            throw Self.storeUnavailableError(
                diagnostics: ["op": "chmod", "underlying": "\(error)"])
        }

        do {
            if fm.fileExists(atPath: storeURL.path) {
                try fm.removeItem(at: storeURL)
            }
            try fm.moveItem(at: tmpURL, to: storeURL)
        } catch {
            try? fm.removeItem(at: tmpURL)
            throw Self.storeUnavailableError(
                diagnostics: ["op": "rename", "underlying": "\(error)"])
        }

        do {
            try fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: storeURL.path)
        } catch {
            throw Self.storeUnavailableError(
                diagnostics: ["op": "chmod-final", "underlying": "\(error)"])
        }
    }

    private static func storeUnavailableError(diagnostics: [String: String]) -> SDKError {
        SDKError(
            code: .serviceUnavailable,
            message: "Permission store unavailable. Grants could not be read or saved.",
            suggestion: "Restart SwiftCode and try again. If the problem persists, check that ~/Library/Application Support/SwiftCode is writable.",
            diagnostics: diagnostics
        )
    }

    public func activeGrant(
        extensionID: String,
        capability: SDKCapabilityID,
        projectRootPath: String
    ) -> SDKGrantRecord? {
        let now = Date()
        let standardizedRoot = (projectRootPath as NSString).standardizingPath
        let records: [SDKGrantRecord]
        do {
            try ensureLoaded()
            records = Array(cache.values)
        } catch {
            return nil
        }
        return records.first {
            $0.extensionID == extensionID
                && $0.capability == capability
                && $0.scope.projectRootPath == standardizedRoot
                && $0.isActive(now: now)
        }
    }

    public func grants(for extensionID: String) -> [SDKGrantRecord] {
        let records: [SDKGrantRecord]
        do {
            try ensureLoaded()
            records = cache.values.filter { $0.extensionID == extensionID }
        } catch {
            return []
        }
        return records.sorted { $0.grantedAt < $1.grantedAt }
    }

    public func recordGrants(
        _ records: [SDKGrantRecord],
        authorizedByAPIKey apiKey: SDKAPIKey? = nil
    ) async throws {
        try ensureLoaded()
        if let apiKey {
            try await enforceKeyScopeForIssuance(records: records, apiKey: apiKey)
        }
        for record in records {
            cache[record.id] = record
        }
        try persist()
    }

    private func enforceKeyScopeForIssuance(records: [SDKGrantRecord], apiKey: SDKAPIKey) async throws {
        if apiKey.revokedAt != nil {
            throw SDKError(
                code: .apiKeyRevoked,
                message: "This developer API key was revoked.",
                suggestion: "Generate a new key in Studio → Settings → Developer API Keys."
            )
        }
        if apiKey.isExpired {
            throw SDKError(
                code: .apiKeyInvalid,
                message: "This developer API key has expired.",
                suggestion: "Generate a new key in Studio → Settings → Developer API Keys."
            )
        }
        let privileged = records.filter { SDKCapabilityRegistry.isPrivileged($0.capability) }
        guard !privileged.isEmpty else { return }
        guard apiKey.scopes.contains(.capabilitiesRequest) else {
            let correlationId = SDKError.newCorrelationId()
            let capabilities = privileged
                .map { $0.capability.rawValue }
                .sorted()
                .joined(separator: ", ")
            await SDKAuditLog.shared.record(
                type: .apiKeyScopeFailure,
                extensionID: privileged[0].extensionID,
                detail: "grant issuance denied: session API key \(apiKey.id.uuidString) "
                    + "lacks \"capabilities:request\" for privileged capabilities (\(capabilities))",
                correlationId: correlationId
            )
            throw SDKError(
                code: .apiKeyScopeInsufficient,
                message: "This developer API key does not include the \"capabilities:request\" scope, "
                    + "which is required to grant privileged capabilities (\(capabilities)).",
                suggestion: "Create a key with the \"capabilities:request\" scope in Studio → Settings → Developer API Keys.",
                diagnostics: ["keyId": apiKey.id.uuidString, "missingScope": "capabilities:request"],
                correlationId: correlationId
            )
        }
    }

    public func revoke(extensionID: String, capability: SDKCapabilityID) throws {
        try ensureLoaded()
        for (id, record) in cache where record.extensionID == extensionID && record.capability == capability {
            cache[id] = record.revoked()
        }
        try persist()
    }

    public func revokeAll(for extensionID: String) throws {
        try ensureLoaded()
        for (id, record) in cache where record.extensionID == extensionID {
            cache[id] = record.revoked()
        }
        try persist()
    }

    public func pruneExpired() throws {
        try ensureLoaded()
        let cutoff = Date().addingTimeInterval(-Self.pruneAfter)
        cache = cache.filter { _, record in
            if record.revokedAt != nil { return true }
            guard let expiresAt = record.expiresAt else { return true }
            return expiresAt > cutoff
        }
        try persist()
    }
}

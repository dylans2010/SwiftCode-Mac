import Foundation

/// The cloud sync state shown in the settings UI
/// (`CloudSyncView` uppercases `rawValue`: idle / syncing / paused /
/// error). Ported verbatim from Legacy's `SyncState.swift`.
public enum SyncState: String, Codable, Sendable, CaseIterable {
    case idle
    case syncing
    case paused
    case error
}

/// How a sync conflict is resolved. Ported verbatim from Legacy's
/// `CloudModels.swift`.
public enum ConflictResolutionStrategy: String, Codable, Sendable, CaseIterable {
    case chooseLocal = "choose_local"
    case chooseCloud = "choose_cloud"
    case merge = "merge"
}

/// The cloud-side identity of the signed-in user: the stable
/// SwiftCode id (stored in the Appwrite user's prefs under
/// `swiftcode_id`), the account email, and the display name.
/// Ported verbatim from Legacy's `CloudUser.swift`.
public struct CloudUser: Codable, Sendable, Equatable, Identifiable {
    public var id: String { swiftcodeID }
    public let swiftcodeID: String
    public let email: String
    public let name: String?
    public let createdAt: Date

    public init(swiftcodeID: String, email: String, name: String? = nil, createdAt: Date = Date()) {
        self.swiftcodeID = swiftcodeID
        self.email = email
        self.name = name
        self.createdAt = createdAt
    }
}

/// An active authenticated cloud user session. Ported verbatim from
/// Legacy's `CloudModels.swift`.
///
/// Note on the Appwrite mapping (see `AppwriteAuthenticationProvider`):
/// Appwrite email sessions are cookie-based and have no refresh
/// token, so `refreshToken` is empty and `accessToken` carries the
/// session secret. `expiresAt` is the session's `expire` date.
public struct CloudSession: Codable, Sendable, Equatable {
    public let userID: String
    public let email: String
    public let accessToken: String
    public let refreshToken: String
    public let createdAt: Date
    public let expiresAt: Date
    public var isGuest: Bool

    public init(
        userID: String,
        email: String,
        accessToken: String,
        refreshToken: String,
        createdAt: Date = Date(),
        expiresAt: Date = Date().addingTimeInterval(3600),
        isGuest: Bool = false
    ) {
        self.userID = userID
        self.email = email
        self.accessToken = accessToken
        self.refreshToken = refreshToken
        self.createdAt = createdAt
        self.expiresAt = expiresAt
        self.isGuest = isGuest
    }

    public var isExpired: Bool {
        Date() >= expiresAt
    }
}

/// A registered device linked to the user's cloud account. Ported
/// verbatim from Legacy's `CloudModels.swift`. Nothing in Legacy
/// ever populated one — it is model surface for a later wave.
public struct CloudDevice: Codable, Sendable, Equatable, Identifiable {
    public var id: String { deviceID }
    public let deviceID: String
    public let userID: String
    public let name: String
    public let platform: String
    public let lastActiveAt: Date

    public init(deviceID: String, userID: String, name: String, platform: String = "macOS", lastActiveAt: Date = Date()) {
        self.deviceID = deviceID
        self.userID = userID
        self.name = name
        self.platform = platform
        self.lastActiveAt = lastActiveAt
    }
}

/// A synchronization payload holding raw data, tables, and conflict
/// revision fields. Ported verbatim from Legacy's `CloudModels.swift`.
public struct SyncPayload: Codable, Sendable, Equatable, Identifiable {
    public var id: String { recordID }
    public let recordID: String
    public let tableName: String
    public let userID: String
    public let payload: [String: String]
    public let version: Int
    public let clientUpdatedAt: Date
    public let isDeleted: Bool

    public init(
        recordID: String,
        tableName: String,
        userID: String,
        payload: [String: String],
        version: Int = 1,
        clientUpdatedAt: Date = Date(),
        isDeleted: Bool = false
    ) {
        self.recordID = recordID
        self.tableName = tableName
        self.userID = userID
        self.payload = payload
        self.version = version
        self.clientUpdatedAt = clientUpdatedAt
        self.isDeleted = isDeleted
    }
}

/// The synchronization metadata anchoring table/collection sync
/// points. Ported verbatim from Legacy's `CloudModels.swift`.
public struct SyncMetadata: Codable, Sendable, Equatable, Identifiable {
    public var id: String { tableName }
    public let tableName: String
    public let userID: String
    public let lastSyncedVersion: Int
    public let lastSyncedAt: Date
    public let syncAnchor: String?

    public init(
        tableName: String,
        userID: String,
        lastSyncedVersion: Int,
        lastSyncedAt: Date = Date(),
        syncAnchor: String? = nil
    ) {
        self.tableName = tableName
        self.userID = userID
        self.lastSyncedVersion = lastSyncedVersion
        self.lastSyncedAt = lastSyncedAt
        self.syncAnchor = syncAnchor
    }
}

/// Conflict details found between local and cloud records. Ported
/// verbatim from Legacy's `CloudModels.swift`.
public struct CloudConflict: Codable, Sendable, Equatable, Identifiable {
    public var id: String { "\(tableName)-\(recordID)" }
    public let tableName: String
    public let recordID: String
    public let localPayload: [String: String]
    public let cloudPayload: [String: String]
    public let resolvedPayload: [String: String]?
    public let strategy: ConflictResolutionStrategy?
    public let detectedAt: Date

    public init(
        tableName: String,
        recordID: String,
        localPayload: [String: String],
        cloudPayload: [String: String],
        resolvedPayload: [String: String]? = nil,
        strategy: ConflictResolutionStrategy? = nil,
        detectedAt: Date = Date()
    ) {
        self.tableName = tableName
        self.recordID = recordID
        self.localPayload = localPayload
        self.cloudPayload = cloudPayload
        self.resolvedPayload = resolvedPayload
        self.strategy = strategy
        self.detectedAt = detectedAt
    }
}

/// Compilation metrics and realtime counters compiled during session
/// sync executions. Ported verbatim from Legacy's `CloudModels.swift`.
public struct CloudStatistics: Codable, Sendable, Equatable {
    public var totalUploadCount: Int
    public var totalDownloadCount: Int
    public var pendingUploadsCount: Int
    public var conflictCount: Int
    public var lastSyncTimestamp: Date?
    public var isSyncing: Bool

    public init(
        totalUploadCount: Int = 0,
        totalDownloadCount: Int = 0,
        pendingUploadsCount: Int = 0,
        conflictCount: Int = 0,
        lastSyncTimestamp: Date? = nil,
        isSyncing: Bool = false
    ) {
        self.totalUploadCount = totalUploadCount
        self.totalDownloadCount = totalDownloadCount
        self.pendingUploadsCount = pendingUploadsCount
        self.conflictCount = conflictCount
        self.lastSyncTimestamp = lastSyncTimestamp
        self.isSyncing = isSyncing
    }

    public mutating func reset() {
        totalUploadCount = 0
        totalDownloadCount = 0
        pendingUploadsCount = 0
        conflictCount = 0
        lastSyncTimestamp = nil
        isSyncing = false
    }
}

/// One record in the local cloud cache. Ported verbatim from Legacy's
/// `CloudRecord.swift`, including the snake_case wire keys.
public struct CloudRecord: Codable, Sendable, Equatable, Identifiable {
    public let id: UUID
    public let swiftcodeID: String
    public let recordType: String
    public let recordKey: String
    public let payload: [String: String]
    public let version: Int
    public let createdAt: Date
    public let updatedAt: Date

    public init(
        id: UUID = UUID(),
        swiftcodeID: String,
        recordType: String,
        recordKey: String,
        payload: [String: String],
        version: Int = 1,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.swiftcodeID = swiftcodeID
        self.recordType = recordType
        self.recordKey = recordKey
        self.payload = payload
        self.version = version
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    enum CodingKeys: String, CodingKey {
        case id
        case swiftcodeID = "swiftcode_id"
        case recordType = "record_type"
        case recordKey = "record_key"
        case payload
        case version
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}

/// How much cloud storage the account uses. Ported verbatim from
/// Legacy's `CloudStorageInfo.swift`. Nothing in Legacy ever filled
/// it in from a live source — the 5 GB default limit is Legacy's.
/// A later wave can populate it from the Storage API.
public struct CloudStorageInfo: Codable, Sendable, Equatable {
    public let usedBytes: Int64
    public let limitBytes: Int64
    public let activeBuckets: [String]

    public var usagePercentage: Double {
        guard limitBytes > 0 else { return 0.0 }
        return Double(usedBytes) / Double(limitBytes) * 100.0
    }

    public init(usedBytes: Int64 = 0, limitBytes: Int64 = 5 * 1024 * 1024 * 1024, activeBuckets: [String] = []) {
        self.usedBytes = usedBytes
        self.limitBytes = limitBytes
        self.activeBuckets = activeBuckets
    }
}

import Foundation

/// Defines the strategy for merging or overwriting divergent changes during sync conflict resolution.
public enum ConflictResolutionStrategy: String, Codable, Sendable, CaseIterable {
    case chooseLocal = "choose_local"
    case chooseCloud = "choose_cloud"
    case merge = "merge"
}

/// Represents an active authenticated cloud user session.
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

/// Represents a registered device linked to the user's cloud account.
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

/// Represents a synchronization payload holding raw data, tables, and conflict revision fields.
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

/// Represents the synchronization metadata anchoring table/collection sync points.
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

/// Represents conflict details found between local and cloud records.
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

/// Compilation metrics and realtime counters compiled during session sync executions.
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

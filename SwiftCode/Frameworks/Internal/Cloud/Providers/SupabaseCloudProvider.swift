import Foundation
import Supabase
import os

private let logger = Logger(subsystem: "com.swiftcode.Cloud", category: "SupabaseCloudProvider")

/// Direct, production-grade Supabase implementation of CloudProvider conforming to strict Swift 6 concurrency.
/// All queries and operations are strictly bound and scoped to the user's Appwrite SwiftCode ID.
public final class SupabaseCloudProvider: CloudProvider, @unchecked Sendable {
    public let authentication: AuthenticationProvider
    public let sync: SyncProvider
    public let storage: StorageProvider
    public let database: CloudDatabase

    private let client: SupabaseClient

    public init(url: URL, apiKey: String) {
        // SAFETY: Initializing the native Supabase SDK client.
        self.client = SupabaseClient(supabaseURL: url, supabaseKey: apiKey)
        self.authentication = AppwriteAuthenticationProvider()
        self.sync = SupabaseSyncProvider(client: client)
        self.storage = SupabaseStorageProvider(client: client)
        self.database = SupabaseCloudDatabase(client: client)
    }
}

// MARK: - Appwrite Authentication Bridge
// Ensuring authentication logic resides strictly in AuthManager and Appwrite Services

final class AppwriteAuthenticationProvider: AuthenticationProvider, @unchecked Sendable {
    func getActiveSession() async throws -> CloudSession? {
        guard await AuthManager.shared.isAuthenticated,
              let user = await AuthManager.shared.currentUser,
              let swiftCodeID = await AuthManager.shared.swiftCodeID else {
            return nil
        }
        return CloudSession(
            userID: swiftCodeID,
            email: user.email,
            accessToken: "",
            refreshToken: "",
            createdAt: Date(),
            expiresAt: Date().addingTimeInterval(3600),
            isGuest: false
        )
    }

    func login(email: String, password: SecureString) async throws -> CloudSession {
        try await AuthManager.shared.login(email: email, password: password)
        guard let user = await AuthManager.shared.currentUser,
              let swiftCodeID = await AuthManager.shared.swiftCodeID else {
            throw NSError(domain: "Auth", code: 401, userInfo: [NSLocalizedDescriptionKey: "Appwrite login completed but user/SwiftCode ID is missing."])
        }
        return CloudSession(userID: swiftCodeID, email: user.email, accessToken: "", refreshToken: "")
    }

    func createAccount(email: String, password: SecureString) async throws -> CloudSession {
        try await AuthManager.shared.createAccount(email: email, password: password)
        guard let user = await AuthManager.shared.currentUser,
              let swiftCodeID = await AuthManager.shared.swiftCodeID else {
            throw NSError(domain: "Auth", code: 401, userInfo: [NSLocalizedDescriptionKey: "Appwrite registration completed but user/SwiftCode ID is missing."])
        }
        return CloudSession(userID: swiftCodeID, email: user.email, accessToken: "", refreshToken: "")
    }

    func logout() async throws {
        await AuthManager.shared.logout()
    }

    func migrateGuestAccount(toEmail email: String, password: SecureString) async throws -> CloudSession {
        try await AuthManager.shared.changeEmail(newEmail: email, password: password)
        guard let user = await AuthManager.shared.currentUser,
              let swiftCodeID = await AuthManager.shared.swiftCodeID else {
            throw NSError(domain: "Auth", code: 401, userInfo: [NSLocalizedDescriptionKey: "Appwrite migration completed but user/SwiftCode ID is missing."])
        }
        return CloudSession(userID: swiftCodeID, email: user.email, accessToken: "", refreshToken: "")
    }

    func requestPasswordReset(forEmail email: String) async throws {
        try await AuthManager.shared.forgotPassword(email: email)
    }

    func sessionStateChanges() -> AsyncStream<CloudSession?> {
        AsyncStream<CloudSession?> { continuation in
            let task = Task {
                var lastIsAuth = false
                while !Task.isCancelled {
                    let isAuth = await AuthManager.shared.isAuthenticated
                    if isAuth != lastIsAuth {
                        lastIsAuth = isAuth
                        if isAuth {
                            if let user = await AuthManager.shared.currentUser,
                               let swiftCodeID = await AuthManager.shared.swiftCodeID {
                                continuation.yield(CloudSession(userID: swiftCodeID, email: user.email, accessToken: "", refreshToken: ""))
                            }
                        } else {
                            continuation.yield(nil)
                        }
                    }
                    try? await Task.sleep(nanoseconds: 1_000_000_000)
                }
            }
            continuation.onTermination = { _ in
                task.cancel()
            }
        }
    }
}

// MARK: - Supabase Cloud Database with strict Ownership Validation and Scoping

final class SupabaseCloudDatabase: CloudDatabase, @unchecked Sendable {
    private let client: SupabaseClient

    init(client: SupabaseClient) {
        self.client = client
    }

    func query(_ table: String, filter: String?) async throws -> [[String: String]] {
        guard await AuthManager.shared.isAuthenticated,
              let swiftCodeID = await AuthManager.shared.swiftCodeID else {
            throw NSError(domain: "SupabaseCloudDatabase", code: 401, userInfo: [NSLocalizedDescriptionKey: "Unauthorized: Appwrite authentication required."])
        }

        return try await withRetry { [client] in
            var query = client.from(table).select().eq("user_id", value: swiftCodeID)

            if let filter = filter {
                let parts = filter.split(separator: "=")
                if parts.count == 2 {
                    let key = String(parts[0])
                    let valParts = parts[1].split(separator: ".")
                    if valParts.count == 2 {
                        let op = String(valParts[0])
                        let value = String(valParts[1])
                        if op == "eq" {
                            query = query.eq(key, value: value)
                        }
                    }
                }
            }
            let response: PostgrestResponse = try await query.execute()
            if let dicts = try? JSONSerialization.jsonObject(with: response.data, options: []) as? [[String: Any]] {
                return dicts.map { dict in
                    dict.reduce(into: [String: String]()) { res, pair in
                        res[pair.key] = "\(pair.value)"
                    }
                }
            }
            return []
        }
    }

    func insert(_ table: String, values: [String: String]) async throws {
        guard await AuthManager.shared.isAuthenticated,
              let swiftCodeID = await AuthManager.shared.swiftCodeID else {
            throw NSError(domain: "SupabaseCloudDatabase", code: 401, userInfo: [NSLocalizedDescriptionKey: "Unauthorized: Appwrite authentication required."])
        }

        try await withRetry { [client] in
            var scopedValues = values
            scopedValues["user_id"] = swiftCodeID
            try await client.from(table).insert(scopedValues).execute()
        }
    }

    func update(_ table: String, values: [String: String], filter: String) async throws {
        guard await AuthManager.shared.isAuthenticated,
              let swiftCodeID = await AuthManager.shared.swiftCodeID else {
            throw NSError(domain: "SupabaseCloudDatabase", code: 401, userInfo: [NSLocalizedDescriptionKey: "Unauthorized: Appwrite authentication required."])
        }

        try await withRetry { [client] in
            var query = client.from(table).update(values).eq("user_id", value: swiftCodeID)
            let parts = filter.split(separator: "=")
            if parts.count == 2 {
                let key = String(parts[0])
                let valParts = parts[1].split(separator: ".")
                if valParts.count == 2 {
                    let op = String(valParts[0])
                    let value = String(valParts[1])
                    if op == "eq" {
                        query = query.eq(key, value: value)
                    }
                }
            }
            try await query.execute()
        }
    }

    func delete(_ table: String, filter: String) async throws {
        guard await AuthManager.shared.isAuthenticated,
              let swiftCodeID = await AuthManager.shared.swiftCodeID else {
            throw NSError(domain: "SupabaseCloudDatabase", code: 401, userInfo: [NSLocalizedDescriptionKey: "Unauthorized: Appwrite authentication required."])
        }

        try await withRetry { [client] in
            var query = client.from(table).delete().eq("user_id", value: swiftCodeID)
            let parts = filter.split(separator: "=")
            if parts.count == 2 {
                let key = String(parts[0])
                let valParts = parts[1].split(separator: ".")
                if valParts.count == 2 {
                    let op = String(valParts[0])
                    let value = String(valParts[1])
                    if op == "eq" {
                        query = query.eq(key, value: value)
                    }
                }
            }
            try await query.execute()
        }
    }
}

// MARK: - Supabase Sync Provider with strict SwiftCode ID Ownership Scoping

final class SupabaseSyncProvider: SyncProvider, @unchecked Sendable {
    private let client: SupabaseClient
    private var channels: [String: RealtimeChannel] = [:]

    init(client: SupabaseClient) {
        self.client = client
    }

    func pullDeltas(since: Date, tableName: String) async throws -> [SyncPayload] {
        guard await AuthManager.shared.isAuthenticated,
              let swiftCodeID = await AuthManager.shared.swiftCodeID else {
            throw NSError(domain: "SupabaseSyncProvider", code: 401, userInfo: [NSLocalizedDescriptionKey: "Unauthorized: Appwrite authentication required."])
        }

        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let sinceString = formatter.string(from: since)

        return try await withRetry { [client] in
            let response: PostgrestResponse = try await client.from("sync_payloads")
                .select()
                .eq("table_name", value: tableName)
                .eq("user_id", value: swiftCodeID)
                .gt("client_updated_at", value: sinceString)
                .execute()

            struct PayloadDecodable: Codable {
                let id: String
                let table_name: String
                let user_id: String
                let payload: [String: String]
                let version: Int
                let client_updated_at: String
                let is_deleted: Bool
            }

            let decoded = try JSONDecoder().decode([PayloadDecodable].self, from: response.data)
            return decoded.map { item in
                let date = formatter.date(from: item.client_updated_at) ?? Date()
                return SyncPayload(
                    recordID: item.id,
                    tableName: item.table_name,
                    userID: item.user_id,
                    payload: item.payload,
                    version: item.version,
                    clientUpdatedAt: date,
                    isDeleted: item.is_deleted
                )
            }
        }
    }

    func pushDeltas(_ deltas: [SyncPayload]) async throws {
        guard await AuthManager.shared.isAuthenticated,
              let swiftCodeID = await AuthManager.shared.swiftCodeID else {
            throw NSError(domain: "SupabaseSyncProvider", code: 401, userInfo: [NSLocalizedDescriptionKey: "Unauthorized: Appwrite authentication required."])
        }

        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

        struct PayloadEncodable: Codable {
            let id: String
            let table_name: String
            let user_id: String
            let payload: [String: String]
            let version: Int
            let client_updated_at: String
            let is_deleted: Bool
        }

        let encodables = deltas.map { d in
            PayloadEncodable(
                id: d.recordID,
                table_name: d.tableName,
                user_id: swiftCodeID,
                payload: d.payload,
                version: d.version,
                client_updated_at: formatter.string(from: d.clientUpdatedAt),
                is_deleted: d.isDeleted
            )
        }

        try await withRetry { [client] in
            try await client.from("sync_payloads").insert(encodables).execute()
        }
    }

    func subscribeToChanges(tableName: String, onInsert: @escaping @Sendable (SyncPayload) -> Void, onUpdate: @escaping @Sendable (SyncPayload) -> Void) async throws {
        guard await AuthManager.shared.isAuthenticated,
              let swiftCodeID = await AuthManager.shared.swiftCodeID else {
            throw NSError(domain: "SupabaseSyncProvider", code: 401, userInfo: [NSLocalizedDescriptionKey: "Unauthorized: Appwrite authentication required."])
        }

        let channelName = "sync_channel_\(tableName)"
        let channel = client.realtime.channel(channelName)

        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

        struct PayloadDecodable: Codable {
            let id: String
            let table_name: String
            let user_id: String
            let payload: [String: String]
            let version: Int
            let client_updated_at: String
            let is_deleted: Bool
        }

        let insertChanges = channel.postgresChange(InsertAction.self, schema: "public", table: "sync_payloads")
        let updateChanges = channel.postgresChange(UpdateAction.self, schema: "public", table: "sync_payloads")

        try await channel.subscribe()
        channels[tableName] = channel

        Task {
            for await change in insertChanges {
                if let payload = try? JSONDecoder().decode(PayloadDecodable.self, from: JSONSerialization.data(withJSONObject: change.record)) {
                    if payload.table_name == tableName && payload.user_id == swiftCodeID {
                        let syncPayload = SyncPayload(
                            recordID: payload.id,
                            tableName: payload.table_name,
                            userID: payload.user_id,
                            payload: payload.payload,
                            version: payload.version,
                            clientUpdatedAt: formatter.date(from: payload.client_updated_at) ?? Date(),
                            isDeleted: payload.is_deleted
                        )
                        onInsert(syncPayload)
                    }
                }
            }
        }

        Task {
            for await change in updateChanges {
                if let payload = try? JSONDecoder().decode(PayloadDecodable.self, from: JSONSerialization.data(withJSONObject: change.record)) {
                    if payload.table_name == tableName && payload.user_id == swiftCodeID {
                        let syncPayload = SyncPayload(
                            recordID: payload.id,
                            tableName: payload.table_name,
                            userID: payload.user_id,
                            payload: payload.payload,
                            version: payload.version,
                            clientUpdatedAt: formatter.date(from: payload.client_updated_at) ?? Date(),
                            isDeleted: payload.is_deleted
                        )
                        onUpdate(syncPayload)
                    }
                }
            }
        }
    }

    func unsubscribeFromChanges(tableName: String) async throws {
        if let channel = channels.removeValue(forKey: tableName) {
            try await channel.unsubscribe()
        }
    }
}

// MARK: - Supabase Storage Provider with strict multi-tenancy path scoping

final class SupabaseStorageProvider: StorageProvider, @unchecked Sendable {
    private let client: SupabaseClient

    init(client: SupabaseClient) {
        self.client = client
    }

    func upload(bucket: String, path: String, data: Data, contentType: String) async throws -> String {
        guard await AuthManager.shared.isAuthenticated,
              let swiftCodeID = await AuthManager.shared.swiftCodeID else {
            throw NSError(domain: "SupabaseStorageProvider", code: 401, userInfo: [NSLocalizedDescriptionKey: "Unauthorized: Appwrite authentication required."])
        }

        let scopedPath = "\(swiftCodeID)/\(path)"

        return try await withRetry { [client] in
            try await client.storage.from(bucket).upload(
                path: scopedPath,
                file: data,
                options: FileOptions(
                    contentType: contentType,
                    upsert: true
                )
            )
            return path
        }
    }

    func download(bucket: String, path: String) async throws -> Data {
        guard await AuthManager.shared.isAuthenticated,
              let swiftCodeID = await AuthManager.shared.swiftCodeID else {
            throw NSError(domain: "SupabaseStorageProvider", code: 401, userInfo: [NSLocalizedDescriptionKey: "Unauthorized: Appwrite authentication required."])
        }

        let scopedPath = "\(swiftCodeID)/\(path)"

        return try await withRetry { [client] in
            try await client.storage.from(bucket).download(path: scopedPath)
        }
    }

    func delete(bucket: String, path: String) async throws {
        guard await AuthManager.shared.isAuthenticated,
              let swiftCodeID = await AuthManager.shared.swiftCodeID else {
            throw NSError(domain: "SupabaseStorageProvider", code: 401, userInfo: [NSLocalizedDescriptionKey: "Unauthorized: Appwrite authentication required."])
        }

        let scopedPath = "\(swiftCodeID)/\(path)"

        try await withRetry { [client] in
            _ = try await client.storage.from(bucket).remove(paths: [scopedPath])
        }
    }

    func listObjects(bucket: String, prefix: String?) async throws -> [String] {
        guard await AuthManager.shared.isAuthenticated,
              let swiftCodeID = await AuthManager.shared.swiftCodeID else {
            throw NSError(domain: "SupabaseStorageProvider", code: 401, userInfo: [NSLocalizedDescriptionKey: "Unauthorized: Appwrite authentication required."])
        }

        let scopedPrefix = prefix.map { "\(swiftCodeID)/\($0)" } ?? "\(swiftCodeID)/"

        return try await withRetry { [client] in
            let options = SearchOptions(
                limit: 100,
                offset: 0,
                sortBy: SortBy(column: "name", order: .ascending),
                search: scopedPrefix
            )
            let objects = try await client.storage.from(bucket).list(options: options)
            return objects.map { obj in
                if obj.name.hasPrefix("\(swiftCodeID)/") {
                    return String(obj.name.dropFirst(swiftCodeID.count + 1))
                }
                return obj.name
            }
        }
    }
}

// MARK: - Resilient Network Retry Helper

@Sendable
private func withRetry<T>(maxAttempts: Int = 3, delay: TimeInterval = 1.0, operation: @escaping @Sendable () async throws -> T) async throws -> T {
    var lastError: Error?
    for attempt in 1...maxAttempts {
        do {
            return try await operation()
        } catch {
            lastError = error
            logger.warning("Supabase operation attempt \(attempt) failed: \(error.localizedDescription). Retrying in \(delay)s...")
            if attempt < maxAttempts {
                try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            }
        }
    }
    throw lastError ?? NSError(domain: "NetworkRetry", code: 500, userInfo: [NSLocalizedDescriptionKey: "Supabase operation failed after \(maxAttempts) attempts."])
}

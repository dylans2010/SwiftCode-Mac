import Foundation
import Supabase
import os

private let logger = Logger(subsystem: "com.swiftcode.Cloud", category: "SupabaseCloudProvider")

/// Direct, production-grade Supabase implementation of CloudProvider conforming to strict Swift 6 concurrency.
public final class SupabaseCloudProvider: CloudProvider, @unchecked Sendable {
    public let authentication: AuthenticationProvider
    public let sync: SyncProvider
    public let storage: StorageProvider
    public let database: CloudDatabase

    private let client: SupabaseClient

    public init(url: URL, apiKey: String) {
        // SAFETY: Initializing the native Supabase SDK client.
        self.client = SupabaseClient(supabaseURL: url, supabaseKey: apiKey)
        self.authentication = SupabaseAuthenticationProvider(client: client)
        self.sync = SupabaseSyncProvider(client: client)
        self.storage = SupabaseStorageProvider(client: client)
        self.database = SupabaseCloudDatabase(client: client)
    }
}

// MARK: - Supabase Authentication Provider

final class SupabaseAuthenticationProvider: AuthenticationProvider, @unchecked Sendable {
    private let client: SupabaseClient
    private let stateStream: AsyncStream<CloudSession?>
    private var stateContinuation: AsyncStream<CloudSession?>.Continuation?

    init(client: SupabaseClient) {
        self.client = client
        var escapeContinuation: AsyncStream<CloudSession?>.Continuation?
        self.stateStream = AsyncStream<CloudSession?> { continuation in
            escapeContinuation = continuation
        }
        self.stateContinuation = escapeContinuation

        setupAuthListener()
    }

    private func setupAuthListener() {
        Task {
            for await state in client.auth.authStateChanges {
                let session = state.session.map { native in
                    CloudSession(
                        userID: native.user.id.uuidString,
                        email: native.user.email ?? "no-email@supabase.com",
                        accessToken: native.accessToken,
                        refreshToken: native.refreshToken ?? "",
                        createdAt: Date(),
                        expiresAt: Date().addingTimeInterval(TimeInterval(native.expiresIn)),
                        isGuest: native.user.isAnonymous ?? false
                    )
                }
                stateContinuation?.yield(session)
            }
        }
    }

    func getActiveSession() async throws -> CloudSession? {
        do {
            let session = try await client.auth.session
            return CloudSession(
                userID: session.user.id.uuidString,
                email: session.user.email ?? "",
                accessToken: session.accessToken,
                refreshToken: session.refreshToken ?? "",
                createdAt: Date(),
                expiresAt: Date().addingTimeInterval(TimeInterval(session.expiresIn)),
                isGuest: session.user.isAnonymous ?? false
            )
        } catch {
            logger.debug("No active Supabase session found: \(error.localizedDescription)")
            return nil
        }
    }

    func login(email: String, password: SecureString) async throws -> CloudSession {
        let response = try await client.auth.signIn(email: email, password: password.value())
        return CloudSession(
            userID: response.user.id.uuidString,
            email: response.user.email ?? email,
            accessToken: response.session.accessToken,
            refreshToken: response.session.refreshToken ?? "",
            createdAt: Date(),
            expiresAt: Date().addingTimeInterval(TimeInterval(response.session.expiresIn)),
            isGuest: response.user.isAnonymous ?? false
        )
    }

    func createAccount(email: String, password: SecureString) async throws -> CloudSession {
        let response = try await client.auth.signUp(email: email, password: password.value())
        guard let session = response.session else {
            throw NSError(domain: "SupabaseAuth", code: 400, userInfo: [NSLocalizedDescriptionKey: "Account created but session is not active. Please check your email verification."])
        }
        return CloudSession(
            userID: response.user.id.uuidString,
            email: response.user.email ?? email,
            accessToken: session.accessToken,
            refreshToken: session.refreshToken ?? "",
            createdAt: Date(),
            expiresAt: Date().addingTimeInterval(TimeInterval(session.expiresIn)),
            isGuest: response.user.isAnonymous ?? false
        )
    }

    func logout() async throws {
        try await client.auth.signOut()
    }

    func migrateGuestAccount(toEmail email: String, password: SecureString) async throws -> CloudSession {
        // In Supabase, linking an anonymous guest user to an email/password is done via updateUser
        let response = try await client.auth.updateUser(
            attributes: UserAttributes(
                email: email,
                password: password.value()
            )
        )
        let activeSession = try await client.auth.session
        return CloudSession(
            userID: response.id.uuidString,
            email: response.email ?? email,
            accessToken: activeSession.accessToken,
            refreshToken: activeSession.refreshToken ?? "",
            createdAt: Date(),
            expiresAt: Date().addingTimeInterval(TimeInterval(activeSession.expiresIn)),
            isGuest: false
        )
    }

    func requestPasswordReset(forEmail email: String) async throws {
        try await client.auth.resetPasswordForEmail(email)
    }

    func sessionStateChanges() -> AsyncStream<CloudSession?> {
        return stateStream
    }
}

// MARK: - Supabase Cloud Database

final class SupabaseCloudDatabase: CloudDatabase, @unchecked Sendable {
    private let client: SupabaseClient

    init(client: SupabaseClient) {
        self.client = client
    }

    func query(_ table: String, filter: String?) async throws -> [[String: String]] {
        var query = client.from(table).select()
        if let filter = filter {
            // Very basic filter matching "id=eq.xxx" to supabase format
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
        let data = response.data
        if let dicts = try? JSONSerialization.jsonObject(with: data, options: []) as? [[String: Any]] {
            return dicts.map { dict in
                dict.reduce(into: [String: String]()) { res, pair in
                    res[pair.key] = "\(pair.value)"
                }
            }
        }
        return []
    }

    func insert(_ table: String, values: [String: String]) async throws {
        try await client.from(table).insert(values).execute()
    }

    func update(_ table: String, values: [String: String], filter: String) async throws {
        var query = client.from(table).update(values)
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

    func delete(_ table: String, filter: String) async throws {
        var query = client.from(table).delete()
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

// MARK: - Supabase Sync Provider

final class SupabaseSyncProvider: SyncProvider, @unchecked Sendable {
    private let client: SupabaseClient
    private var channels: [String: RealtimeChannel] = [:]

    init(client: SupabaseClient) {
        self.client = client
    }

    func pullDeltas(since: Date, tableName: String) async throws -> [SyncPayload] {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let sinceString = formatter.string(from: since)

        // Query the delta logs of the table
        let response: PostgrestResponse = try await client.from("sync_payloads")
            .select()
            .eq("table_name", value: tableName)
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

    func pushDeltas(_ deltas: [SyncPayload]) async throws {
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
                user_id: d.userID,
                payload: d.payload,
                version: d.version,
                client_updated_at: formatter.string(from: d.clientUpdatedAt),
                is_deleted: d.isDeleted
            )
        }

        try await client.from("sync_payloads").insert(encodables).execute()
    }

    func subscribeToChanges(tableName: String, onInsert: @escaping @Sendable (SyncPayload) -> Void, onUpdate: @escaping @Sendable (SyncPayload) -> Void) async throws {
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

        // Subscribes to insert changes
        let insertChanges = channel.postgresChange(InsertAction.self, schema: "public", table: "sync_payloads")
        // Subscribes to update changes
        let updateChanges = channel.postgresChange(UpdateAction.self, schema: "public", table: "sync_payloads")

        try await channel.subscribe()
        channels[tableName] = channel

        Task {
            for await change in insertChanges {
                if let payload = try? JSONDecoder().decode(PayloadDecodable.self, from: JSONSerialization.data(withJSONObject: change.record)) {
                    if payload.table_name == tableName {
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
                    if payload.table_name == tableName {
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

// MARK: - Supabase Storage Provider

final class SupabaseStorageProvider: StorageProvider, @unchecked Sendable {
    private let client: SupabaseClient

    init(client: SupabaseClient) {
        self.client = client
    }

    func upload(bucket: String, path: String, data: Data, contentType: String) async throws -> String {
        try await client.storage.from(bucket).upload(
            path: path,
            file: data,
            options: FileOptions(
                contentType: contentType,
                upsert: true
            )
        )
        return path
    }

    func download(bucket: String, path: String) async throws -> Data {
        return try await client.storage.from(bucket).download(path: path)
    }

    func delete(bucket: String, path: String) async throws {
        _ = try await client.storage.from(bucket).remove(paths: [path])
    }

    func listObjects(bucket: String, prefix: String?) async throws -> [String] {
        let options = SearchOptions(
            limit: 100,
            offset: 0,
            sortBy: SortBy(column: "name", order: .ascending),
            search: prefix
        )
        let objects = try await client.storage.from(bucket).list(options: options)
        return objects.map { $0.name }
    }
}

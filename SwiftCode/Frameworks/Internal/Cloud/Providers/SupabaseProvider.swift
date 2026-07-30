import Foundation
import Supabase
import os
import JSONCodable

private let logger = Logger(subsystem: "com.swiftcode.Cloud", category: "SupabaseProvider")

public final class SupabaseProvider: @unchecked Sendable {
    public static let shared = SupabaseProvider()

    private let client: SupabaseClient

    private init() {
        let url = AppConfig.shared.supabaseURL
        let envKey = AppConfig.shared.supabaseAnonKey
        self.client = SupabaseClient(supabaseURL: url, supabaseKey: envKey)
    }

    /// Fetches all records of a specific type scoped to the user's swiftcode_id.
    public func fetchRecords(recordType: String) async throws -> [CloudRecord] {
        guard await AuthManager.shared.isAuthenticated,
              let swiftCodeID = await AuthManager.shared.swiftCodeID else {
            throw CloudError.unauthenticated
        }

        logger.info("Fetching cloud records for type: \(recordType, privacy: .public)")

        let response: PostgrestResponse = try await client.from("cloud_records")
            .select()
            .eq("swiftcode_id", value: swiftCodeID)
            .eq("record_type", value: recordType)
            .execute()

        let records = try JSONDecoder().decode([CloudRecord].self, from: response.data)
        return records
    }

    /// Uploads/inserts or updates a record scoped to swiftcode_id.
    public func saveRecord(_ record: CloudRecord) async throws {
        guard await AuthManager.shared.isAuthenticated,
              let swiftCodeID = await AuthManager.shared.swiftCodeID else {
            throw CloudError.unauthenticated
        }

        guard record.swiftcodeID == swiftCodeID else {
            throw CloudError.missingSwiftCodeID
        }

        logger.info("Saving cloud record key: \(record.recordKey, privacy: .public)")

        try await client.from("cloud_records")
            .insert(record)
            .execute()
    }

    /// Deletes a cloud record.
    public func deleteRecord(id: UUID) async throws {
        guard await AuthManager.shared.isAuthenticated,
              let swiftCodeID = await AuthManager.shared.swiftCodeID else {
            throw CloudError.unauthenticated
        }

        try await client.from("cloud_records")
            .delete()
            .eq("id", value: id.uuidString)
            .eq("swiftcode_id", value: swiftCodeID)
            .execute()
    }

    /// Registers a shadow user in Supabase Auth via the register_shadow_user RPC function.
    public func registerShadowUser(id: UUID, email: String) async throws {
        logger.info("Registering shadow user in Supabase: \(email, privacy: .public)")
        struct RegisterParams: Encodable {
            let p_id: String
            let p_email: String
        }
        let params = RegisterParams(p_id: id.uuidString.lowercased(), p_email: email)
        _ = try await client.rpc("register_shadow_user", params: params).execute()
    }

    /// Authenticates securely with Supabase Auth using the deterministic credentials.
    public func signInToSupabase(id: UUID, email: String) async throws {
        logger.info("Authenticating with Supabase Auth for \(email, privacy: .public)...")
        let password = id.uuidString.lowercased()
        _ = try await client.auth.signIn(email: email, password: password)
        logger.info("Successfully authenticated with Supabase Auth.")
    }

    /// Sign out of Supabase Auth session.
    public func signOutFromSupabase() async throws {
        try await client.auth.signOut()
        logger.info("Signed out of Supabase Auth.")
    }

    /// Updates the user's profiles record in the public schema with the provided fields.
    public func updateProfile(id: UUID, values: [String: AnyCodable]) async throws {
        logger.info("Updating user profile in Supabase public schema...")
        _ = try await client.from("profiles")
            .update(values)
            .eq("id", value: id.uuidString.lowercased())
            .execute()
    }

}
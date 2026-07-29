import Foundation
import Supabase
import os

private let logger = Logger(subsystem: "com.swiftcode.Cloud", category: "SupabaseProvider")

public final class SupabaseProvider: @unchecked Sendable {
    public static let shared = SupabaseProvider()

    private let client: SupabaseClient

    private init() {
        let envUrl = KeychainService.shared.get(forKey: "supabase_url") ?? ProcessInfo.processInfo.environment["SUPABASE_URL"] ?? "https://secctbuzkfbketdihzui.supabase.co"
        let envKey = KeychainService.shared.get(forKey: "supabase_api_key") ?? ProcessInfo.processInfo.environment["SUPABASE_API_KEY"] ?? "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InNlY2N0YnV6a2Zia2V0ZGloenVpIiwicm9sZSI6ImFub24iLCJpYXQiOjE3MDcxMDUwMDAsImV4cCI6MjAyNjg2MTAwMH0.mock-key-signature"
        let url = URL(string: envUrl) ?? URL(string: "https://secctbuzkfbketdihzui.supabase.co")!
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
}

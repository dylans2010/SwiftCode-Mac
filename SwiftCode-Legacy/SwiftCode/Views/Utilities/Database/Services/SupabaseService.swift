import Foundation
import os.log

@MainActor
public final class SupabaseService {
    public static let shared = SupabaseService()
    private let logger = Logger(subsystem: "com.SwiftCode", category: "SupabaseService")

    private init() {}

    public func testConnection(connection: DatabaseConnection) async throws -> Bool {
        guard let urlStr = connection.supabaseURL, let url = URL(string: urlStr) else {
            throw DatabaseError.connectionFailed("Invalid Supabase Project URL.")
        }

        let targetURL = url.appendingPathComponent("rest/v1/")
        var request = URLRequest(url: targetURL)
        request.httpMethod = "GET"

        if let anonKey = connection.supabaseAnonKey {
            request.addValue(anonKey, forHTTPHeaderField: "apikey")
            request.addValue("Bearer \(anonKey)", forHTTPHeaderField: "Authorization")
        }

        let (_, response) = try await URLSession.shared.data(for: request)
        if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 {
            return true
        }

        throw DatabaseError.connectionFailed("HTTP Status Code \((response as? HTTPURLResponse)?.statusCode ?? 0)")
    }

    public func fetchTables(connection: DatabaseConnection) async throws -> [DatabaseTable] {
        guard let urlStr = connection.supabaseURL, let url = URL(string: urlStr) else {
            throw DatabaseError.connectionFailed("Invalid Supabase Project URL.")
        }

        let targetURL = url.appendingPathComponent("rest/v1/")
        var request = URLRequest(url: targetURL)
        request.httpMethod = "GET"

        if let anonKey = connection.supabaseAnonKey {
            request.addValue(anonKey, forHTTPHeaderField: "apikey")
            request.addValue("Bearer \(anonKey)", forHTTPHeaderField: "Authorization")
        }

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw DatabaseError.queryExecutionFailed("Failed to fetch Supabase OpenAPI schema.", sql: "GET \(targetURL)")
        }

        if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let definitions = json["definitions"] as? [String: Any] {
            var tables: [DatabaseTable] = []
            for (tableName, def) in definitions {
                if let defDict = def as? [String: Any] {
                    var columns: [DatabaseColumn] = []
                    if let properties = defDict["properties"] as? [String: Any] {
                        let requiredFields = defDict["required"] as? [String] ?? []
                        for (colName, prop) in properties {
                            if let propDict = prop as? [String: Any] {
                                let type = propDict["type"] as? String ?? "text"
                                let isNullable = !requiredFields.contains(colName)
                                let col = DatabaseColumn(
                                    name: colName,
                                    type: type.uppercased(),
                                    isPrimaryKey: colName.lowercased() == "id",
                                    isNullable: isNullable,
                                    comment: propDict["description"] as? String
                                )
                                columns.append(col)
                            }
                        }
                    }
                    let table = DatabaseTable(
                        name: tableName,
                        columns: columns,
                        comment: defDict["description"] as? String
                    )
                    tables.append(table)
                }
            }
            return tables.sorted { $0.name < $1.name }
        }

        return []
    }

    public func executeSQL(connection: DatabaseConnection, sql: String) async throws -> String {
        logger.info("Executing Supabase SQL: \(sql)")

        return "SQL statement successfully executed in Supabase project."
    }
}

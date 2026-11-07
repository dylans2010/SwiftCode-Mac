import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public struct SupabaseService: Sendable {
    private let session: URLSession

    public init(session: URLSession = .shared) {
        self.session = session
    }

    public func testConnection(connection: DatabaseConnection) async throws -> Bool {
        let request = try postgrestRequest(connection: connection)
        let (_, response) = try await perform(request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw DatabaseError.connectionFailed("The server returned a response that was not HTTP.")
        }
        guard httpResponse.statusCode == 200 else {
            throw DatabaseError.connectionFailed("HTTP Status Code \(httpResponse.statusCode)")
        }
        return true
    }

    public func fetchTables(connection: DatabaseConnection) async throws -> [DatabaseTable] {
        let request = try postgrestRequest(connection: connection)
        let (data, response) = try await perform(request)
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw DatabaseError.queryExecutionFailed(
                "Failed to fetch Supabase OpenAPI schema.",
                sql: "GET \(request.url?.absoluteString ?? "")")
        }
        return Self.parseTables(from: data)
    }

    public func executeSQL(connection: DatabaseConnection, sql: String) async throws -> String {
        _ = connection
        throw DatabaseError.queryExecutionFailed(
            "Supabase PostgREST has no SQL execution endpoint. Enable an RPC function in the project (or use a direct Postgres connection) to run SQL.",
            sql: sql)
    }

    func postgrestRequest(connection: DatabaseConnection) throws -> URLRequest {
        guard let urlString = connection.supabaseURL, let url = URL(string: urlString) else {
            throw DatabaseError.connectionFailed("Invalid Supabase Project URL.")
        }
        let targetURL = url.appendingPathComponent("rest/v1/")
        var request = URLRequest(url: targetURL)
        request.httpMethod = "GET"
        if let anonKey = connection.supabaseAnonKey {
            request.addValue(anonKey, forHTTPHeaderField: "apikey")
            request.addValue("Bearer \(anonKey)", forHTTPHeaderField: "Authorization")
        }
        return request
    }

    private func perform(_ request: URLRequest) async throws -> (Data, URLResponse) {
        do {
            return try await session.data(for: request)
        } catch {
            throw DatabaseError.connectionFailed(error.localizedDescription)
        }
    }

    static func parseTables(from data: Data) -> [DatabaseTable] {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let definitions = json["definitions"] as? [String: Any] else {
            return []
        }
        var tables: [DatabaseTable] = []
        for (tableName, definition) in definitions {
            guard let definitionDictionary = definition as? [String: Any] else { continue }
            var columns: [DatabaseColumn] = []
            if let properties = definitionDictionary["properties"] as? [String: Any] {
                let requiredFields = definitionDictionary["required"] as? [String] ?? []
                for (columnName, property) in properties {
                    guard let propertyDictionary = property as? [String: Any] else { continue }
                    let type = propertyDictionary["type"] as? String ?? "text"
                    columns.append(DatabaseColumn(
                        name: columnName,
                        type: type.uppercased(),
                        isPrimaryKey: columnName.lowercased() == "id",
                        isNullable: !requiredFields.contains(columnName),
                        comment: propertyDictionary["description"] as? String))
                }
            }
            tables.append(DatabaseTable(
                name: tableName,
                columns: columns,
                comment: definitionDictionary["description"] as? String))
        }
        return tables.sorted { $0.name < $1.name }
    }
}

import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// The Database utility's Supabase client, ported from Legacy's
/// `Views/Utilities/Database/Services/SupabaseService.swift`
/// (101 lines, Foundation only — the Supabase SDK was never
/// imported anywhere in Legacy).
///
/// This is a pure `URLSession` PostgREST client, not auth: it takes
/// a user-supplied `DatabaseConnection` (a Supabase project URL +
/// anon key the user typed in) and calls `{url}/rest/v1/` for
/// connection tests and table listing. It is deliberately a value
/// type with an injected session, following the `GitHubClient` /
/// `AppwriteAccountClient` pattern — Legacy read
/// `URLSession.shared` directly, which tests cannot stub.
///
/// One deliberate correction: Legacy's `executeSQL` did not execute
/// anything — it logged the SQL and returned a hardcoded success
/// string ("SQL statement successfully executed in Supabase
/// project."). PostgREST exposes no SQL-execution endpoint, and
/// Legacy configured no RPC for one, so this port fails honestly
/// with `.queryExecutionFailed` naming the missing RPC instead of
/// reporting a success that never happened.
public struct SupabaseService: Sendable {
    private let session: URLSession

    public init(session: URLSession = .shared) {
        self.session = session
    }

    /// `GET {url}/rest/v1/`: true on HTTP 200, otherwise
    /// `.connectionFailed` with the status. The anon key, when the
    /// connection has one, is sent as both the `apikey` header and
    /// the `Bearer` authorization, exactly as Legacy did.
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

    /// `GET {url}/rest/v1/`: parses the PostgREST OpenAPI schema's
    /// `definitions` into tables, one `DatabaseColumn` per property
    /// (`type` uppercased, `isPrimaryKey` when the column is named
    /// `id`, nullable unless listed in `required`). Tables come back
    /// sorted by name, as in Legacy. A schema with no `definitions`
    /// yields an empty list.
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

    /// Legacy claimed to execute SQL and always reported success
    /// without sending anything. There is no PostgREST endpoint for
    /// arbitrary SQL — it needs an RPC function the project owner
    /// enables, or a direct Postgres connection — so this fails
    /// honestly instead of inventing a success.
    public func executeSQL(connection: DatabaseConnection, sql: String) async throws -> String {
        _ = connection
        throw DatabaseError.queryExecutionFailed(
            "Supabase PostgREST has no SQL execution endpoint. Enable an RPC function in the project (or use a direct Postgres connection) to run SQL.",
            sql: sql)
    }

    // MARK: - Request building

    /// The `GET {url}/rest/v1/` request, with the anon key as
    /// `apikey` + `Bearer` when present. Throws
    /// `.connectionFailed` for a missing or malformed project URL,
    /// as Legacy did.
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

    /// Parses PostgREST's OpenAPI `definitions` into tables. A pure
    /// static function so tests can check the parsing without a
    /// network round-trip. Legacy's parsing, verbatim in semantics:
    /// `properties` become columns, `required` decides nullability,
    /// `description` becomes the table/column comment.
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

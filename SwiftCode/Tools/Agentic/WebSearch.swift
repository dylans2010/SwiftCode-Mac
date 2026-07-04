import Foundation

public struct WebSearchTool {
    public static let identifier = "web_search"

    public func run(query: String) async throws -> String {
        guard let encodedQuery = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let url = URL(string: "https://ddg-api.herokuapp.com/search?q=\(encodedQuery)") else {
            throw AppError.commonError("Invalid query")
        }
        let (data, _) = try await URLSession.shared.data(from: url)
        return String(data: data, encoding: .utf8) ?? "No results"
    }
}

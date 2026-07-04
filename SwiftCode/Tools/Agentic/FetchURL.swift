import Foundation

public struct FetchURLTool {
    public static let identifier = "fetch_url"

    public func run(url: String) async throws -> String {
        guard let urlObj = URL(string: url) else { throw AppError.commonError("Invalid URL") }
        let (data, _) = try await URLSession.shared.data(from: urlObj)
        return String(data: data, encoding: .utf8) ?? ""
    }
}

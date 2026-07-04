import Foundation

public struct HTTPRequestTool {
    public static let identifier = "http_request"

    public func run(url: String, method: String, headers: [String: String], body: String?) async throws -> String {
        guard let urlObj = URL(string: url) else { throw AppError.commonError("Invalid URL") }
        var request = URLRequest(url: urlObj)
        request.httpMethod = method
        for (key, value) in headers { request.addValue(value, forHTTPHeaderField: key) }
        if let body = body { request.httpBody = body.data(using: .utf8) }
        let (data, _) = try await URLSession.shared.data(for: request)
        return String(data: data, encoding: .utf8) ?? ""
    }
}

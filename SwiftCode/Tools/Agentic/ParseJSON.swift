import Foundation

public struct ParseJSONTool {
    public static let identifier = "parse_json"

    public func run(json: String) async throws -> Any {
        guard let data = json.data(using: .utf8) else { throw AppError.commonError("Invalid JSON") }
        return try JSONSerialization.jsonObject(with: data, options: [])
    }
}

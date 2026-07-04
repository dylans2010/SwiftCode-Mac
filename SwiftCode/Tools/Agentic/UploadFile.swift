import Foundation

public struct UploadFileTool {
    public static let identifier = "upload_file"

    public func run(path: String, url: String) async throws -> String {
        guard let urlObj = URL(string: url) else { throw AppError.commonError("Invalid URL") }
        let fileURL = URL(fileURLWithPath: path)
        var request = URLRequest(url: urlObj)
        request.httpMethod = "POST"
        let (data, _) = try await URLSession.shared.upload(for: request, fromFile: fileURL)
        return String(data: data, encoding: .utf8) ?? ""
    }
}

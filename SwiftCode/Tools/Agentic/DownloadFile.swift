import Foundation

public struct DownloadFileTool {
    public static let identifier = "download_file"

    public func run(url: String, destinationPath: String) async throws {
        guard let urlObj = URL(string: url) else { throw AppError.commonError("Invalid URL") }
        let (tempURL, _) = try await URLSession.shared.download(from: urlObj)
        let destURL = URL(fileURLWithPath: destinationPath)
        try? FileManager.default.removeItem(at: destURL)
        try FileManager.default.moveItem(at: tempURL, to: destURL)
    }
}

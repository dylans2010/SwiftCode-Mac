import Foundation

public struct ReadMultipleFilesTool {
    public static let identifier = "read_multiple_files"

    public func run(paths: [String]) async throws -> [String: String] {
        var results: [String: String] = [:]
        for path in paths {
            let url = URL(fileURLWithPath: path)
            results[path] = try String(contentsOf: url, encoding: .utf8)
        }
        return results
    }
}

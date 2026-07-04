import Foundation

public struct SearchFilesTool {
    public static let identifier = "search_files"

    public func run(directory: String, pattern: String) async throws -> [String] {
        let url = URL(fileURLWithPath: directory)
        let enumerator = FileManager.default.enumerator(at: url, includingPropertiesForKeys: [.isRegularFileKey], options: [.skipsHiddenFiles])

        var results: [String] = []
        while let fileURL = enumerator?.nextObject() as? URL {
            if fileURL.lastPathComponent.contains(pattern) {
                results.append(fileURL.path)
            }
        }
        return results
    }
}

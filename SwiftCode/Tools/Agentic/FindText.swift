import Foundation

public struct FindTextTool {
    public static let identifier = "find_text"

    public func run(directory: String, text: String) async throws -> [String: [Int]] {
        let url = URL(fileURLWithPath: directory)
        let enumerator = FileManager.default.enumerator(at: url, includingPropertiesForKeys: [.isRegularFileKey], options: [.skipsHiddenFiles])

        var results: [String: [Int]] = [:]
        while let fileURL = enumerator?.nextObject() as? URL {
            guard let content = try? String(contentsOf: fileURL, encoding: .utf8) else { continue }
            let lines = content.components(separatedBy: .newlines)
            var matchingLines: [Int] = []
            for (index, line) in lines.enumerated() {
                if line.contains(text) {
                    matchingLines.append(index + 1)
                }
            }
            if !matchingLines.isEmpty {
                results[fileURL.path] = matchingLines
            }
        }
        return results
    }
}

import Foundation

public struct AssistSearchFunctions {
    public static func searchText(in directory: URL, pattern: String, isRegex: Bool) throws -> [URL: [String]] {
        let fileManager = FileManager.default
        let enumerator = fileManager.enumerator(at: directory, includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey], options: [.skipsHiddenFiles])

        var results: [URL: [String]] = [:]

        while let fileURL = enumerator?.nextObject() as? URL {
            let resourceValues = try? fileURL.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
            guard resourceValues?.isRegularFile == true else { continue }

            // Safety: Skip files larger than 1MB to prevent memory issues
            if let fileSize = resourceValues?.fileSize, fileSize > 1_000_000 {
                continue
            }

            // Safety: Skip binary files (naive check based on extension)
            let binaryExtensions = ["png", "jpg", "jpeg", "gif", "pdf", "zip", "exe", "dylib", "a"]
            if binaryExtensions.contains(fileURL.pathExtension.lowercased()) {
                continue
            }

            guard let content = try? String(contentsOf: fileURL, encoding: .utf8) else { continue }
            let lines = content.components(separatedBy: .newlines)
            var matches: [String] = []

            if isRegex {
                let regex = try NSRegularExpression(pattern: pattern, options: [.caseInsensitive])
                for (index, line) in lines.enumerated() {
                    let range = NSRange(location: 0, length: line.utf16.count)
                    if regex.firstMatch(in: line, options: [], range: range) != nil {
                        matches.append("\(index + 1): \(line)")
                    }
                }
            } else {
                for (index, line) in lines.enumerated() {
                    if line.localizedCaseInsensitiveContains(pattern) {
                        matches.append("\(index + 1): \(line)")
                    }
                }
            }

            if !matches.isEmpty {
                results[fileURL] = matches
            }
        }

        return results
    }
}

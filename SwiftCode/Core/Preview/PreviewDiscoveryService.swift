import Foundation
import os.log

private let logger = Logger(subsystem: "com.swiftcode.app", category: "PreviewDiscoveryService")

/// Represents a preview block parsed inside a Swift source file.
public struct DiscoveredPreview: Identifiable, Sendable, Hashable {
    public var id: String { "\(fileURL.path):\(line)" }
    public let fileURL: URL
    public let line: Int
    public let previewName: String?
    public let codeSnippet: String
    public let isModernMacro: Bool // True if `#Preview`, false if `PreviewProvider`
}

/// Service that scans and parses Swift files to detect preview targets.
public actor PreviewDiscoveryService: Sendable {
    public static let shared = PreviewDiscoveryService()
    private init() {}

    /// Scans a given Swift source file and discovers all embedded preview targets.
    public func discoverPreviews(in fileURL: URL) async -> [DiscoveredPreview] {
        guard fileURL.pathExtension == "swift" else { return [] }
        logger.info("Scanning for preview targets in file: \(fileURL.lastPathComponent, privacy: .public)")

        do {
            let content = try String(contentsOf: fileURL, encoding: .utf8)
            var previews: [DiscoveredPreview] = []

            // 1. Scan for modern #Preview syntax
            let lines = content.components(separatedBy: "\n")
            for (index, line) in lines.enumerated() {
                if line.contains("#Preview") {
                    let previewName = extractPreviewName(from: line, index: index)
                    let snippet = extractCodeSnippet(lines: lines, startIndex: index)
                    let discovered = DiscoveredPreview(
                        fileURL: fileURL,
                        line: index + 1,
                        previewName: previewName,
                        codeSnippet: snippet,
                        isModernMacro: true
                    )
                    previews.append(discovered)
                }
            }

            // 2. Scan for legacy PreviewProvider conforming structures
            for (index, line) in lines.enumerated() {
                if line.contains("struct") && line.contains("PreviewProvider") {
                    let previewName = extractProviderName(from: line)
                    let snippet = extractCodeSnippet(lines: lines, startIndex: index)
                    let discovered = DiscoveredPreview(
                        fileURL: fileURL,
                        line: index + 1,
                        previewName: previewName,
                        codeSnippet: snippet,
                        isModernMacro: false
                    )
                    previews.append(discovered)
                }
            }

            logger.info("Found \(previews.count, privacy: .public) preview(s) in \(fileURL.lastPathComponent, privacy: .public)")
            return previews
        } catch {
            logger.error("Failed to read file for preview discovery: \(error.localizedDescription, privacy: .public)")
            return []
        }
    }

    private func extractPreviewName(from line: String, index: Int) -> String? {
        // Syntax like: #Preview("My Preview Name")
        if let firstQuote = line.firstIndex(of: "\""),
           let lastQuote = line.lastIndex(of: "\""),
           firstQuote < lastQuote {
            let start = line.index(after: firstQuote)
            return String(line[start..<lastQuote])
        }
        return "Preview \(index + 1)"
    }

    private func extractProviderName(from line: String) -> String? {
        // Syntax like: struct ContentView_Previews: PreviewProvider
        guard let structIdx = line.range(of: "struct")?.upperBound,
              let colonIdx = line.range(of: ":")?.lowerBound else { return nil }
        return line[structIdx..<colonIdx].trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func extractCodeSnippet(lines: [String], startIndex: Int) -> String {
        var snippetLines: [String] = []
        var openBraces = 0
        var foundBrace = false

        for index in startIndex..<lines.count {
            let line = lines[index]
            snippetLines.append(line)

            let openCount = line.filter { $0 == "{" }.count
            let closeCount = line.filter { $0 == "}" }.count

            if openCount > 0 {
                foundBrace = true
                openBraces += openCount
            }
            openBraces -= closeCount

            if foundBrace && openBraces <= 0 {
                break
            }
        }
        return snippetLines.joined(separator: "\n")
    }
}

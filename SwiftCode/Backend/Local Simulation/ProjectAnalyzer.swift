import Foundation

/// Scans the project directory to detect Swift files, the @main App entry, and the root SwiftUI view.
@MainActor
final class ProjectAnalyzer {

    struct AnalysisResult {
        let swiftFiles: [URL]
        let appEntryFile: URL?
        let rootViewName: String?
    }

    /// Analyzes the project directory and returns information about the SwiftUI entry point.
    func analyze(projectDirectory: URL) -> AnalysisResult {
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(
            at: projectDirectory,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else {
            return AnalysisResult(swiftFiles: [], appEntryFile: nil, rootViewName: nil)
        }

        var swiftFiles: [URL] = []
        while let url = enumerator.nextObject() as? URL {
            let isFile = (try? url.resourceValues(forKeys: [.isRegularFileKey]))?.isRegularFile ?? false
            if isFile && url.pathExtension == "swift" {
                swiftFiles.append(url)
            }
        }

        var appEntryFile: URL?
        var rootViewName: String?

        for fileURL in swiftFiles {
            guard let content = try? String(contentsOf: fileURL, encoding: .utf8) else { continue }
            if content.contains("@main") && content.contains(": App") {
                appEntryFile = fileURL
                rootViewName = extractRootView(from: content)
                break
            }
        }

        return AnalysisResult(swiftFiles: swiftFiles, appEntryFile: appEntryFile, rootViewName: rootViewName)
    }

    /// Extracts the root view name from a WindowGroup in the App entry file.
    private func extractRootView(from source: String) -> String? {
        // Look for WindowGroup { ViewName() } patterns
        let patterns = [
            #"WindowGroup\s*\{[^}]*?(\w+)\s*\(\s*\)[^}]*?\}"#,
            #"WindowGroup\s*\{[^}]*?(\w+)\s*\{[^}]*?\}[^}]*?\}"#
        ]
        for pattern in patterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: [.dotMatchesLineSeparators]),
               let match = regex.firstMatch(in: source, range: NSRange(source.startIndex..., in: source)),
               match.numberOfRanges > 1,
               let range = Range(match.range(at: 1), in: source) {
                return String(source[range])
            }
        }
        // Fallback: find the first View that appears near WindowGroup
        let lines = source.components(separatedBy: "\n")
        for (i, line) in lines.enumerated() {
            if line.contains("WindowGroup") {
                for j in (i + 1)..<min(i + 5, lines.count) {
                    let candidate = lines[j].trimmingCharacters(in: .whitespaces)
                    if let viewName = extractViewName(from: candidate) {
                        return viewName
                    }
                }
            }
        }
        return nil
    }

    private func extractViewName(from line: String) -> String? {
        // Match lines like "ContentView()" or "MyView(arg: val)"
        if let regex = try? NSRegularExpression(pattern: #"^\s*([A-Z]\w*)\s*\("#),
           let match = regex.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)),
           let range = Range(match.range(at: 1), in: line) {
            return String(line[range])
        }
        return nil
    }
}

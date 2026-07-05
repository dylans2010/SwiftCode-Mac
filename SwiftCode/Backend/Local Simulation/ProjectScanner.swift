import Foundation

final class ProjectScanner {
    func scan(projectDirectory: URL) throws -> ProjectStructure {
        let fileManager = FileManager.default
        guard let enumerator = fileManager.enumerator(at: projectDirectory, includingPropertiesForKeys: [.isRegularFileKey], options: [.skipsHiddenFiles]) else {
            throw SimulationError(type: .scan, message: "Failed to enumerate project directory.", file: projectDirectory.path, line: nil, stackTrace: nil)
        }

        var swiftFiles: [URL] = []
        var viewTypes: Set<String> = []
        var appEntry: URL?
        var dependencies: [URL: Set<String>] = [:]

        while let fileURL = enumerator.nextObject() as? URL {
            guard fileURL.pathExtension == "swift" else { continue }
            let isRegular = (try? fileURL.resourceValues(forKeys: [.isRegularFileKey]))?.isRegularFile == true
            guard isRegular else { continue }
            swiftFiles.append(fileURL)

            guard let source = try? String(contentsOf: fileURL, encoding: .utf8) else { continue }

            if source.contains("@main") && source.contains(": App") {
                appEntry = fileURL
            }

            for match in matches(in: source, pattern: #"struct\s+([A-Za-z_][A-Za-z0-9_]*)\s*:\s*[^\{]*\bView\b"#) {
                viewTypes.insert(match)
            }

            let importedModules = Set(matches(in: source, pattern: #"import\s+([A-Za-z_][A-Za-z0-9_]*)"#))
            dependencies[fileURL] = importedModules
        }

        return ProjectStructure(
            swiftFiles: swiftFiles.sorted { $0.path < $1.path },
            swiftUIViewTypes: Array(viewTypes).sorted(),
            appEntryPoint: appEntry,
            dependencies: dependencies
        )
    }

    private func matches(in source: String, pattern: String) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.dotMatchesLineSeparators]) else {
            return []
        }
        let range = NSRange(source.startIndex..., in: source)
        return regex.matches(in: source, range: range).compactMap { match in
            guard match.numberOfRanges > 1, let range = Range(match.range(at: 1), in: source) else { return nil }
            return String(source[range])
        }
    }
}

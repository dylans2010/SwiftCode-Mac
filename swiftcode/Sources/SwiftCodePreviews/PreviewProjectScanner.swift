import Foundation

/// Project structure for preview entry resolution (Legacy
/// `SwiftCode/Core/Preview/PreviewProjectScanner.swift`, Dylan's own
/// code, ported under MIT).
///
/// The target-membership filter is adapted: Legacy read it from
/// `ProjectResolutionService` (selected target + parsed projects),
/// which does not exist in the destination, and this target does not
/// depend on `SwiftCodeProject`, so the scanner cannot read
/// `project.pbxproj` itself. The caller passes the target's files
/// explicitly (`targetFiles`, computed with `PBXProj` by code in
/// `SwiftCodeIDECore` / `SwiftCodeMCP`); with no `targetFiles` the
/// whole directory is scanned. Adding `SwiftCodeProject` to this
/// target's dependencies would let the scanner compute the set
/// itself — recorded in the disposition as the wiring hook.
public struct PreviewProjectStructure: Sendable {
    public let swiftFiles: [URL]
    public let swiftUIViewTypes: [String]
    public let appEntryPoint: URL?
    public let dependencies: [URL: Set<String>]
}

public final class PreviewProjectScanner: Sendable {
    public init() {}

    /// Scans `projectDirectory` for `.swift` files, the `@main` App
    /// entry, `View` types, and per-file imports. When `targetFiles`
    /// is supplied, only those files (plus `activeFilePath`, when
    /// given) are kept — Legacy's active-target filter, with the
    /// file set computed by the caller (see the header note).
    public func scan(projectDirectory: URL, activeFilePath: String? = nil, targetFiles: Set<URL>? = nil) async throws -> PreviewProjectStructure {
        let fileManager = FileManager.default
        guard let enumerator = fileManager.enumerator(at: projectDirectory, includingPropertiesForKeys: [.isRegularFileKey], options: [.skipsHiddenFiles]) else {
            throw PreviewError.scanFailed(message: "Failed to enumerate project directory: \(projectDirectory.path)")
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

        // Apply target membership filtering
        var filteredSwiftFiles = swiftFiles
        if let targetFiles {
            filteredSwiftFiles = swiftFiles.filter { fileURL in
                targetFiles.contains(fileURL) || fileURL.path == activeFilePath
            }
        }

        return PreviewProjectStructure(
            swiftFiles: filteredSwiftFiles.sorted { $0.path < $1.path },
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

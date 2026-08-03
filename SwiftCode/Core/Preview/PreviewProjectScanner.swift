import Foundation

public struct PreviewProjectStructure: Sendable {
    public let swiftFiles: [URL]
    public let swiftUIViewTypes: [String]
    public let appEntryPoint: URL?
    public let dependencies: [URL: Set<String>]
}

public final class PreviewProjectScanner: Sendable {
    public init() {}

    private func getActiveTargetFiles(projectDirectory: URL) -> Set<URL>? {
        guard let targetID = ProjectResolutionService.shared.selectedTargetID else {
            return nil
        }

        for (_, model) in ProjectResolutionService.shared.parsedProjects {
            guard let target = model.targets.first(where: { $0.uuid == targetID }) else { continue }

            var fileRefUUIDs = Set<String>()
            for phase in model.buildPhases {
                if phase.isa == "PBXSourcesBuildPhase" && target.buildPhaseUUIDs.contains(phase.uuid) {
                    for fileUUID in phase.files {
                        if let fileRefUUID = model.buildFiles[fileUUID] {
                            fileRefUUIDs.insert(fileRefUUID)
                        }
                    }
                }
            }

            var files = Set<URL>()
            for fileRef in model.fileReferences {
                if fileRefUUIDs.contains(fileRef.uuid), let path = fileRef.path {
                    let cleanPath = path.replacingOccurrences(of: "\"", with: "")
                    let resolvedURL = projectDirectory.appendingPathComponent(cleanPath)
                    files.insert(resolvedURL)
                }
            }

            return files
        }
        return nil
    }

    public func scan(projectDirectory: URL, activeFilePath: String? = nil) throws -> PreviewProjectStructure {
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
        if let targetFiles = getActiveTargetFiles(projectDirectory: projectDirectory) {
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

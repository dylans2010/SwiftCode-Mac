import Foundation

/// [CRITICAL SYSTEM FILE] - HIGH RISK
/// Scans the project structure, analyzes dependencies, and identifies code quality issues.
@MainActor
public final class _AssistCriticalCodebaseAnalyzer: Sendable {
    private let context: AssistContext

    public init(context: AssistContext) {
        self.context = context
    }

    /// Performs a full scan of the project and returns a summary of the architecture.
    public func analyze() async throws -> CodebaseSummary {
        let root = context.workspaceRoot
        await context.logger.info("Analyzing codebase at \(root.path)", toolId: "CodebaseAnalyzer")

        // Offload disk-intensive file walking to background thread to avoid blocking main UI thread
        let allFiles = try await Task.detached(priority: .userInitiated) { [root] in
            try self.scanDirectory(at: root)
        }.value

        let swiftFiles = allFiles.filter { $0.hasSuffix(".swift") }

        // Find key project files
        let hasProjectFile = allFiles.contains { $0.hasSuffix(".xcodeproj") }
        let hasPackageSwift = allFiles.contains { $0.hasSuffix("Package.swift") }

        return CodebaseSummary(
            totalFiles: allFiles.count,
            swiftFileCount: swiftFiles.count,
            structure: "Scanned \(allFiles.count) files. Project types: \(hasProjectFile ? "Xcode" : "") \(hasPackageSwift ? "Swift Package" : "")."
        )
    }

    nonisolated private func scanDirectory(at url: URL) throws -> [String] {
        let fm = FileManager.default
        let resourceKeys: [URLResourceKey] = [.isRegularFileKey, .isDirectoryKey]

        guard let enumerator = fm.enumerator(at: url, includingPropertiesForKeys: resourceKeys, options: [.skipsHiddenFiles, .skipsPackageDescendants]) else {
            return []
        }

        var files: [String] = []
        let rootPath = url.standardized.path

        for case let fileURL as URL in enumerator {
            let resourceValues = try fileURL.resourceValues(forKeys: Set(resourceKeys))
            if resourceValues.isRegularFile ?? false {
                let filePath = fileURL.standardized.path
                let relativePath = filePath.replacingOccurrences(of: rootPath + "/", with: "")
                files.append(relativePath)
            }
        }
        return files
    }
}

public struct CodebaseSummary {
    public let totalFiles: Int
    public let swiftFileCount: Int
    public let structure: String
}

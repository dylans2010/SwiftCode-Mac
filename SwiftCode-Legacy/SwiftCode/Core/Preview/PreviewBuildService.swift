import Foundation
import os

public actor PreviewBuildService {
    private let logger = Logger(subsystem: "com.swiftcode.preview", category: "BuildService")
    private let scanner = PreviewProjectScanner()
    private let resolver = PreviewEntryResolver()
    private let compiler = PreviewRuntimeCompiler()
    private let sandbox = PreviewSandbox()

    public init() {}

    public func compilePreview(
        sourcePath: String,
        targetName: String,
        outputHandler: @escaping @Sendable (String) -> Void
    ) async throws -> URL {
        logger.info("[BEGIN] Compiling target preview view '\(targetName)' for file '\(sourcePath)'")
        let startTime = Date()

        let fileURL = URL(fileURLWithPath: sourcePath)
        let projectDir = fileURL.deletingLastPathComponent()

        outputHandler("Scanning project hierarchy...")
        let structure = try await scanner.scan(projectDirectory: projectDir, activeFilePath: sourcePath)

        outputHandler("Resolving SwiftUI entry targets...")
        let entry = try resolver.resolve(projectStructure: structure, preferredView: targetName)

        outputHandler("Applying workspace sandboxing...")
        let sandboxPolicy = sandbox.makePolicy(projectDirectory: projectDir)

        outputHandler("Compiling modules using swiftc...")
        let module = try await compiler.compile(projectStructure: structure, entry: entry, sandboxPolicy: sandboxPolicy)

        let duration = Date().timeIntervalSince(startTime)
        logger.info("[END] Completed compilation of '\(targetName)' in \(duration)s")
        outputHandler("Build succeeded in \(String(format: "%.2f", duration))s.")

        return module.libraryURL
    }
}

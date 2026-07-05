import Foundation

/// Prepares the runtime environment for the local simulation preview.
/// Validates project files, simulates build steps, and prepares the detected root view for rendering.
@MainActor
final class PreviewEngine {

    enum PreviewEngineError: LocalizedError {
        case noSwiftFilesFound
        case noAppEntryFound
        case noRootViewFound

        var errorDescription: String? {
            switch self {
            case .noSwiftFilesFound:
                return "No Swift files were found in the project."
            case .noAppEntryFound:
                return "Could not locate an @main App entry point in the project."
            case .noRootViewFound:
                return "Could not detect the root SwiftUI view inside WindowGroup."
            }
        }
    }

    struct PreviewContext {
        let projectDirectory: URL
        let swiftFiles: [URL]
        let appEntryFile: URL
        let rootViewName: String
    }

    private enum SimulatedDelay {
        static let resolveFiles: UInt64    = 200_000_000
        static let parseFiles: UInt64      = 300_000_000
        static let foundEntry: UInt64      = 150_000_000
        static let detectedView: UInt64    = 150_000_000
        static let prepareEnvironment: UInt64 = 300_000_000
        static let renderPreview: UInt64   = 200_000_000
    }

    /// Validates and prepares the project for preview rendering.
    /// Streams simulated build log messages via the provided callback.
    func prepare(
        analysisResult: ProjectAnalyzer.AnalysisResult,
        projectDirectory: URL,
        logHandler: @escaping (String) -> Void
    ) async throws -> PreviewContext {

        logHandler("Resolving project files...")
        try await Task.sleep(nanoseconds: SimulatedDelay.resolveFiles)

        guard !analysisResult.swiftFiles.isEmpty else {
            throw PreviewEngineError.noSwiftFilesFound
        }

        logHandler("Parsing \(analysisResult.swiftFiles.count) Swift file(s)...")
        try await Task.sleep(nanoseconds: SimulatedDelay.parseFiles)

        guard let appEntryFile = analysisResult.appEntryFile else {
            throw PreviewEngineError.noAppEntryFound
        }

        logHandler("Found app entry: \(appEntryFile.lastPathComponent)")
        try await Task.sleep(nanoseconds: SimulatedDelay.foundEntry)

        guard let rootViewName = analysisResult.rootViewName else {
            throw PreviewEngineError.noRootViewFound
        }

        logHandler("Detected root view: \(rootViewName)")
        try await Task.sleep(nanoseconds: SimulatedDelay.detectedView)

        logHandler("Preparing preview environment...")
        try await Task.sleep(nanoseconds: SimulatedDelay.prepareEnvironment)

        logHandler("Rendering preview...")
        try await Task.sleep(nanoseconds: SimulatedDelay.renderPreview)

        return PreviewContext(
            projectDirectory: projectDirectory,
            swiftFiles: analysisResult.swiftFiles,
            appEntryFile: appEntryFile,
            rootViewName: rootViewName
        )
    }
}

import Foundation
import Observation

@MainActor
@Observable
public final class ImportProjManager {
    public static let shared = ImportProjManager()
    private init() {}

    public var importProgress: Double = 0
    public var isImporting = false
    public var importError: Error?

    public func importProject(from url: URL) async throws -> Project {
        isImporting = true
        importProgress = 0
        importError = nil

        defer { isImporting = false }

        // Start accessing security scoped resource if needed
        let isAccessing = url.startAccessingSecurityScopedResource()
        defer { if isAccessing { url.stopAccessingSecurityScopedResource() } }

        importProgress = 0.2
        try ProjectValidator.shared.validate(packageURL: url)

        importProgress = 0.5
        let project = try await ProjectCoordinator.shared.importProject(from: url)

        importProgress = 1.0
        return project
    }
}

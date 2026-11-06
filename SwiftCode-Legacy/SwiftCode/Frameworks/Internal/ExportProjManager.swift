import Foundation
import Observation

@MainActor
@Observable
public final class ExportProjManager {
    public static let shared = ExportProjManager()
    private init() {}

    public var exportProgress: Double = 0
    public var isExporting = false
    public var exportError: Error?

    public func exportProject(_ project: Project, to url: URL) async throws {
        isExporting = true
        exportProgress = 0
        exportError = nil

        defer { isExporting = false }

        do {
            exportProgress = 0.3
            try await ProjectCoordinator.shared.exportProject(project, to: url)
            exportProgress = 1.0
        } catch {
            exportError = error
            throw error
        }
    }
}

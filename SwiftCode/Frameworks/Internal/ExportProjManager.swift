import Foundation

public final class ExportProjManager: ObservableObject {
    public static let shared = ExportProjManager()
    private init() {}

    @Published public var exportProgress: Double = 0
    @Published public var isExporting = false
    @Published public var exportError: Error?

    public func exportProject(_ project: Project, to url: URL) async throws {
        isExporting = true
        exportProgress = 0
        exportError = nil

        defer { isExporting = false }

        exportProgress = 0.3
        try await ProjectCoordinator.shared.exportProject(project, to: url)

        exportProgress = 1.0
    }
}

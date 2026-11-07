import Foundation

public actor ProjectOpeningCoordinator {
    public static let shared = ProjectOpeningCoordinator()

    public let timeout: TimeInterval

    public init(timeout: TimeInterval = 15) {
        self.timeout = timeout
    }

    public enum ProjectOpenError: Error, LocalizedError {
        case timeout(URL)
        case cancelled
        case failed(URL, Error)

        public var errorDescription: String? {
            switch self {
            case .timeout(let url):
                return "Opening \(url.lastPathComponent) timed out."
            case .cancelled:
                return "Opening the project was cancelled."
            case .failed(let url, let error):
                return "Could not open \(url.lastPathComponent): \(error.localizedDescription)"
            }
        }
    }

    public func open(_ url: URL) async throws -> WorkspaceSession {
        let timeout = self.timeout
        return try await withThrowingTaskGroup(of: WorkspaceSession.self) { group in
            group.addTask {
                try await self.openNow(url)
            }
            group.addTask {
                try await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
                throw ProjectOpenError.timeout(url)
            }
            do {
                guard let session = try await group.next() else {
                    throw ProjectOpenError.failed(url, CocoaError(.fileNoSuchFile))
                }
                group.cancelAll()
                return session
            } catch is CancellationError {
                group.cancelAll()
                throw ProjectOpenError.cancelled
            }
        }
    }

    private func openNow(_ url: URL) async throws -> WorkspaceSession {
        let accessing = url.startAccessingSecurityScopedResource()
        defer { if accessing { url.stopAccessingSecurityScopedResource() } }
        do {
            let model = try WorkspaceModel(url: url)
            return await MainActor.run { WorkspaceSession(model: model) }
        } catch {
            throw ProjectOpenError.failed(url, error)
        }
    }
}

import Foundation

/// Timeout-guarded project opening (Legacy
/// `SwiftCode/Backend/Project/ProjectOpeningCoordinator.swift`,
/// Dylan's own code, ported under MIT).
///
/// Legacy opened through its singletons with a 15-second timeout,
/// security-scoped bookmark access, and `ProjectOpenError.timeout` /
/// `.cancelled`. The destination opens through `WorkspaceModel(url:)`
/// + `WorkspaceSession`, so the coordinator wraps that pair with the
/// same 15-second timeout and the same security-scoped access. A
/// task cancelled while waiting reports `.cancelled`, exactly as
/// Legacy did.
///
/// Wiring: no lifecycle hook — call `open(_:)` from the open-project
/// flow (the App entry / workspace-open action) and present the
/// returned session.
public actor ProjectOpeningCoordinator {
    public static let shared = ProjectOpeningCoordinator()

    /// How long an open may take before it reports `.timeout`
    /// (Legacy's 15 seconds).
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

    /// Opens `url` as a workspace session, or throws
    /// `ProjectOpenError` when it times out, is cancelled, or the
    /// workspace cannot be constructed.
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
            // `WorkspaceSession` is `@MainActor`; hop there to build it.
            return await MainActor.run { WorkspaceSession(model: model) }
        } catch {
            throw ProjectOpenError.failed(url, error)
        }
    }
}

import Foundation

public struct BuildService {
    public init() {}

    public func build(
        projectPath: String,
        scheme: String,
        configuration: String,
        destination: String,
        onLog: @escaping @Sendable (String) -> Void
    ) async throws -> Bool {
        return try await BuildProjectCommand().execute(
            projectPath: projectPath,
            scheme: scheme,
            configuration: configuration,
            destination: destination,
            onLog: onLog
        )
    }
}

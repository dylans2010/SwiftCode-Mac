import Foundation

public struct InstallService {
    public init() {}

    public func install(
        deviceUDID: String,
        appBundleURL: URL,
        onProgress: @escaping @Sendable (String) -> Void
    ) async throws -> Bool {
        return try await InstallApplicationCommand().execute(
            deviceUDID: deviceUDID,
            appBundleURL: appBundleURL,
            onProgress: onProgress
        )
    }
}

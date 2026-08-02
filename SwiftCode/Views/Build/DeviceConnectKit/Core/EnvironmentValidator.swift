import Foundation
import OSLog

public struct EnvironmentValidator {
    private static let logger = Logger(subsystem: "com.swiftcode.deviceconnect", category: "EnvironmentValidator")

    public init() {}

    public func validate() async -> (environment: DeviceEnvironment, diagnostics: [String]) {
        do {
            let env = try await ValidateEnvironmentCommand().execute()
            let diagnostics = DiagnosticsFormatter.formatEnvironmentDiagnostics(env)
            return (env, diagnostics)
        } catch {
            Self.logger.error("Environment validation failed: \(error.localizedDescription)")
            let fallback = DeviceEnvironment()
            return (fallback, ["Validation failed to execute: \(error.localizedDescription)"])
        }
    }
}

import Foundation
import OSLog

public struct DiagnosticsCommand {
    private static let logger = Logger(subsystem: "com.swiftcode.deviceconnect", category: "DiagnosticsCommand")

    public init() {}

    public func execute() async throws -> String {
        let env = try await ValidateEnvironmentCommand().execute()
        let sdks = try await SDKValidationCommand().execute()
        let certs = try await SigningValidationCommand().execute()

        var report = "=== DeviceConnectKit System Diagnostics ===\n"
        report += "Date: \(Date())\n"
        report += "macOS Version: \(env.macOSVersion)\n"
        report += "Xcode Path: \(env.xcodePath ?? "Not Found")\n"
        report += "Xcode Version: \(env.xcodeVersion ?? "Not Found")\n"
        report += "Swift Version: \(env.swiftVersion ?? "Not Found")\n"
        report += "iOS SDK Available: \(env.hasiOSSDK ? "Yes" : "No")\n"
        report += "Simulator SDK Available: \(env.hasSimulatorSDK ? "Yes" : "No")\n"
        report += "Signing Configured: \(env.isSigningSetup ? "Yes" : "No")\n"

        report += "\n=== Available SDKs ===\n"
        if sdks.isEmpty {
            report += "No SDKs found.\n"
        } else {
            for sdk in sdks {
                report += "- \(sdk)\n"
            }
        }

        report += "\n=== Code Signing Identities ===\n"
        if certs.isEmpty {
            report += "No valid signing identities discovered.\n"
        } else {
            for cert in certs {
                report += "- \(cert)\n"
            }
        }

        return report
    }
}

import Foundation

public struct DiagnosticsFormatter {
    public static func formatEnvironmentDiagnostics(_ env: DeviceEnvironment) -> [String] {
        var diagnostics: [String] = []

        if env.xcodeVersion == nil {
            diagnostics.append("Missing: Xcode is not detected or registered in the environment. Please run 'xcode-select -s /Applications/Xcode.app' to set your path.")
        }
        if !env.hasiOSSDK {
            diagnostics.append("Missing SDK: The iOS SDK could not be verified. Ensure iOS build support is checked in your Xcode installations.")
        }
        if !env.isSigningSetup {
            diagnostics.append("Warning: Signing profiles are unverified. Builds might fail on physical devices unless codesigning is set up correctly in SwiftCode GitHub/Apple Settings.")
        }

        if diagnostics.isEmpty {
            diagnostics.append("All checks passed. System is fully compatible with DeviceConnect deployment pipelines.")
        }

        return diagnostics
    }

    public static func formatPipelineFailure(stage: DeploymentStatus, error: String) -> String {
        return """
        Deployment failed at stage: \(stage.description)
        Timestamp: \(ISO8601DateFormatter().string(from: Date()))
        Error Details: \(error)
        Suggested Action: Verify developer mode is active on your target device and connected securely.
        """
    }
}

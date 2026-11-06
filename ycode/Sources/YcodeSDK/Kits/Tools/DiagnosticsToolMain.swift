import Foundation

/// `diagnostics` tool (Legacy `Sources/Tools/DiagnosticsTool/main.swift`).
///
/// Runs the SDK doctor against a directory and prints its diagnostics.
/// Library entry point: the executable target wraps it in a thin `@main`
/// that calls `exit(DiagnosticsToolMain.run(...))`.
public enum DiagnosticsToolMain {
    public static func run(arguments: [String]) -> Int32 {
        let path = arguments.first ?? FileManager.default.currentDirectoryPath

        let coordinator = SwiftCodeSDKCoordinator()
        let report = coordinator.doctor.diagnose(sdkRoot: path)

        if !report.diagnostics.isEmpty {
            print(DiagnosticFormatter.formatText(report.diagnostics))
        } else {
            print("✅ No diagnostic issues detected.")
        }

        return report.isHealthy ? 0 : 1
    }
}

import Foundation

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

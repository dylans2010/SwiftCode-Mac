import Foundation
import SwiftCodeSDK

let args = Array(CommandLine.arguments.dropFirst())
let path = args.first ?? FileManager.default.currentDirectoryPath

let coordinator = SwiftCodeSDKCoordinator()
let report = coordinator.doctor.diagnose(sdkRoot: path)

if !report.diagnostics.isEmpty {
    print(DiagnosticFormatter.formatText(report.diagnostics))
} else {
    print("✅ No diagnostic issues detected.")
}

exit(report.isHealthy ? 0 : 1)

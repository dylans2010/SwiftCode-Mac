import Foundation
import SwiftCodeSDK

// `diagnostics`: run the SDK diagnostic engine over a path
// (Legacy SwiftCode/SDK/Sources/Tools/DiagnosticsTool).
// Thin wrapper over SwiftCodeSDK (`DiagnosticsToolMain`).
exit(DiagnosticsToolMain.run(arguments: Array(CommandLine.arguments.dropFirst())))

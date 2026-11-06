import Foundation
import YcodeSDK

// `diagnostics`: run the SDK diagnostic engine over a path
// (Legacy SwiftCode/SDK/Sources/Tools/DiagnosticsTool).
// Thin wrapper over YcodeSDK (`DiagnosticsToolMain`).
exit(DiagnosticsToolMain.run(arguments: Array(CommandLine.arguments.dropFirst())))

import Foundation
import YcodeSDK

// `extension-validator`: validate a `swiftcode.json` manifest
// (Legacy SwiftCode/SDK/Sources/Tools/ExtensionValidator).
// Thin wrapper over YcodeSDK (`ExtensionValidatorMain`).
exit(ExtensionValidatorMain.run(arguments: Array(CommandLine.arguments.dropFirst())))

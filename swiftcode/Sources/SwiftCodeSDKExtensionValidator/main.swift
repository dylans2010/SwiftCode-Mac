import Foundation
import SwiftCodeSDK

// `extension-validator`: validate a `swiftcode.json` manifest
// (Legacy SwiftCode/SDK/Sources/Tools/ExtensionValidator).
// Thin wrapper over SwiftCodeSDK (`ExtensionValidatorMain`).
exit(ExtensionValidatorMain.run(arguments: Array(CommandLine.arguments.dropFirst())))

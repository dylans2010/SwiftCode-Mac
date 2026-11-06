import Foundation
import SwiftCodeSDK

// `swiftcode`: the SwiftCode SDK command line (Legacy SwiftCode/SDK/Sources/CLI).
// Thin wrapper — the nine commands (doctor/init/validate/build/test/inspect/
// package/verify/docs) live in SwiftCodeSDK (`SwiftCodeSDKCLI`).
exit(await SwiftCodeSDKCLI.run(arguments: Array(CommandLine.arguments.dropFirst())))

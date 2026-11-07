import Foundation
import SwiftCodeSDK

exit(await SwiftCodeSDKCLI.run(arguments: Array(CommandLine.arguments.dropFirst())))

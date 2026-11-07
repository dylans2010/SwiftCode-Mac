import Foundation
import YcodeRelease
import YcodeXcodebuild

SwiftCodeRelease.handleVersionFlag(tool: "swiftcodebuild")
SwiftCodeRelease.adoptBundledHelpers()
let arguments = Array(CommandLine.arguments.dropFirst())
if arguments.count == 2, arguments[0] == "__list-swift-tests" {
    exit(await SwiftTestingBridge.listMain(executable: arguments[1]))
}
exit(Xcodebuild.run(arguments, context: .current()))

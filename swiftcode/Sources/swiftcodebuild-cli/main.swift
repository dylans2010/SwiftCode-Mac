import Foundation
import SwiftCodeRelease
import SwiftCodeXcodebuild

// swiftcodebuild: an xcodebuild-compatible command line built on SwiftCode's own
// project model and swift-build. See specs/xcodebuild/.
SwiftCodeRelease.handleVersionFlag(tool: "swiftcodebuild")
SwiftCodeRelease.adoptBundledHelpers()
let arguments = Array(CommandLine.arguments.dropFirst())
// Internal: list a test bundle's swift-testing tests (run by swiftcodebuild
// itself in a child process with the test frameworks on the search path).
if arguments.count == 2, arguments[0] == "__list-swift-tests" {
    exit(await SwiftTestingBridge.listMain(executable: arguments[1]))
}
exit(Xcodebuild.run(arguments, context: .current()))

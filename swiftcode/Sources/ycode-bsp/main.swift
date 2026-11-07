import Foundation
import YcodeBuildServer
import YcodeRelease

SwiftCodeRelease.handleVersionFlag(tool: "swiftcode-bsp")
SwiftCodeRelease.adoptBundledHelpers()
exit(BuildServerMain.run(Array(CommandLine.arguments.dropFirst())))

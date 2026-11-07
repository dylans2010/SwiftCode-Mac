import Foundation
import SwiftCodeBuildServer
import SwiftCodeRelease

SwiftCodeRelease.handleVersionFlag(tool: "swiftcode-bsp")
SwiftCodeRelease.adoptBundledHelpers()
exit(BuildServerMain.run(Array(CommandLine.arguments.dropFirst())))

import Foundation
import SwiftCodeBuildServer
import SwiftCodeRelease

// swiftcode-bsp: SwiftCode's build server for sourcekit-lsp (Build Server Protocol
// over stdin/stdout), plus commands that show what it answers. See
// specs/ide/language.md §Build server.
SwiftCodeRelease.handleVersionFlag(tool: "swiftcode-bsp")
SwiftCodeRelease.adoptBundledHelpers()
exit(BuildServerMain.run(Array(CommandLine.arguments.dropFirst())))

import Foundation
import YcodeSDK

// `project-generator`: scaffold a project from a template
// (Legacy SwiftCode/SDK/Sources/Tools/ProjectGenerator).
// Thin wrapper over YcodeSDK (`ProjectGeneratorMain`).
exit(ProjectGeneratorMain.run(arguments: Array(CommandLine.arguments.dropFirst())))

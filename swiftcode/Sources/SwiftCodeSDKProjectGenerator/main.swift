import Foundation
import SwiftCodeSDK

// `project-generator`: scaffold a project from a template
// (Legacy SwiftCode/SDK/Sources/Tools/ProjectGenerator).
// Thin wrapper over SwiftCodeSDK (`ProjectGeneratorMain`).
exit(ProjectGeneratorMain.run(arguments: Array(CommandLine.arguments.dropFirst())))

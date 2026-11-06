import Foundation
import SwiftCodeSDK

// `project-inspector`: print a project's metadata as JSON
// (Legacy SwiftCode/SDK/Sources/Tools/ProjectInspector).
// Thin wrapper over SwiftCodeSDK (`ProjectInspectorMain`).
exit(ProjectInspectorMain.run(arguments: Array(CommandLine.arguments.dropFirst())))

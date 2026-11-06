import Foundation

public struct AssistBuildSystemDetectTool: AssistTool {
    public let id = "build_system_detect"
    public let name = "Build System Detect"
    public let description = "Detects the build systems in use: .xcworkspace/.xcodeproj, SwiftPM, CocoaPods, Carthage, Tuist, xcodegen, Bazel, CMake."

    public init() {}

    public var capability: ToolCapability { .repositoryDiscovery }
    public var riskLevel: ToolRiskLevel { .safeRead }

    public var parametersSchema: JSONSchema {
        JSONSchema(type: "object", description: "Detects build systems.", properties: [:], required: [])
    }

    public func execute(input: [String: Any], context: AssistContext) async throws -> AssistToolResult {
        let root = context.workspaceRoot
        let fm = FileManager.default
        var found: [(String, String)] = []
        let checks: [(String, String)] = [
            ("xcworkspace", ".xcworkspace"), ("xcodeproj", ".xcodeproj"),
            ("Package.swift", "SwiftPM"), ("Podfile", "CocoaPods"),
            ("Cartfile", "Carthage"), ("Project.swift", "Tuist"),
            ("project.yml", "xcodegen"), ("BUILD", "Bazel"),
            ("CMakeLists.txt", "CMake"), ("Makefile", "Make")
        ]
        for (name, system) in checks {
            let url = root.appendingPathComponent(name)
            var isDir: ObjCBool = false
            if fm.fileExists(atPath: url.path, isDirectory: &isDir) {
                // Directories only count for bundle-style markers.
                if isDir.boolValue {
                    if name.hasPrefix(".") { found.append((name, system)) }
                } else {
                    found.append((name, system))
                }
            }
        }
        if found.isEmpty {
            return .success("No recognized build system files found in the workspace root.", data: ["count": "0"])
        }
        var lines = ["Build systems detected:"]
        for (name, system) in found {
            lines.append("- \(system): \(name)")
        }
        return .success(lines.joined(separator: "\n"), data: ["count": "\(found.count)"])
    }
}

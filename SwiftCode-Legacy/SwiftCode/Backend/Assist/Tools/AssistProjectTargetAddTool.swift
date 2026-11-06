import Foundation

public struct AssistProjectTargetAddTool: AssistTool {
    public let id = "project_target_add"
    public let name = "Add Target"
    public let description = "Adds a new Xcode target: creates a source directory with a real Swift file and inserts PBXNativeTarget blocks into project.pbxproj."

    public init() {}

    public var capability: ToolCapability { .compilation }
    public var riskLevel: ToolRiskLevel { .safeMutation }

    public var parametersSchema: JSONSchema {
        JSONSchema(
            type: "object",
            description: "Adds a new Xcode target to project.pbxproj.",
            properties: [
                "targetName": JSONSchema(type: "string", description: "Name of the new target. Letters, digits, underscore, hyphen only."),
                "type": JSONSchema(type: "string", description: "Target type: app, framework, or test. Default: app."),
                "bundleId": JSONSchema(type: "string", description: "Optional bundle identifier for the new target.")
            ],
            required: ["targetName"]
        )
    }

    public func execute(input: [String: Any], context: AssistContext) async throws -> AssistToolResult {
        guard let rawName = (input["targetName"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
              !rawName.isEmpty else {
            return .failure("Missing required parameter: targetName")
        }
        let type = (input["type"] as? String ?? "app").lowercased()
        guard type == "app" || type == "framework" || type == "test" else {
            return .failure("Invalid type '\(type)'. Expected app, framework, or test.")
        }
        let bundleId = (input["bundleId"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard isValidTargetName(rawName) else {
            return .failure("Invalid target name '\(rawName)'. Use letters, digits, underscore, or hyphen only.")
        }
        if let bundleId, !bundleId.isEmpty, !isValidBundleId(bundleId) {
            return .failure("Invalid bundleId '\(bundleId)'.")
        }
        guard let pbxURL = findPBXProjURL(in: context.workspaceRoot) else {
            return .failure("No project.pbxproj found in the workspace.")
        }
        guard let content = try? String(contentsOf: pbxURL, encoding: .utf8) else {
            return .failure("Failed to read project.pbxproj.")
        }
        if content.contains("/* \(rawName) */ = {") && content.contains("isa = PBXNativeTarget") {
            return .failure("Target '\(rawName)' already exists in project.pbxproj.")
        }
        // Verify all insertion anchors exist BEFORE writing anything.
        guard content.contains("/* Begin PBXNativeTarget section */") else {
            return .failure("project.pbxproj is missing the Begin PBXNativeTarget section anchor. No changes were made.")
        }
        guard content.contains("/* Begin XCBuildConfigurationList section */") else {
            return .failure("project.pbxproj is missing the Begin XCBuildConfigurationList section anchor. No changes were made.")
        }
        guard content.contains("/* Begin XCBuildConfiguration section */") else {
            return .failure("project.pbxproj is missing the Begin XCBuildConfiguration section anchor. No changes were made.")
        }

        // Create the target source directory and a real Swift file.
        let targetDir = context.workspaceRoot.appendingPathComponent(rawName)
        if FileManager.default.fileExists(atPath: targetDir.path) {
            return .failure("Directory '\(rawName)' already exists in the workspace. No changes were made.")
        }
        do {
            try FileManager.default.createDirectory(at: targetDir, withIntermediateDirectories: true)
            let fileURL = targetDir.appendingPathComponent("\(swiftTypeName(for: rawName)).swift")
            try swiftSource(for: rawName, type: type).write(to: fileURL, atomically: true, encoding: .utf8)
        } catch {
            return .failure("Failed to create target source files: \(error.localizedDescription)")
        }

        // Generate collision-free pbxproj IDs.
        let targetID = uniqueID(notIn: content)
        let configListID = uniqueID(notIn: content)
        let debugID = uniqueID(notIn: content)
        let releaseID = uniqueID(notIn: content)

        let productType: String
        switch type {
        case "framework": productType = "com.apple.product-type.framework"
        case "test": productType = "com.apple.product-type.bundle.unit-test"
        default: productType = "com.apple.product-type.application"
        }

        let bundleLine: String
        if let bundleId, !bundleId.isEmpty {
            bundleLine = "\n\t\t\t\tPRODUCT_BUNDLE_IDENTIFIER = \(bundleId);"
        } else {
            bundleLine = ""
        }

        let targetBlock = """
        \t\t\(targetID) /* \(rawName) */ = {
        \t\t\tisa = PBXNativeTarget;
        \t\t\tbuildConfigurationList = \(configListID) /* Build configuration list for PBXNativeTarget "\(rawName)" */;
        \t\t\tbuildPhases = (
        \t\t\t);
        \t\t\tbuildRules = (
        \t\t\t);
        \t\t\tdependencies = (
        \t\t\t);
        \t\t\tname = \(rawName);
        \t\t\tproductName = \(rawName);
        \t\t\tproductType = "\(productType)";
        \t\t};
        """

        let configListBlock = """
        \t\t\(configListID) /* Build configuration list for PBXNativeTarget "\(rawName)" */ = {
        \t\t\tisa = XCBuildConfigurationList;
        \t\t\tbuildConfigurations = (
        \t\t\t\t\(debugID) /* Debug */,
        \t\t\t\t\(releaseID) /* Release */,
        \t\t\t);
        \t\t\tdefaultConfigurationIsVisible = 0;
        \t\t\tdefaultConfigurationName = Release;
        \t\t};
        """

        let debugBlock = """
        \t\t\(debugID) /* Debug */ = {
        \t\t\tisa = XCBuildConfiguration;
        \t\t\tbuildSettings = {
        \t\t\t\tPRODUCT_NAME = "$(TARGET_NAME)";\(bundleLine)
        \t\t\t};
        \t\t\tname = Debug;
        \t\t};
        """

        let releaseBlock = """
        \t\t\(releaseID) /* Release */ = {
        \t\t\tisa = XCBuildConfiguration;
        \t\t\tbuildSettings = {
        \t\t\t\tPRODUCT_NAME = "$(TARGET_NAME)";\(bundleLine)
        \t\t\t};
        \t\t\tname = Release;
        \t\t};
        """

        var lines = content.components(separatedBy: "\n")
        insert(block: targetBlock, afterAnchor: "/* Begin PBXNativeTarget section */", into: &lines)
        insert(block: configListBlock, afterAnchor: "/* Begin XCBuildConfigurationList section */", into: &lines)
        insert(block: debugBlock, afterAnchor: "/* Begin XCBuildConfiguration section */", into: &lines)
        insert(block: releaseBlock, afterAnchor: "/* Begin XCBuildConfiguration section */", into: &lines)

        let updated = lines.joined(separator: "\n")
        do {
            try updated.write(to: pbxURL, atomically: true, encoding: .utf8)
        } catch {
            return .failure("Failed to write project.pbxproj: \(error.localizedDescription)")
        }
        guard let verify = try? String(contentsOf: pbxURL, encoding: .utf8),
              verify.contains("/* \(rawName) */ = {"),
              verify.contains("isa = PBXNativeTarget") else {
            return .failure("Verification failed: target '\(rawName)' not found after writing project.pbxproj.")
        }
        return .success(
            "Added target '\(rawName)' (\(type)) with source directory '\(rawName)/'.",
            data: ["targetName": rawName, "type": type, "targetId": targetID, "sourceDirectory": rawName],
            filesChanged: ["project.pbxproj", "\(rawName)/\(swiftTypeName(for: rawName)).swift"]
        )
    }

    private func isValidTargetName(_ name: String) -> Bool {
        guard !name.isEmpty, name.count <= 64, !name.contains(".."), !name.contains("/") else { return false }
        let allowed = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789_-")
        return name.unicodeScalars.allSatisfy { allowed.contains($0) }
    }

    private func isValidBundleId(_ id: String) -> Bool {
        guard !id.isEmpty, !id.contains(" ") else { return false }
        let allowed = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-.")
        return id.unicodeScalars.allSatisfy { allowed.contains($0) }
    }

    private func swiftTypeName(for targetName: String) -> String {
        let cleaned = targetName.replacingOccurrences(of: "-", with: "_")
        guard let first = cleaned.first else { return "Main" }
        return String(first).uppercased() + String(cleaned.dropFirst())
    }

    private func swiftSource(for targetName: String, type: String) -> String {
        let typeName = swiftTypeName(for: targetName)
        switch type {
        case "framework":
            return "import Foundation\n\n/// \(targetName) framework entry point.\npublic struct \(typeName) {\n    public init() {}\n}\n"
        case "test":
            return "import XCTest\n\nfinal class \(typeName)Tests: XCTestCase {\n    func testExample() {\n        XCTAssertTrue(true)\n    }\n}\n"
        default:
            return "import Foundation\n\n/// \(targetName) app entry point.\npublic struct \(typeName)App {\n    public init() {}\n}\n"
        }
    }

    private func uniqueID(notIn content: String) -> String {
        var candidate = ""
        repeat {
            candidate = String(UUID().uuidString.replacingOccurrences(of: "-", with: "").prefix(24)).uppercased()
        } while content.contains(candidate)
        return candidate
    }

    private func insert(block: String, afterAnchor anchor: String, into lines: inout [String]) {
        for (index, line) in lines.enumerated() where line.contains(anchor) {
            lines.insert(block, at: index + 1)
            return
        }
    }

    private func findPBXProjURL(in workspaceRoot: URL) -> URL? {
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(at: workspaceRoot, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]) else { return nil }
        for case let url as URL in enumerator {
            if url.lastPathComponent == "project.pbxproj" { return url }
        }
        return nil
    }
}

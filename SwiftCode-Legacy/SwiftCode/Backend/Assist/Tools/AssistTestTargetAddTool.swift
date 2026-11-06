import Foundation

public struct AssistTestTargetAddTool: AssistTool {
    public let id = "test_target_add"
    public let name = "Add Test Target"
    public let description = "Creates a test directory with a real XCTest file and inserts a PBXNativeTarget block into the project pbxproj."

    public init() {}

    public var capability: ToolCapability { .compilation }
    public var riskLevel: ToolRiskLevel { .safeMutation }

    public var parametersSchema: JSONSchema {
        JSONSchema(
            type: "object",
            description: "Adds a unit or UI test target to the Xcode project found in the workspace root.",
            properties: [
                "targetName": JSONSchema(type: "string", description: "Required. Valid identifier for the new test target."),
                "type": JSONSchema(type: "string", description: "unit or ui. Default: unit.")
            ],
            required: ["targetName"]
        )
    }

    public func execute(input: [String: Any], context: AssistContext) async throws -> AssistToolResult {
        guard let targetName = (input["targetName"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines), !targetName.isEmpty else {
            return .failure("Missing required parameter: targetName")
        }
        guard isValidIdentifier(targetName) else {
            return .failure("targetName '\(targetName)' is not a valid identifier. Use letters, digits, and underscores, starting with a letter or underscore.")
        }
        let type = ((input["type"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()).flatMap { $0.isEmpty ? nil : $0 } ?? "unit"
        guard type == "unit" || type == "ui" else {
            return .failure("type must be 'unit' or 'ui'.")
        }
        guard let projectURL = findXcodeproj(in: context.workspaceRoot) else {
            return .failure("No .xcodeproj found in the workspace root. Open a project first.")
        }
        let pbxprojURL = projectURL.appendingPathComponent("project.pbxproj")
        guard FileManager.default.fileExists(atPath: pbxprojURL.path) else {
            return .failure("project.pbxproj not found in '\(projectURL.lastPathComponent)'.")
        }
        guard var pbxproj = try? String(contentsOf: pbxprojURL, encoding: .utf8) else {
            return .failure("Could not read project.pbxproj as UTF-8 text.")
        }
        if pbxproj.contains("name = \(targetName);") || pbxproj.contains("/* \(targetName) */") {
            return .failure("A target named '\(targetName)' already exists in project.pbxproj.")
        }
        let testDir = context.workspaceRoot.appendingPathComponent(targetName)
        if FileManager.default.fileExists(atPath: testDir.path) {
            return .failure("Directory '\(targetName)' already exists in the workspace. Choose a different targetName.")
        }
        let anchors = [
            "/* Begin PBXNativeTarget section */",
            "/* Begin PBXFileReference section */",
            "/* Begin PBXSourcesBuildPhase section */",
            "/* Begin PBXFrameworksBuildPhase section */",
            "/* Begin XCBuildConfigurationList section */",
            "/* Begin XCBuildConfiguration section */",
            "targets = ("
        ]
        for anchor in anchors {
            guard pbxproj.contains(anchor) else {
                return .failure("project.pbxproj is missing required anchor '\(anchor)'. No changes were written.")
            }
        }
        let testFileURL = testDir.appendingPathComponent("\(targetName)Tests.swift")
        do {
            try FileManager.default.createDirectory(at: testDir, withIntermediateDirectories: true)
            try buildTestContent(targetName: targetName, type: type).write(to: testFileURL, atomically: true, encoding: .utf8)
        } catch {
            try? FileManager.default.removeItem(at: testDir)
            return .failure("Failed to create test file: \(error.localizedDescription)")
        }

        let ids = makeIDs(existing: pbxproj, count: 12)
        let targetID = ids[0]
        let productRefID = ids[1]
        let sourcesID = ids[2]
        let frameworksID = ids[3]
        let configListID = ids[4]
        let debugConfigID = ids[5]
        let releaseConfigID = ids[6]
        let productType = type == "ui" ? "com.apple.product-type.bundle.ui-testing" : "com.apple.product-type.bundle.unit-test"
        let productName = "\(targetName).xctest"

        let targetBlock = "\t\t\(targetID) /* \(targetName) */ = {\n\t\t\tisa = PBXNativeTarget;\n\t\t\tbuildConfigurationList = \(configListID) /* Build configuration list for PBXNativeTarget \"\(targetName)\" */;\n\t\t\tbuildPhases = (\n\t\t\t\t\(sourcesID) /* Sources */,\n\t\t\t\t\(frameworksID) /* Frameworks */,\n\t\t\t);\n\t\t\tbuildRules = (\n\t\t\t);\n\t\t\tdependencies = (\n\t\t\t);\n\t\t\tname = \(targetName);\n\t\t\tproductName = \(targetName);\n\t\t\tproductReference = \(productRefID) /* \(productName) */;\n\t\t\tproductType = \"\(productType)\";\n\t\t};\n"
        let fileRefBlock = "\t\t\(productRefID) /* \(productName) */ = {isa = PBXFileReference; explicitFileType = wrapper.cfbundle; includeInIndex = 0; path = \(productName); sourceTree = BUILT_PRODUCTS_DIR; };\n"
        let sourcesBlock = "\t\t\(sourcesID) /* Sources */ = {\n\t\t\tisa = PBXSourcesBuildPhase;\n\t\t\tbuildActionMask = 2147483647;\n\t\t\tfiles = (\n\t\t\t);\n\t\t\trunOnlyForDeploymentPostprocessing = 0;\n\t\t};\n"
        let frameworksBlock = "\t\t\(frameworksID) /* Frameworks */ = {\n\t\t\tisa = PBXFrameworksBuildPhase;\n\t\t\tbuildActionMask = 2147483647;\n\t\t\tfiles = (\n\t\t\t);\n\t\t\trunOnlyForDeploymentPostprocessing = 0;\n\t\t};\n"
        let configListBlock = "\t\t\(configListID) /* Build configuration list for PBXNativeTarget \"\(targetName)\" */ = {\n\t\t\tisa = XCBuildConfigurationList;\n\t\t\tbuildConfigurations = (\n\t\t\t\t\(debugConfigID) /* Debug */,\n\t\t\t\t\(releaseConfigID) /* Release */,\n\t\t\t);\n\t\t\tdefaultConfigurationIsVisible = 0;\n\t\t\tdefaultConfigurationName = Release;\n\t\t};\n"
        let debugBlock = "\t\t\(debugConfigID) /* Debug */ = {\n\t\t\tisa = XCBuildConfiguration;\n\t\t\tbuildSettings = {\n\t\t\t\tIPHONEOS_DEPLOYMENT_TARGET = 17.0;\n\t\t\t\tMACOSX_DEPLOYMENT_TARGET = 14.0;\n\t\t\t\tPRODUCT_NAME = \"$(TARGET_NAME)\";\n\t\t\t\tSWIFT_EMBED_LIBRARIES_WITH_INSTALL = YES;\n\t\t\t};\n\t\t\tname = Debug;\n\t\t};\n"
        let releaseBlock = "\t\t\(releaseConfigID) /* Release */ = {\n\t\t\tisa = XCBuildConfiguration;\n\t\t\tbuildSettings = {\n\t\t\t\tIPHONEOS_DEPLOYMENT_TARGET = 17.0;\n\t\t\t\tMACOSX_DEPLOYMENT_TARGET = 14.0;\n\t\t\t\tPRODUCT_NAME = \"$(TARGET_NAME)\";\n\t\t\t\tSWIFT_EMBED_LIBRARIES_WITH_INSTALL = YES;\n\t\t\t};\n\t\t\tname = Release;\n\t\t};\n"

        guard insert(&pbxproj, block: targetBlock, afterAnchor: "/* Begin PBXNativeTarget section */"),
              insert(&pbxproj, block: fileRefBlock, afterAnchor: "/* Begin PBXFileReference section */"),
              insert(&pbxproj, block: sourcesBlock, afterAnchor: "/* Begin PBXSourcesBuildPhase section */"),
              insert(&pbxproj, block: frameworksBlock, afterAnchor: "/* Begin PBXFrameworksBuildPhase section */"),
              insert(&pbxproj, block: configListBlock, afterAnchor: "/* Begin XCBuildConfigurationList section */"),
              insert(&pbxproj, block: debugBlock, afterAnchor: "/* Begin XCBuildConfiguration section */"),
              insert(&pbxproj, block: releaseBlock, afterAnchor: "/* Begin XCBuildConfiguration section */"),
              insert(&pbxproj, block: "\t\t\t\t\(targetID) /* \(targetName) */,\n", afterAnchor: "targets = (") else {
            try? FileManager.default.removeItem(at: testDir)
            return .failure("Failed to insert the new target blocks into project.pbxproj. No changes were kept.")
        }
        do {
            try pbxproj.write(to: pbxprojURL, atomically: true, encoding: .utf8)
        } catch {
            try? FileManager.default.removeItem(at: testDir)
            return .failure("Failed to write project.pbxproj: \(error.localizedDescription). Test files were removed.")
        }
        guard let verify = try? String(contentsOf: pbxprojURL, encoding: .utf8),
              verify.contains("name = \(targetName);"),
              verify.contains(targetID) else {
            return .failure("Verification failed: target '\(targetName)' was not found in project.pbxproj after writing.")
        }
        return .success("Added test target '\(targetName)' (\(type)) with test file \(targetName)/\(targetName)Tests.swift and PBXNativeTarget entry in project.pbxproj.", data: [
            "targetName": targetName,
            "type": type,
            "targetID": targetID,
            "testFile": "\(targetName)/\(targetName)Tests.swift"
        ])
    }

    private func buildTestContent(targetName: String, type: String) -> String {
        var lines: [String] = []
        lines.append("import XCTest")
        lines.append("")
        if type == "ui" {
            lines.append("final class \(targetName)Tests: XCTestCase {")
            lines.append("    func testLaunch() throws {")
            lines.append("        let app = XCUIApplication()")
            lines.append("        app.launch()")
            lines.append("        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 10))")
            lines.append("    }")
        } else {
            lines.append("final class \(targetName)Tests: XCTestCase {")
            lines.append("    func testExample() throws {")
            lines.append("        XCTAssertEqual(1 + 1, 2)")
            lines.append("    }")
        }
        lines.append("}")
        return lines.joined(separator: "\n") + "\n"
    }

    private func insert(_ text: inout String, block: String, afterAnchor anchor: String) -> Bool {
        guard let range = text.range(of: anchor) else { return false }
        guard let lineEnd = text.range(of: "\n", options: [], range: range.upperBound..<text.endIndex) else { return false }
        text.insert(contentsOf: block, at: lineEnd.upperBound)
        return true
    }

    private func makeIDs(existing: String, count: Int) -> [String] {
        var ids: [String] = []
        var attempts = 0
        while ids.count < count && attempts < 200 {
            attempts += 1
            let candidate = String(UUID().uuidString.replacingOccurrences(of: "-", with: "").prefix(24).uppercased())
            if candidate.count != 24 { continue }
            if existing.contains(candidate) { continue }
            if ids.contains(candidate) { continue }
            ids.append(candidate)
        }
        return ids
    }

    private func findXcodeproj(in workspaceRoot: URL) -> URL? {
        let fm = FileManager.default
        if let top = try? fm.contentsOfDirectory(at: workspaceRoot, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]) {
            for item in top where item.pathExtension == "xcodeproj" { return item }
        }
        guard let enumerator = fm.enumerator(at: workspaceRoot, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]) else { return nil }
        for case let url as URL in enumerator {
            let name = url.lastPathComponent
            if name == ".git" || name == "build" || name == "DerivedData" || name == "Pods" {
                enumerator.skipDescendants()
                continue
            }
            if url.pathExtension == "xcodeproj" { return url }
        }
        return nil
    }

    private func isValidIdentifier(_ value: String) -> Bool {
        guard let first = value.unicodeScalars.first else { return false }
        guard CharacterSet.letters.contains(first) || first == "_" else { return false }
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "_"))
        return value.unicodeScalars.allSatisfy { allowed.contains($0) }
    }
}

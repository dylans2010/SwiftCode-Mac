import Foundation

public struct AssistUITestScaffoldTool: AssistTool {
    public let id = "ui_test_scaffold"
    public let name = "UI Test Scaffold"
    public let description = "Creates a real XCTest UI test file with setUp, launch, a launch-state assertion, and tearDown."

    public init() {}

    public var capability: ToolCapability { .testing }
    public var riskLevel: ToolRiskLevel { .safeMutation }

    public var parametersSchema: JSONSchema {
        JSONSchema(
            type: "object",
            description: "Scaffolds a UI test file. Refuses to overwrite an existing file unless overwrite is true.",
            properties: [
                "testName": JSONSchema(type: "string", description: "Required. Valid Swift identifier used for the test class and file name."),
                "targetApp": JSONSchema(type: "string", description: "Optional bundle identifier of the app under test. When empty, XCUIApplication() is used."),
                "path": JSONSchema(type: "string", description: "Workspace-relative directory for the new test file. Default: UITests/."),
                "overwrite": JSONSchema(type: "string", description: "Must be 'true' to replace an existing file. Default: 'false'.")
            ],
            required: ["testName"]
        )
    }

    public func execute(input: [String: Any], context: AssistContext) async throws -> AssistToolResult {
        guard let testName = (input["testName"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines), !testName.isEmpty else {
            return .failure("Missing required parameter: testName")
        }
        guard isValidIdentifier(testName) else {
            return .failure("testName '\(testName)' is not a valid Swift identifier. Use letters, digits, and underscores, starting with a letter or underscore.")
        }
        let targetApp = (input["targetApp"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let dirRaw = ((input["path"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)).flatMap { $0.isEmpty ? nil : $0 } ?? "UITests/"
        guard let dirURL = resolveInsideWorkspace(dirRaw, workspaceRoot: context.workspaceRoot) else {
            return .failure("path must be inside the workspace and must not contain '..'.")
        }
        let overwrite = (input["overwrite"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == "true"
            || (input["overwrite"] as? Bool) == true
        let fileURL = dirURL.appendingPathComponent("\(testName).swift")
        if FileManager.default.fileExists(atPath: fileURL.path) && !overwrite {
            return .failure("File already exists at '\(relativePath(of: fileURL, workspaceRoot: context.workspaceRoot))'. Pass overwrite='true' to replace it.")
        }
        do {
            try FileManager.default.createDirectory(at: dirURL, withIntermediateDirectories: true)
            try buildContent(testName: testName, targetApp: targetApp).write(to: fileURL, atomically: true, encoding: .utf8)
        } catch {
            return .failure("Failed to create UI test file: \(error.localizedDescription)")
        }
        return .success("Created UI test file at \(relativePath(of: fileURL, workspaceRoot: context.workspaceRoot))", data: [
            "path": relativePath(of: fileURL, workspaceRoot: context.workspaceRoot),
            "testName": testName
        ])
    }

    private func buildContent(testName: String, targetApp: String) -> String {
        var lines: [String] = []
        lines.append("import XCTest")
        lines.append("")
        lines.append("final class \(testName): XCTestCase {")
        lines.append("    private var app: XCUIApplication!")
        lines.append("")
        lines.append("    override func setUpWithError() throws {")
        lines.append("        continueAfterFailure = false")
        if targetApp.isEmpty {
            lines.append("        app = XCUIApplication()")
        } else {
            lines.append("        app = XCUIApplication(bundleIdentifier: \"\(targetApp)\")")
        }
        lines.append("    }")
        lines.append("")
        lines.append("    override func tearDownWithError() throws {")
        lines.append("        app = nil")
        lines.append("    }")
        lines.append("")
        lines.append("    func testLaunch() throws {")
        lines.append("        app.launch()")
        lines.append("        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 10), \"App did not reach the foreground after launch.\")")
        lines.append("        XCTAssertTrue(app.state == .runningForeground)")
        lines.append("    }")
        lines.append("}")
        return lines.joined(separator: "\n") + "\n"
    }

    private func isValidIdentifier(_ value: String) -> Bool {
        guard let first = value.unicodeScalars.first else { return false }
        let letters = CharacterSet.letters
        let firstOK = letters.contains(first) || first == "_"
        guard firstOK else { return false }
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "_"))
        return value.unicodeScalars.allSatisfy { allowed.contains($0) }
    }

    private func resolveInsideWorkspace(_ rawPath: String, workspaceRoot: URL) -> URL? {
        if rawPath.isEmpty { return nil }
        if rawPath.components(separatedBy: "/").contains("..") { return nil }
        let root = workspaceRoot.standardized
        let candidate: URL
        if rawPath.hasPrefix("/") {
            candidate = URL(fileURLWithPath: rawPath).standardized
        } else {
            candidate = root.appendingPathComponent(rawPath).standardized
        }
        let rootPath = root.path
        if candidate.path == rootPath { return candidate }
        if candidate.path.hasPrefix(rootPath + "/") { return candidate }
        return nil
    }

    private func relativePath(of url: URL, workspaceRoot: URL) -> String {
        let root = workspaceRoot.standardized.path
        let path = url.standardized.path
        if path.hasPrefix(root + "/") { return String(path.dropFirst(root.count + 1)) }
        return url.lastPathComponent
    }
}

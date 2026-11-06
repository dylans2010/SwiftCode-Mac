import Foundation

public struct AssistTestRunSingleTool: AssistTool {
    public let id = "test_run_single"
    public let name = "Run Single Test"
    public let description = "Runs one test by ID with xcodebuild test -only-testing and returns pass/fail plus the output tail."

    public init() {}

    public var capability: ToolCapability { .testing }
    public var riskLevel: ToolRiskLevel { .execution }

    public var parametersSchema: JSONSchema {
        JSONSchema(
            type: "object",
            description: "Runs a single test such as MyTests/MyTest/testExample.",
            properties: [
                "testId": JSONSchema(type: "string", description: "Required. Test identifier, e.g. MyTests/MyTest/testExample."),
                "scheme": JSONSchema(type: "string", description: "Scheme to test. Defaults to the first scheme listed by xcodebuild."),
                "destination": JSONSchema(type: "string", description: "xcodebuild destination. Default: platform=macOS.")
            ],
            required: ["testId"]
        )
    }

    public func execute(input: [String: Any], context: AssistContext) async throws -> AssistToolResult {
        guard let testId = (input["testId"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines), !testId.isEmpty else {
            return .failure("Missing required parameter: testId")
        }
        guard isValidTestId(testId) else {
            return .failure("testId '\(testId)' is not valid. Expected a form like MyTests/MyTest/testExample with no spaces or shell characters.")
        }
        let destination: String = {
            if let d = input["destination"] as? String, !d.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return d }
            return "platform=macOS"
        }()
        if hasUnsafeShellCharacters(destination) {
            return .failure("destination contains characters that are not allowed.")
        }
        let explicitScheme = (input["scheme"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let s = explicitScheme, !s.isEmpty, hasUnsafeShellCharacters(s) {
            return .failure("scheme contains characters that are not allowed.")
        }
        let xcodebuildPath = "/usr/bin/xcodebuild"
        guard FileManager.default.fileExists(atPath: xcodebuildPath) else {
            return .failure("xcodebuild not found at /usr/bin/xcodebuild. Install Xcode command line tools first.")
        }
        guard let project = findXcodeProject(in: context.workspaceRoot) else {
            return .failure("No .xcodeproj/.xcworkspace found in the workspace root. Open a project first.")
        }
        let scheme: String
        if let s = explicitScheme, !s.isEmpty {
            scheme = s
        } else if let discovered = firstScheme(for: project, workspaceRoot: context.workspaceRoot) {
            scheme = discovered
        } else {
            return .failure("No scheme found for project '\(project.url.lastPathComponent)'. Pass scheme explicitly.")
        }
        var arguments: [String] = []
        if project.isWorkspace {
            arguments += ["-workspace", project.url.path]
        } else {
            arguments += ["-project", project.url.path]
        }
        arguments += [
            "-scheme", scheme,
            "-destination", destination,
            "-only-testing:\(testId)",
            "test"
        ]
        let run: (exitCode: Int32, stdout: String, stderr: String)
        do {
            run = try runProcess(executablePath: xcodebuildPath, arguments: arguments, workingDirectory: context.workspaceRoot)
        } catch {
            return .failure("xcodebuild execution failed: \(error.localizedDescription)")
        }
        let combined = run.stdout + "\n" + run.stderr
        let succeeded = combined.contains("** TEST SUCCEEDED **")
        let status = succeeded && run.exitCode == 0 ? "Passed" : "Failed"
        let tail = String(combined.suffix(2000))
        return .success("Single test \(testId) — \(status) (\(project.url.lastPathComponent) / \(scheme))\n\(tail)", data: [
            "status": status,
            "testId": testId,
            "scheme": scheme,
            "exitCode": "\(run.exitCode)"
        ])
    }

    private func isValidTestId(_ value: String) -> Bool {
        if value.contains(" ") || value.contains("\n") || value.contains("\r") { return false }
        if value.components(separatedBy: "/").count < 2 { return false }
        let forbidden = CharacterSet(charactersIn: ";|&$`\"'<>\\!(){}[]*?~#")
        if value.rangeOfCharacter(from: forbidden) != nil { return false }
        if value.contains("..") { return false }
        return true
    }

    private func hasUnsafeShellCharacters(_ value: String) -> Bool {
        let forbidden = CharacterSet(charactersIn: ";|&$`\"'<>\\!()\n\r")
        return value.rangeOfCharacter(from: forbidden) != nil
    }

    private func findXcodeProject(in workspaceRoot: URL) -> (url: URL, isWorkspace: Bool)? {
        let fm = FileManager.default
        if let top = try? fm.contentsOfDirectory(at: workspaceRoot, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]) {
            for item in top where item.pathExtension == "xcworkspace" { return (item, true) }
            for item in top where item.pathExtension == "xcodeproj" { return (item, false) }
        }
        guard let enumerator = fm.enumerator(at: workspaceRoot, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]) else { return nil }
        var foundProject: URL?
        for case let url as URL in enumerator {
            let name = url.lastPathComponent
            if name == ".git" || name == "build" || name == "DerivedData" || name == "Pods" {
                enumerator.skipDescendants()
                continue
            }
            if url.pathExtension == "xcworkspace" { return (url, true) }
            if url.pathExtension == "xcodeproj" && foundProject == nil { foundProject = url }
        }
        if let found = foundProject { return (found, false) }
        return nil
    }

    private func firstScheme(for project: (url: URL, isWorkspace: Bool), workspaceRoot: URL) -> String? {
        var arguments: [String] = []
        if project.isWorkspace {
            arguments += ["-workspace", project.url.path]
        } else {
            arguments += ["-project", project.url.path]
        }
        arguments += ["-list", "-json"]
        guard let run = try? runProcess(executablePath: "/usr/bin/xcodebuild", arguments: arguments, workingDirectory: workspaceRoot) else { return nil }
        guard let data = run.stdout.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        if let projectInfo = json["project"] as? [String: Any],
           let schemes = projectInfo["schemes"] as? [String],
           let first = schemes.first { return first }
        if let workspaceInfo = json["workspace"] as? [String: Any],
           let schemes = workspaceInfo["schemes"] as? [String],
           let first = schemes.first { return first }
        return nil
    }

    private func runProcess(executablePath: String, arguments: [String], workingDirectory: URL) throws -> (exitCode: Int32, stdout: String, stderr: String) {
        let fm = FileManager.default
        let tmp = fm.temporaryDirectory
        let outURL = tmp.appendingPathComponent("assist-\(UUID().uuidString)-out.txt")
        let errURL = tmp.appendingPathComponent("assist-\(UUID().uuidString)-err.txt")
        fm.createFile(atPath: outURL.path, contents: nil)
        fm.createFile(atPath: errURL.path, contents: nil)
        guard let outHandle = try? FileHandle(forWritingTo: outURL),
              let errHandle = try? FileHandle(forWritingTo: errURL) else {
            throw NSError(domain: "AssistTestRunSingleTool", code: 1, userInfo: [NSLocalizedDescriptionKey: "Could not create temporary output files for process output."])
        }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executablePath)
        process.arguments = arguments
        process.currentDirectoryURL = workingDirectory
        process.standardOutput = outHandle
        process.standardError = errHandle
        do {
            try process.run()
        } catch {
            try? outHandle.close()
            try? errHandle.close()
            try? fm.removeItem(at: outURL)
            try? fm.removeItem(at: errURL)
            throw error
        }
        process.waitUntilExit()
        try? outHandle.close()
        try? errHandle.close()
        let stdout = (try? String(contentsOf: outURL, encoding: .utf8)) ?? ""
        let stderr = (try? String(contentsOf: errURL, encoding: .utf8)) ?? ""
        try? fm.removeItem(at: outURL)
        try? fm.removeItem(at: errURL)
        return (process.terminationStatus, stdout, stderr)
    }
}

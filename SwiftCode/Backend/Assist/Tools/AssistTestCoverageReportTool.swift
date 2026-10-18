import Foundation

public struct AssistTestCoverageReportTool: AssistTool {
    public let id = "test_coverage_report"
    public let name = "Test Coverage Report"
    public let description = "Runs xcodebuild test with code coverage enabled and reports the coverage summary plus pass/fail."

    public init() {}

    public var capability: ToolCapability { .testing }
    public var riskLevel: ToolRiskLevel { .execution }

    public var parametersSchema: JSONSchema {
        JSONSchema(
            type: "object",
            description: "Runs the test suite with code coverage enabled and parses coverage output.",
            properties: [
                "scheme": JSONSchema(type: "string", description: "Scheme to test. Defaults to the first scheme listed by xcodebuild."),
                "destination": JSONSchema(type: "string", description: "xcodebuild destination. Default: platform=macOS.")
            ],
            required: []
        )
    }

    public func execute(input: [String: Any], context: AssistContext) async throws -> AssistToolResult {
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

        let buildDir = context.workspaceRoot.appendingPathComponent("build")
        try? FileManager.default.createDirectory(at: buildDir, withIntermediateDirectories: true)
        let resultBundle = buildDir.appendingPathComponent("TestResults.xcresult")

        var arguments: [String] = []
        if project.isWorkspace {
            arguments += ["-workspace", project.url.path]
        } else {
            arguments += ["-project", project.url.path]
        }
        arguments += [
            "-scheme", scheme,
            "-destination", destination,
            "-enableCodeCoverage", "YES",
            "-resultBundlePath", resultBundle.path,
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
        let failed = combined.contains("** TEST FAILED **") || run.exitCode != 0
        let status = succeeded && !failed ? "Passed" : "Failed"
        let coverageLines = combined.components(separatedBy: .newlines).filter { $0.lowercased().contains("coverage") && $0.contains("%") }
        let percentages = coverageLines.flatMap { extractPercentages(from: $0) }
        let coverageText: String
        if percentages.isEmpty {
            coverageText = "No coverage percentage lines in xcodebuild output. Full coverage detail lives in \(resultBundle.path) when the test run produced a result bundle."
        } else {
            let formatted = percentages.map { String(format: "%.1f%%", $0) }.joined(separator: ", ")
            coverageText = "Coverage values found: \(formatted)"
        }
        let executedLine = combined.components(separatedBy: .newlines).first { $0.contains("Executed") && $0.contains("tests") } ?? ""
        var output = "Test Coverage — \(project.url.lastPathComponent) / \(scheme): \(status)\n\(coverageText)"
        if !executedLine.isEmpty {
            output += "\n\(executedLine.trimmingCharacters(in: .whitespaces))"
        }
        if !coverageLines.isEmpty {
            output += "\n" + coverageLines.prefix(10).joined(separator: "\n")
        }
        output += "\nResult bundle: \(resultBundle.path)"
        return .success(output, data: [
            "status": status,
            "scheme": scheme,
            "coverage": percentages.map { String($0) }.joined(separator: ","),
            "resultBundle": resultBundle.path,
            "exitCode": "\(run.exitCode)"
        ])
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

    private func extractPercentages(from line: String) -> [Double] {
        var values: [Double] = []
        let tokens = line.components(separatedBy: .whitespaces)
        for token in tokens where token.hasSuffix("%") {
            let numberPart = token.dropLast().trimmingCharacters(in: CharacterSet(charactersIn: "(),"))
            if let value = Double(numberPart) { values.append(value) }
        }
        return values
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
            throw NSError(domain: "AssistTestCoverageReportTool", code: 1, userInfo: [NSLocalizedDescriptionKey: "Could not create temporary output files for process output."])
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

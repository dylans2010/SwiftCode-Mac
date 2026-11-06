import Foundation

public struct AssistPerformanceBenchmarkTool: AssistTool {
    public let id = "performance_benchmark"
    public let name = "Performance Benchmark"
    public let description = "Runs an allow-listed command N times via Process and reports average, minimum, and maximum wall time plus exit codes."

    public init() {}

    public var capability: ToolCapability { .diagnostics }
    public var riskLevel: ToolRiskLevel { .execution }

    public var parametersSchema: JSONSchema {
        JSONSchema(
            type: "object",
            description: "Benchmarks an allow-listed executable. No shell, no network, no installs.",
            properties: [
                "command": JSONSchema(type: "string", description: "Required. Executable path, one of /usr/bin/time, /usr/bin/xcodebuild, /usr/bin/swift, /bin/ls, /usr/bin/du. May include arguments after the executable."),
                "arguments": JSONSchema(type: "string", description: "Optional extra arguments, space-separated. Combined with any arguments in command."),
                "iterations": JSONSchema(type: "string", description: "Run count. Default: 3. Maximum: 10.")
            ],
            required: ["command"]
        )
    }

    public func execute(input: [String: Any], context: AssistContext) async throws -> AssistToolResult {
        guard let commandRaw = (input["command"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines), !commandRaw.isEmpty else {
            return .failure("Missing required parameter: command")
        }
        let allowed: Set<String> = ["/usr/bin/time", "/usr/bin/xcodebuild", "/usr/bin/swift", "/bin/ls", "/usr/bin/du"]
        var tokens = commandRaw.components(separatedBy: .whitespaces).filter { !$0.isEmpty }
        guard let executable = tokens.first else {
            return .failure("command is empty.")
        }
        guard allowed.contains(executable) else {
            return .failure("command '\(executable)' is not in the allow-list. Allowed: /usr/bin/time, /usr/bin/xcodebuild, /usr/bin/swift, /bin/ls, /usr/bin/du.")
        }
        tokens.removeFirst()
        var extraArguments: [String] = []
        if let argsString = input["arguments"] as? String {
            extraArguments = argsString.components(separatedBy: .whitespaces).filter { !$0.isEmpty }
        } else if let argsArray = input["arguments"] as? [String] {
            extraArguments = argsArray
        }
        let allArguments = tokens + extraArguments
        for arg in allArguments where hasUnsafeShellCharacters(arg) {
            return .failure("Argument '\(arg)' contains characters that are not allowed.")
        }
        guard FileManager.default.fileExists(atPath: executable) else {
            return .failure("Executable not found at '\(executable)'.")
        }
        let iterationsRaw = input["iterations"] as? String ?? (input["iterations"] as? Int).map { String($0) } ?? "3"
        guard let requested = Int(iterationsRaw.trimmingCharacters(in: .whitespacesAndNewlines)), requested >= 1 else {
            return .failure("iterations must be an integer of at least 1.")
        }
        let iterations = min(requested, 10)
        var durations: [Double] = []
        var exitCodes: [Int32] = []
        var lastOutput = ""
        for _ in 0..<iterations {
            let start = Date()
            do {
                let run = try runProcess(executablePath: executable, arguments: allArguments, workingDirectory: context.workspaceRoot)
                durations.append(Date().timeIntervalSince(start))
                exitCodes.append(run.exitCode)
                lastOutput = (run.stdout + "\n" + run.stderr).trimmingCharacters(in: .whitespacesAndNewlines)
            } catch {
                return .failure("Benchmark run failed: \(error.localizedDescription)")
            }
        }
        guard let minValue = durations.min(), let maxValue = durations.max(), !durations.isEmpty else {
            return .failure("No benchmark runs completed.")
        }
        let average = durations.reduce(0, +) / Double(durations.count)
        let output = "Benchmark '\(executable) \(allArguments.joined(separator: " "))' over \(iterations) run(s): avg \(String(format: "%.3f", average))s, min \(String(format: "%.3f", minValue))s, max \(String(format: "%.3f", maxValue))s. Exit codes: \(exitCodes.map { String($0) }.joined(separator: ", ")).\nLast run output tail:\n\(String(lastOutput.suffix(1000)))"
        return .success(output, data: [
            "executable": executable,
            "iterations": "\(iterations)",
            "averageSeconds": String(format: "%.3f", average),
            "minSeconds": String(format: "%.3f", minValue),
            "maxSeconds": String(format: "%.3f", maxValue),
            "exitCodes": exitCodes.map { String($0) }.joined(separator: ",")
        ])
    }

    private func hasUnsafeShellCharacters(_ value: String) -> Bool {
        let forbidden = CharacterSet(charactersIn: ";|&$`\"'<>\\!()\n\r")
        if value.rangeOfCharacter(from: forbidden) != nil { return true }
        return false
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
            throw NSError(domain: "AssistPerformanceBenchmarkTool", code: 1, userInfo: [NSLocalizedDescriptionKey: "Could not create temporary output files for process output."])
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

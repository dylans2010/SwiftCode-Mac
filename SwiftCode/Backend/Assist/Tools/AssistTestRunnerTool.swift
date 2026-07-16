import Foundation

public struct AssistTestRunnerTool: AssistTool {
    public let id = "project_test"
    public let name = "Run Tests"
    public let description = "Runs project tests using xcodebuild test command."

    public init() {}

    public func execute(input: [String: Any], context: AssistContext) async throws -> AssistToolResult {
        _ = input["path"] as? String ?? ""
        let scheme = input["scheme"] as? String ?? context.project?.name ?? "SwiftCode"

        await context.logger.info("Running tests for scheme: \(scheme)", toolId: id)

        #if os(macOS)
        do {
            // Build xcodebuild test command
            let projectPath = context.workspaceRoot.appendingPathComponent("SwiftCode.xcodeproj").path
            let destinationPlatform = "platform=iOS Simulator,name=iPhone 15,OS=latest"

            let arguments = [
                "-project", projectPath,
                "-scheme", scheme,
                "-destination", destinationPlatform,
                "test"
            ]

            await context.logger.info("Executing: xcodebuild \(arguments.joined(separator: " "))", toolId: id)

            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/xcodebuild")
            process.arguments = arguments

            let outputPipe = Pipe()
            let errorPipe = Pipe()
            process.standardOutput = outputPipe
            process.standardError = errorPipe

            try process.run()
            process.waitUntilExit()

            let outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()
            let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
            let output = String(data: outputData, encoding: .utf8) ?? ""
            let errorOutput = String(data: errorData, encoding: .utf8) ?? ""

            // Parse test results from xcodebuild output
            let (passed, failed, total) = parseTestResults(from: output + errorOutput)

            let resultData: [String: String] = [
                "passed": "\(passed)",
                "failed": "\(failed)",
                "total": "\(total)",
                "status": process.terminationStatus == 0 ? "Success" : "Failed",
                "exit_code": "\(process.terminationStatus)"
            ]

            if process.terminationStatus == 0 {
                return .success("Tests completed: \(passed) passed, \(failed) failed", data: resultData)
            } else {
                let errorSummary = extractErrorSummary(from: output + errorOutput)
                return .failure("Tests failed with exit code \(process.terminationStatus). \(errorSummary)")
            }
        } catch {
            return .failure("Failed to run tests: \(error.localizedDescription)")
        }
        #else
        return .failure("Test runner is only supported on macOS")
        #endif
    }

    private func parseTestResults(from output: String) -> (passed: Int, failed: Int, total: Int) {
        var passed = 0
        var failed = 0

        // Parse xcodebuild test output for test results
        // Format: "Test Case '-[TargetTests.TestClass testMethod]' passed (0.001 seconds)."
        let lines = output.components(separatedBy: .newlines)

        for line in lines {
            if line.contains("' passed (") {
                passed += 1
            } else if line.contains("' failed (") {
                failed += 1
            }
        }

        // Alternative: Look for test summary line
        // Format: "Test Suite 'All tests' passed at 2024-01-01 12:00:00.000."
        if let summaryLine = lines.first(where: { $0.contains("Executed") && $0.contains("tests") }) {
            // Format: "Executed 10 tests, with 2 failures (0 unexpected)"
            let components = summaryLine.components(separatedBy: " ")
            if let executedIndex = components.firstIndex(of: "Executed"),
               executedIndex + 1 < components.count,
               let total = Int(components[executedIndex + 1]) {
                if let failuresIndex = components.firstIndex(of: "failures"),
                   failuresIndex - 1 >= 0,
                   let failures = Int(components[failuresIndex - 1]) {
                    return (total - failures, failures, total)
                }
            }
        }

        let total = passed + failed
        return (passed, failed, total > 0 ? total : 0)
    }

    private func extractErrorSummary(from output: String) -> String {
        let lines = output.components(separatedBy: .newlines)
        var errors: [String] = []

        for line in lines {
            if line.contains("error:") || line.contains("FAILURE:") {
                errors.append(line.trimmingCharacters(in: .whitespaces))
                if errors.count >= 3 { break } // Limit to first 3 errors
            }
        }

        return errors.isEmpty ? "Check test output for details." : errors.joined(separator: " | ")
    }
}

import Foundation

public struct AssistBuildProjectTool: AssistTool {
    public let id = "project_build"
    public let name = "Build Project"
    public let description = "Builds the project using xcodebuild command."

    public init() {}

    public func execute(input: [String: Any], context: AssistContext) async throws -> AssistToolResult {
        let projectPath = input["project"] as? String ?? "SwiftCode.xcodeproj"
        let scheme = input["scheme"] as? String ?? context.project?.name ?? "SwiftCode"
        let configuration = input["configuration"] as? String ?? "Debug"

        await context.logger.info("Building project: \(projectPath), scheme: \(scheme)", toolId: id)

        #if os(macOS)
        do {
            let fullProjectPath = context.workspaceRoot.appendingPathComponent(projectPath).path
            let destinationPlatform = "platform=iOS Simulator,name=iPhone 15,OS=latest"

            let arguments = [
                "-project", fullProjectPath,
                "-scheme", scheme,
                "-configuration", configuration,
                "-destination", destinationPlatform,
                "clean", "build"
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

            // Parse build results
            let (succeeded, errors, warnings) = parseBuildResults(from: output + errorOutput)

            let resultData: [String: String] = [
                "status": succeeded ? "Success" : "Failed",
                "errors": "\(errors)",
                "warnings": "\(warnings)",
                "exit_code": "\(process.terminationStatus)"
            ]

            if process.terminationStatus == 0 {
                return .success("Build succeeded with \(warnings) warnings", data: resultData)
            } else {
                let errorSummary = extractBuildErrors(from: output + errorOutput)
                return .failure("Build failed with \(errors) errors. \(errorSummary)")
            }
        } catch {
            return .failure("Failed to build project: \(error.localizedDescription)")
        }
        #else
        return .failure("Build tool is only supported on macOS")
        #endif
    }

    private func parseBuildResults(from output: String) -> (succeeded: Bool, errors: Int, warnings: Int) {
        var errorCount = 0
        var warningCount = 0
        var buildSucceeded = false

        let lines = output.components(separatedBy: .newlines)

        for line in lines {
            // Look for "BUILD SUCCEEDED" or "BUILD FAILED"
            if line.contains("** BUILD SUCCEEDED **") {
                buildSucceeded = true
            } else if line.contains("** BUILD FAILED **") {
                buildSucceeded = false
            }

            // Count errors and warnings from summary
            if line.contains("error generated") || line.contains("errors generated") {
                let components = line.components(separatedBy: " ")
                if let errorIndex = components.firstIndex(where: { $0.contains("error") }),
                   errorIndex > 0,
                   let count = Int(components[errorIndex - 1]) {
                    errorCount = count
                }
            }

            if line.contains("warning generated") || line.contains("warnings generated") {
                let components = line.components(separatedBy: " ")
                if let warningIndex = components.firstIndex(where: { $0.contains("warning") }),
                   warningIndex > 0,
                   let count = Int(components[warningIndex - 1]) {
                    warningCount = count
                }
            }
        }

        return (buildSucceeded, errorCount, warningCount)
    }

    private func extractBuildErrors(from output: String) -> String {
        let lines = output.components(separatedBy: .newlines)
        var errors: [String] = []

        for line in lines {
            if line.contains("error:") {
                errors.append(line.trimmingCharacters(in: .whitespaces))
                if errors.count >= 3 { break } // Limit to first 3 errors
            }
        }

        return errors.isEmpty ? "Check build output for details." : errors.joined(separator: " | ")
    }
}

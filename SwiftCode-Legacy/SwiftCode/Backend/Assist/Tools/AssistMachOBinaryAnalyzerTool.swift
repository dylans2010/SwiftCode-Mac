//
//  AssistMachOBinaryAnalyzerTool.swift
//  SwiftCode
//

import Foundation

public struct AssistMachOBinaryAnalyzerTool: AssistTool {
    public let id = "mach_o_binary_analyzer"
    public let name = "Mach-O Binary Analyzer"
    public let description = "Inspects built application binaries, architectures (arm64, x86_64), and linked dynamic libraries via otool and file."

    public init() {}

    public var capability: ToolCapability { .diagnostics }
    public var riskLevel: ToolRiskLevel { .safeRead }

    public var parametersSchema: JSONSchema {
        JSONSchema(
            type: "object",
            description: "Analyzes compiled binaries or frameworks in Products / DerivedData for architectures and linked dylibs.",
            properties: [
                "binaryPath": JSONSchema(type: "string", description: "Relative or absolute path to the compiled binary or executable file.")
            ],
            required: ["binaryPath"]
        )
    }

    public func execute(input: [String: Any], context: AssistContext) async throws -> AssistToolResult {
        guard let binPath = input["binaryPath"] as? String else {
            return .failure("Missing required parameter: binaryPath")
        }

        let resolvedURL = binPath.hasPrefix("/") ? URL(fileURLWithPath: binPath) : context.workspaceRoot.appendingPathComponent(binPath)
        guard FileManager.default.fileExists(atPath: resolvedURL.path) else {
            return .failure("Binary file not found at: \(resolvedURL.path)")
        }

        // 1. Run file command to check architecture
        let fileProc = Process()
        fileProc.executableURL = URL(fileURLWithPath: "/usr/bin/file")
        fileProc.arguments = [resolvedURL.path]
        let filePipe = Pipe()
        fileProc.standardOutput = filePipe
        fileProc.standardError = filePipe
        try? fileProc.run()
        fileProc.waitUntilExit()
        let fileOut = String(decoding: filePipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)

        // 2. Run otool -L to check linked dynamic libraries
        let otoolProc = Process()
        otoolProc.executableURL = URL(fileURLWithPath: "/usr/bin/xcrun")
        otoolProc.arguments = ["otool", "-L", resolvedURL.path]
        let otoolPipe = Pipe()
        otoolProc.standardOutput = otoolPipe
        otoolProc.standardError = otoolPipe
        try? otoolProc.run()
        otoolProc.waitUntilExit()
        let otoolOut = String(decoding: otoolPipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)

        var report = "### Mach-O Binary Analysis for `\(resolvedURL.lastPathComponent)`:\n\n"
        report += "#### Architecture & File Type:\n`\(fileOut)`\n\n"

        let dylibLines = otoolOut.components(separatedBy: .newlines).filter { !$0.isEmpty }
        report += "#### Linked Dynamic Libraries (\(dylibLines.count)):\n"
        for line in dylibLines.prefix(25) {
            report += "- `\(line.trimmingCharacters(in: .whitespaces))`\n"
        }

        return .success(report)
    }
}
